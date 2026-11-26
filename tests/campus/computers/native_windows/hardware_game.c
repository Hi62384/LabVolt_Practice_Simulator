#define UNICODE
#define _UNICODE
#define COBJMACROS
#include <windows.h>
#include <d3d11.h>
#include <stdio.h>


enum { FrameWidth = 320, FrameHeight = 200 };

static ID3D11Device *device;
static IDXGISwapChain *swap;
static ID3D11DeviceContext *context;
static ID3D11Texture2D *target;
static ID3D11RenderTargetView *view;
static int points;

static BOOL render(void)
{
    const FLOAT blue[4] = {19.f / 255.f, 134.f / 255.f, 217.f / 255.f, 1.f};
    const FLOAT orange[4] = {208.f / 255.f, 81.f / 255.f, 38.f / 255.f, 1.f};
    ID3D11DeviceContext_ClearRenderTargetView(context, view, points % 2 == 0 ? blue : orange);
    return SUCCEEDED(IDXGISwapChain_Present(swap, 0, 0));
}

static LRESULT CALLBACK game_window(HWND window, UINT message, WPARAM key, LPARAM detail)
{
    switch (message) {
        case WM_LBUTTONDOWN:
        case WM_KEYDOWN:
            if (message == WM_LBUTTONDOWN || key == VK_SPACE || key == VK_F9) {
                ++points;
                if (!render()) PostQuitMessage(6);
                wchar_t title[72];
                swprintf_s(title, 72, L"Campus Hardware Game - Score %d", points);
                SetWindowTextW(window, title);
            }
            return 0;
        case WM_PAINT: {
            PAINTSTRUCT paint;
            BeginPaint(window, &paint);
            EndPaint(window, &paint);
            return 0;
        }
        case WM_DESTROY: PostQuitMessage(0); return 0;
        default: return DefWindowProcW(window, message, key, detail);
    }
}

int WINAPI wWinMain(HINSTANCE app, HINSTANCE prior, PWSTR cmd, int show)
{
    (void)prior; (void)cmd; (void)show;

    WNDCLASSW cls = {0};
    cls.lpfnWndProc = game_window;
    cls.hInstance = app;
    cls.lpszClassName = L"CampusHardwareGame";
    if (!RegisterClassW(&cls)) return 8;
    HWND window = CreateWindowExW(0, cls.lpszClassName, L"Campus Hardware Game",
        WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT, 480, 300, NULL, NULL, app, NULL);
    if (!window) return 9;
        DXGI_SWAP_CHAIN_DESC sd = {0};
    sd.BufferDesc.Width = FrameWidth;
    sd.BufferDesc.Height = FrameHeight;
    sd.BufferDesc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    sd.SampleDesc.Count = 1;
    sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    sd.BufferCount = 2;
    sd.OutputWindow = window;
    sd.Windowed = TRUE;
    sd.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
    HRESULT hr = D3D11CreateDeviceAndSwapChain(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL,
        0, D3D11_SDK_VERSION, &sd, &swap, &device, NULL, &context);
    if (FAILED(hr)) { fprintf(stderr, "Direct3D swap chain failed: 0x%08lx\n", (unsigned long)hr); return 10; }
    if (FAILED(IDXGISwapChain_GetBuffer(swap, 0, &IID_ID3D11Texture2D, (void **)&target))) return 11;
    if (FAILED(ID3D11Device_CreateRenderTargetView(device, (ID3D11Resource *)target, NULL, &view))) return 12;
    ShowWindow(window, SW_SHOW);
    if (!render()) return 13;
    MSG event = {0};
    while (GetMessageW(&event, NULL, 0, 0) > 0) {
        TranslateMessage(&event);
        DispatchMessageW(&event);
    }
    ID3D11RenderTargetView_Release(view);
    ID3D11Texture2D_Release(target);
    IDXGISwapChain_Release(swap);
    ID3D11DeviceContext_Release(context);
    ID3D11Device_Release(device);
    return (int)event.wParam;
}
