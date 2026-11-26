# Campus OS test files

This folder covers all 145 file extensions in the Campus OS import registry. Use **Files → Import file** to copy a sample into Downloads, then open it in Campus OS. A supported import type may have a viewer, a Code Editor mode, or storage only.

| Folder | What to check |
| --- | --- |
| `applications` | Run or install **Campus Click Test.exe**. Open **Campus Click Setup.exe**, choose **Run setup**, click its installer window, then import **Installed Click.exe**. Open either **Campus Click Package.msi** or **Campus Click Package.msix** and select **Install into Campus OS**. **Campus Hardware Game.exe** uses hardware Direct3D 11. Click the live game or press Space or F9 to update its counter. **sample.campusapp** uses the Campus OS web runtime. |
| `source` | Text and Code Editor syntax. Import `sample.html`, `sample.css` and `sample.js` together for the web preview. Code execution requires a matching runtime. |
| `images`, `audio`, `video` | Import, preview and playback where the renderer supports the format. |
| `models` | GLB, glTF, OBJ and STL open in 3D Viewer. PLY, FBX, DAE, 3MF and Blender files are storage samples. |
| `documents`, `archives` | PDF viewing and ZIP browsing/extraction. The other document and archive formats test file import and storage. |
| `fonts`, `windows-inspection` | Font storage, Windows package metadata, and DLL handling. The MSI, MSIX and MSIX bundle examples are inspection fixtures. |

The Windows game and setup sources are in `tests/campus/computers/native_windows`. The other files are small synthetic fixtures or come from the repository's sample archive. Every Windows launch requires local approval.
