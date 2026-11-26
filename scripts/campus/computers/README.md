# Campus OS

Campus OS runs on the existing workstation session and virtual drive. Workstations preserve windows while powered on. Power-off still clears a public workstation's temporary files. Attachments, saved files, and assignment actions continue through the existing device and school authority.

Files and Terminal share the same virtual workspace. Terminal commands are help, clear, pwd, ls, cd, mkdir, touch, cat, echo, open, and date. Folder mutations require a device that supports folders. The workstation's internal drive supports recoverable deletion. The USB workflow continues to use its existing explicit permanent-delete confirmation and archive writes.

## Code Editor and runtimes

The Windows desktop uses the bundled Monaco Editor 0.55.1. Its MIT license and third-party notices are inside the asset ZIP. The editor serves these fixed assets from a temporary loopback address. Workspace files stay in the game's virtual drive and enter the editor as source text. A native text editor remains available if Chromium cannot start.

Use **Run** or **Ctrl+Enter** in the Code Editor, or `run <file>` in Terminal. JSON validation works locally. Previously saved `.campus` files still open as text.

To enable remote execution on the game host, set `LABVOLT_JUDGE0_URL` to an HTTPS Judge0 CE deployment before starting LabVolt. Set `LABVOLT_JUDGE0_TOKEN` only if the deployment requires an authentication token. A token-free loopback endpoint is supported for local testing. Configure the deployment to deny outbound networking from submissions and enforce its own execution quotas. Clients cannot configure a compiler endpoint or receive the host token.

**Settings → Programming → Test Connection** lists the runtimes returned by the provider. **Run** asks before sending the selected source file and optional standard input. **Stop** ends locally tracked execution. An accepted remote job may continue until its provider-enforced limit. The integration supports single-file submissions on the host.

| Source | Editing | Execution |
| --- | --- | --- |
| HTML, CSS, JavaScript | Monaco language services include contextual suggestions and diagnostics. The JavaScript worker resolves imports from available workspace sources in the current folder and its subfolders. | Offline preview in a separate Campus OS window |
| TypeScript | Monaco checks types across imports from available workspace sources in the current folder and its subfolders. | Requires a compatible Judge0 runtime |
| JSON | Monaco schema-aware editing and diagnostics where a schema is available | Local validation |
| Python, C, C++, C#, Java, Go, Rust, Ruby, Lua, PHP, Kotlin and other mapped extensions | Monaco syntax support where available and word-based completion | The selected Judge0 deployment determines the available runtimes |
| Other files | Plain text or the available Monaco language mode | A compatible provider runtime may be selected explicitly |

The opt-in live test at `tests/campus/computers/test_ide_live.gd` submits original Python, C, C++, C#, and Java fixtures to the configured Judge0 endpoint. It uses no workspace files. The graphical test at `tests/campus/computers/test_ide_project_symbols.gd` verifies that Monaco resolves an imported TypeScript symbol and reports its type mismatch.

## Application packages and Windows files

A `.campusapp` file is a ZIP archive under 8 MiB. It contains a root `manifest.json` with `schema: 1`, a namespaced `id`, `name`, `publisher`, a three-part `version`, `description`, `runtime: "web"`, and an `entry` pointing to a packaged HTML file. An optional `icon` points to a PNG. Packages can contain HTML, CSS, JavaScript, WebAssembly and supported media assets. The preview checks archive paths, file/directory conflicts, file types, an unpacked size limit of 16 MiB, and unsupported permissions or dependencies. Publisher text is self-reported.

Open a package in **Files** and choose **Install**. The confirmation shows the package details, size, and installation folder on the active virtual drive. Choose whether to add a shortcut to the desktop or Start menu. If the package is already installed, this workflow offers update or repair. You can also launch apps from **Settings → Installed Apps**. Uninstall from Installed Apps and choose whether to keep saved application data. Packages and app data on a USB drive follow that drive. A public workstation's internal drive remains temporary.

[Campus Notes](../../../tests/campus/computers/sample_apps/campus-notes.campusapp) is a sample package. Open its raw download URL in the Campus OS Browser and use the Browser's download command. The [source files](../../../tests/campus/computers/sample_apps/campus_notes) show the manifest, interface, and storage API.

Web previews resolve assets from the selected file's folder in the virtual drive. HTML previews start from the selected page. JavaScript and CSS previews use `index.html` when present and otherwise start from a generated page that loads the selected file. Run compiles no web assets and sends no web source to the provider.

Each app runs in a separate Chromium context at `https://campus-app.invalid/`. Only its packaged resources are served. Fetch `/__campus__/state.json` to read its saved JSON object, or PUT a replacement JSON object up to 4 KiB. The desktop submits changes to the active virtual drive through the same session authority used for file saves. No host filesystem paths are passed to the app. The runtime disables outgoing requests, privileged game bindings, external navigation, and downloads in app windows. The bundled Windows gdCEF build runs without Chromium's OS-level subprocess sandbox.

Windows executables and MSI, MSIX, and MSIX bundle packages can be stored and transferred in the virtual filesystem within its download limit. Opening a PE executable in Files reports its architecture, desktop or console subsystem, and native or .NET entry point. The preview parses its headers and checks file bounds without loading the executable. Windows packages open in the same viewer and show their storage-only status.

The controlled native fixture uses the firmware broker's capability-free AppContainer, a fresh profile, an explicit child environment, a restricted list of inherited handles, and a kill-on-close Job Object. Its writable test directory has an AppContainer-specific ACL. The job limits resource use and lifetime. The AppContainer and ACLs enforce the access boundary. Standard AppContainer can still access some system resources and COM objects. LPAC reduces default access further and needs separate compatibility verification. [Microsoft AppContainer guidance](https://learn.microsoft.com/en-us/windows/win32/secauthz/implementing-an-appcontainer)

A Campus OS launcher still needs an authenticated broker connection, a per-application virtual-drive staging and commit protocol, bounded window capture owned by that broker, and lifecycle tests for installer and game compatibility. Full-trust MSIX and unrestricted Windows Installer execution grant access outside the requested boundary. The Files preview does not launch those packages. [Microsoft MSIX isolation overview](https://learn.microsoft.com/en-us/windows/msix/msix-containerization-overview)

From Visual Studio x64 Developer PowerShell, run `tests/campus/computers/native_windows/test_window_capture.ps1 -VerifyGpuAndInput` to verify the controlled executable. The fixture checks the AppContainer token, denies a private file read and machine registry write, and writes to its scoped directory. The optional mode sends F9 to the verified fixture window, reads back a Direct3D hardware render target inside the guest, and captures the new color after the guest paints it. Native swap-chain capture, audio, and player-supplied executables are outside this fixture.

The diagnostic runs `-DesktopIsolation` and `-LessPrivileged` also require a one-process job, block host clipboard access, and check the suspended process token against a private DACL before resuming it. The LPAC check additionally verifies that the token cannot read a resource granted to All Application Packages. On the test machine, both desktop-isolation variants reached the access check and then exited at Windows GUI initialization with `0xC0000142`. The regular AppContainer fixture passed its capture, input, and GPU readback checks. Campus OS continues to store and inspect Windows files while the launcher is unavailable.
