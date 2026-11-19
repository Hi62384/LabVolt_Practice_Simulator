# Embedded browser runtime

The Windows x64 runtime in this folder is a local build of [gdCEF 0.21.0](https://github.com/Lecrapouille/gdcef/releases/tag/v0.21.0-godot4) against Godot 4.5. Upstream distributes 0.21.0 prebuilt for Godot 4.7, which this project cannot load. `VERSION` records the source commit, CEF version, and Godot version. `LICENSE` is the gdCEF license. `labvolt_gdcef_0_21.patch` records the changes for virtual downloads, blocked host file dialogs, and isolated in-memory browser sessions. Windows runtime files use Git LFS because `libcef.dll` exceeds GitHub's normal file limit.

The game uses one CEF runtime per process. Browser tabs on a device share that device session's cookies, and a new device session gets a separate in-memory context. Closing a session closes its browser tabs and releases its context. The browser is incognito and remote debugging is disabled. Chromium's native file dialog is canceled in C++. The game's Attach button supplies a selected virtual document or current-phone photo to a top-level HTML file input.

Campus OS handles Chromium download events, including attachment responses to website form submissions. Each tab uses a private scratch directory in the game's user data with generated filenames. The callback cancels transfers above 256 KB and returns bounded bytes to the app. The app validates type and contents and asks for confirmation before writing to the computer's virtual Downloads folder. Powered-off public workstations clear those files. Players can copy them to an attached USB drive to retain them.

This build supports the in-game campus PCs, laptops, and phones on Windows x64. Native Linux, macOS, Android, iOS, and web exports need separately supported renderer builds.

To rebuild, check out gdCEF commit `d3d58fc9f37dfc3f951f7ac6caa67ecf7a267539`, apply `labvolt_gdcef_0_21.patch`, set `GODOT_VERSION = "4.5"` in its `build.py`, install its `requirements.txt`, and run `build.py` from a Visual Studio x64 Developer Command Prompt. Copy only its `cef_artifacts/windows` runtime, `VERSION`, and `LICENSE` into this folder. The patch was checked against that commit.

After exporting the Windows preset, run `cef_artifacts/package_windows.ps1 -ExportDirectory <folder-containing-LabVolt.exe>` to copy the CEF subprocess, resources, and locales beside the executable. Godot exports the extension DLL and `libcef.dll` but not all CEF sidecars.

The isolated browser fixture in `tests/campus/computers/test_browser_runtime.gd` passed in a normal Windows run, including public HTTPS, address and history controls, a loopback login through forwarded mouse input, same-device tab login sharing, new-device cookie separation, virtual-file and phone-photo uploads, an iframe host-picker block, and close/reopen. It also passed against the exported Windows executable and PCK. The fixture's loopback server is `browser_fixture_server.py`.
