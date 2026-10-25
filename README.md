# XOS

Windows optimization suite for gaming and privacy.

- `Playbook/`: the AME Wizard playbook. Options in `playbook.conf`, actions in `Configuration/custom.yml`, helper scripts in `Executables/`.
- `Toolkit/`: XOS Toolkit, a C# WPF app that applies the same changes one at a time and can undo them.
- `CpuService/`: CPU affinity companion, built together with the Toolkit.

## Supported Windows

Windows 10 22H2 (19045) and Windows 11 23H2 (22631), 25H2 (26200), 26H2 (26300).

## Installing

1. Get [AME Wizard](https://ameliorated.io). XOS is tested on Beta 0.8.4.
2. Drag the newest `XOS V<version>.apbx` into AME Wizard.
3. Pick the options. Defender and UAC handling, Edge, printing and wallpaper are either/or choices; taskbar cleanup, OneDrive, Teams, WSL, Photos, Xbox and AI features (Copilot, Recall) can each be left alone.
4. Apply, then reboot when the wizard finishes.

XOS changes system files and settings. Use it on an installation you can afford to reinstall.

Uninstall is on the Toolkit's Troubleshooting page. It restores Windows defaults, not your previous configuration, and removed Store apps have to be reinstalled by hand.

## Building

These third-party files are not in the repository:

| File | Source | Put it in |
|---|---|---|
| `MinSudo.exe` | [NanaRun](https://github.com/M2Team/NanaRun) | `Playbook/Executables/` and `Toolkit/` |
| `nvidiaProfileInspector.exe`, `nvidiaProfileInspector.exe.config`, `Reference.xml` | [Nvidia Profile Inspector](https://github.com/Orbmu2k/nvidiaProfileInspector) | `Toolkit/Nvidia Profile Inspector/` |
| `chocolatey-2.7.1.0.msi` | [Chocolatey](https://chocolatey.org/install) | `Toolkit/Resources/` |

Pack the playbook by zipping the contents of `Playbook/` (not the folder itself) into `XOS V<version>.apbx`. AME Wizard opens that archive directly.

## Credits

AME Wizard by [Ameliorated](https://ameliorated.io). MinSudo from NanaRun by M2Team (MIT). `DefenderOFF.ps1` is based on LeanAndMean by AveYo (MIT). Nvidia Profile Inspector by Orbmu2k. Chocolatey and the Open-Shell Fluent-Metro skins keep their own licences.
