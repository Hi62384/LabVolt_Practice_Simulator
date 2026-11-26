#define UNICODE
#define _UNICODE
#include <windows.h>

static BOOL install(HINSTANCE app)
{
    HRSRC resource = FindResourceW(app, MAKEINTRESOURCEW(101), RT_RCDATA);
    if (!resource) return FALSE;
    DWORD size = SizeofResource(app, resource);
    HGLOBAL loaded = LoadResource(app, resource);
    const void *image = LockResource(loaded);
    if (!image || !size) return FALSE;
    HANDLE output = CreateFileW(L"Installed Click.exe", GENERIC_WRITE, 0, NULL, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL);
    if (output == INVALID_HANDLE_VALUE) return FALSE;
    DWORD written = 0;
    BOOL success = WriteFile(output, image, size, &written, NULL) && written == size;
    CloseHandle(output);
    return success;
}

static LRESULT CALLBACK setup_window(HWND window, UINT message, WPARAM key, LPARAM data)
{
    switch (message) {
        case WM_LBUTTONDOWN:
            if (install((HINSTANCE)GetWindowLongPtrW(window, GWLP_HINSTANCE))) {
                PostQuitMessage(0);
            } else { PostQuitMessage(5); }
            return 0;
        case WM_PAINT: {
            PAINTSTRUCT paint;
            HDC context = BeginPaint(window, &paint);
            RECT bounds;
            GetClientRect(window, &bounds);
            HBRUSH background = CreateSolidBrush(RGB(75,113,61));
            FillRect(context, &bounds, background);
            DeleteObject(background);
            SetBkMode(context, TRANSPARENT);
            SetTextColor(context, RGB(255,255,255));
            DrawTextW(context, L"Click to install Campus Click Test", -1, &bounds, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
            EndPaint(window, &paint);
            return 0;
        }
        case WM_DESTROY: PostQuitMessage(1); return 0;
        default: return DefWindowProcW(window, message, key, data);
    }
}

int WINAPI wWinMain(HINSTANCE app, HINSTANCE prior, PWSTR command, int show)
{
    (void)prior; (void)command; (void)show;
    WNDCLASSW schema = {0};
    schema.lpfnWndProc = setup_window;
    schema.hInstance = app;
    schema.lpszClassName = L"CampusClickSetup";
    schema.hCursor = LoadCursorW(NULL, IDC_ARROW);
    if (!RegisterClassW(&schema)) return 2;
    HWND window = CreateWindowExW(0, schema.lpszClassName, L"Campus Click Setup", WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT, CW_USEDEFAULT, 470, 240, NULL, NULL, app, NULL);
    if (!window) return 3;
    ShowWindow(window, SW_SHOW);
    MSG event;
    while (GetMessageW(&event, NULL, 0, 0) > 0) {
        TranslateMessage(&event);
        DispatchMessageW(&event);
    }
    return (int)event.wParam;
}
