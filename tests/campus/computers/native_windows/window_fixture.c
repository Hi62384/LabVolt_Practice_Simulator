#define WIN32_LEAN_AND_MEAN
#define COBJMACROS
#include <windows.h>
#include <d3d11.h>
#include <stdio.h>

static BOOL render_color_on_gpu(COLORREF *color)
{
    ID3D11Device *device = NULL;
    ID3D11DeviceContext *context = NULL;
    ID3D11Texture2D *target = NULL;
    ID3D11Texture2D *readback = NULL;
    ID3D11RenderTargetView *view = NULL;
    HRESULT result = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0,
        NULL, 0, D3D11_SDK_VERSION, &device, NULL, &context);
    if (FAILED(result)) goto done;
    D3D11_TEXTURE2D_DESC desc = {0};
    desc.Width = desc.Height = 8;
    desc.MipLevels = desc.ArraySize = desc.SampleDesc.Count = 1;
    desc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    desc.BindFlags = D3D11_BIND_RENDER_TARGET;
    result = ID3D11Device_CreateTexture2D(device, &desc, NULL, &target);
    if (FAILED(result)) goto done;
    result = ID3D11Device_CreateRenderTargetView(device, (ID3D11Resource *)target, NULL, &view);
    if (FAILED(result)) goto done;
    desc.BindFlags = 0;
    desc.Usage = D3D11_USAGE_STAGING;
    desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    result = ID3D11Device_CreateTexture2D(device, &desc, NULL, &readback);
    if (FAILED(result)) goto done;
    const FLOAT clear[] = {208.0f / 255, 81.0f / 255, 38.0f / 255, 1.0f};
    ID3D11DeviceContext_ClearRenderTargetView(context, view, clear);
    ID3D11DeviceContext_CopyResource(context, (ID3D11Resource *)readback, (ID3D11Resource *)target);
    D3D11_MAPPED_SUBRESOURCE mapped;
    result = ID3D11DeviceContext_Map(context, (ID3D11Resource *)readback, 0, D3D11_MAP_READ, 0, &mapped);
    if (SUCCEEDED(result)) {
        const BYTE *pixel = (const BYTE *)mapped.pData;
        *color = RGB(pixel[0], pixel[1], pixel[2]);
        ID3D11DeviceContext_Unmap(context, (ID3D11Resource *)readback, 0);
    }
done:
    if (view) ID3D11RenderTargetView_Release(view);
    if (readback) ID3D11Texture2D_Release(readback);
    if (target) ID3D11Texture2D_Release(target);
    if (context) ID3D11DeviceContext_Release(context);
    if (device) ID3D11Device_Release(device);
    if (FAILED(result)) printf("Direct3D hardware render failed: 0x%08lx\n", (unsigned long)result);
    return SUCCEEDED(result);
}

static COLORREF window_color = RGB(19, 134, 217);
static BOOL verify_gpu;
static BOOL gpu_passed;

static LRESULT CALLBACK FixtureWindowProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam)
{
    if (message == WM_PAINT) {
        PAINTSTRUCT paint;
        HDC dc = BeginPaint(window, &paint);
        RECT client;
        GetClientRect(window, &client);
        HBRUSH color = CreateSolidBrush(window_color);
        FillRect(dc, &client, color);
        DeleteObject(color);
        EndPaint(window, &paint);
        return 0;
    }
    if (message == WM_KEYDOWN && wparam == VK_F9 && verify_gpu) {
        gpu_passed = render_color_on_gpu(&window_color);
        InvalidateRect(window, NULL, FALSE);
        fflush(stdout);
        return 0;
    }
    if (message == WM_TIMER) {
        DestroyWindow(window);
        return 0;
    }
    if (message == WM_DESTROY) {
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcW(window, message, wparam, lparam);
}

int wmain(int argc, wchar_t **argv)
{
    if (argc != 3 && argc != 4) return 20;
    verify_gpu = argc == 4;

    HANDLE token;
    DWORD isolated = 0;
    DWORD bytes = 0;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) return 21;
    BOOL inspected = GetTokenInformation(token, TokenIsAppContainer, &isolated, sizeof(isolated), &bytes);
    CloseHandle(token);
    if (!inspected || !isolated) return 22;

    HANDLE private_file = CreateFileW(argv[1], GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
    if (private_file != INVALID_HANDLE_VALUE) {
        CloseHandle(private_file);
        return 23;
    }
    if (GetLastError() != ERROR_ACCESS_DENIED) return 24;

    HKEY key;
    if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, L"SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion", 0, KEY_SET_VALUE, &key) != ERROR_ACCESS_DENIED)
        return 25;

    HANDLE app_data = CreateFileW(L"app-data.txt", GENERIC_WRITE, 0, NULL, CREATE_NEW, 0, NULL);
    if (app_data == INVALID_HANDLE_VALUE) return 26;
    CloseHandle(app_data);

    WNDCLASSW cls = {0};
    cls.lpfnWndProc = FixtureWindowProc;
    cls.hInstance = GetModuleHandleW(NULL);
    cls.lpszClassName = L"LabVoltFixtureClass";
    if (!RegisterClassW(&cls)) return 27;
    HWND window = CreateWindowExW(WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW, cls.lpszClassName,
        argv[2], WS_OVERLAPPEDWINDOW, 30, 30, 310, 200, NULL, NULL, cls.hInstance, NULL);
    if (!window) return 28;
    ShowWindow(window, SW_SHOWNOACTIVATE);
    UpdateWindow(window);
    printf("APP_CONTAINER_WINDOW %lu\n", GetCurrentProcessId());
    fflush(stdout);
    SetTimer(window, 1, 10000, NULL);
    MSG event;
    while (GetMessageW(&event, NULL, 0, 0) > 0)
        DispatchMessageW(&event);
    return !verify_gpu || gpu_passed ? 0 : 29;
}
