#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>

static LRESULT CALLBACK FixtureWindowProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam)
{
    if (message == WM_PAINT) {
        PAINTSTRUCT paint;
        HDC dc = BeginPaint(window, &paint);
        RECT client;
        GetClientRect(window, &client);
        HBRUSH color = CreateSolidBrush(RGB(19, 134, 217));
        FillRect(dc, &client, color);
        DeleteObject(color);
        EndPaint(window, &paint);
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
    if (argc != 3) return 20;

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
    return 0;
}
