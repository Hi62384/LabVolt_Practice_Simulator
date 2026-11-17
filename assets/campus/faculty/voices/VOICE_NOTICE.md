# Instructor speech assets

The 21 instructor profiles use distinct speaker identities from the Piper `en_US-libritts_r-medium` model, downloaded from [rhasspy/piper-voices v1.0.0](https://huggingface.co/rhasspy/piper-voices/tree/v1.0.0/en/en_US/libritts_r/medium). The model card in this folder identifies 904 speakers and credits the LibriTTS-R dataset under CC BY 4.0. Voice model and configuration are unmodified. The selected speaker IDs and speaking rates are game configuration.

The Windows runtime is the unmodified [rhasspy/piper 2023.11.14-2 standalone release](https://github.com/rhasspy/piper/releases/tag/2023.11.14-2). Its MIT license is included as `PIPER_LICENSE.md`. Windows releases copy the runtime and model beside `LabVolt.exe` using `scripts/campus/academics/package_windows_voices.ps1`.

For a source checkout on Windows, run `scripts/campus/academics/package_windows_voices.ps1` once without arguments. It prepares the ignored `.deps` runtime that the editor build can use. An exported game uses the sidecars prepared by the release workflow.

The teacher names and appearances are fictional game characters. No claim is made that a particular model speaker is the voice of a real person.
