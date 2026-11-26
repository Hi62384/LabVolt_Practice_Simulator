#define UNICODE
#define _UNICODE
#include <windows.h>
#include <stdint.h>
#include <stdio.h>

static int score = 0;
static LRESULT CALLBACK board(HWND window, UINT message, WPARAM key, LPARAM point)
{
    (void)point;
    switch (message) {
        case WM_KEYDOWN:
            if (key == VK_F9 || key == VK_SPACE) { ++score; InvalidateRect(window, NULL, TRUE); }
            return 0;
        case WM_LBUTTONDOWN:
            ++score; InvalidateRect(window, NULL, TRUE); return 0;
        case WM_PAINT: {
            PAINTSTRUCT paint;
            HDC context = BeginPaint(window, &paint);
            RECT client;
            GetClientRect(window, &client);
            HBRUSH fill = CreateSolidBrush(score == 0 ? RGB(19,134,217) : RGB(208,81,38));
            FillRect(context, &client, fill);
            DeleteObject(fill);
            wchar_t label[100];
            swprintf_s(label, 100, L"Campus Click Test: %d\nClick, Space, or F9", score);
            SetBkMode(context, TRANSPARENT);
            SetTextColor(context, RGB(255,255,255));
            DrawTextW(context, label, -1, &client, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
            EndPaint(window, &paint);
            return 0;
        }
        case WM_DESTROY: PostQuitMessage(0); return 0;
        default: return DefWindowProcW(window, message, key, point);
    }
}

int WINAPI wWinMain(HINSTANCE app, HINSTANCE prior, PWSTR cmd, int show)
{
    (void)prior; (void)cmd; (void)show;
    WNDCLASSW schema = {0};
    schema.lpfnWndProc = board;
    schema.hInstance = app;
    schema.lpszClassName = L"CampusClickTest";
    schema.hCursor = LoadCursorW(NULL, IDC_ARROW);
    if (!RegisterClassW(&schema)) return 2;
    HWND window = CreateWindowExW(0, schema.lpszClassName, L"Campus Click Test", WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT, CW_USEDEFAULT, 500, 320, NULL, NULL, app, NULL);
    if (!window) return 3;
    ShowWindow(window, SW_SHOW);
    MSG event;
    while (GetMessageW(&event, NULL, 0, 0) > 0) {
        TranslateMessage(&event);
        DispatchMessageW(&event);
    }
    return 0;
}
