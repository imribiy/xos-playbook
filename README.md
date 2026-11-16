# XOS Playbook

Windows optimization playbook for gaming and privacy, applied with [AME Wizard](https://ameliorated.io).

**Downloads:** see [Releases](https://github.com/imribiy/xos-playbook/releases). Builds marked *Pre-release* are developer betas. Report problems in [Issues](https://github.com/imribiy/xos-playbook/issues); search the existing ones first.

The companion app, XOS Toolkit, lives in [imribiy/xos-toolkit](https://github.com/imribiy/xos-toolkit). Every playbook release installs it.

## Supported Windows

Windows 10 22H2 (19045) and Windows 11 23H2 (22631), 25H2 (26200) and 26H2 (26300).

## Installing

1. Get [AME Wizard](https://ameliorated.io). XOS is tested on Beta 0.8.4.
2. Download `XOS V<version>.apbx` from [Releases](https://github.com/imribiy/xos-playbook/releases) and drag it into AME Wizard.
3. Pick the options. Defender and UAC handling, Edge, printing and wallpaper are either/or choices. Taskbar cleanup, OneDrive, Teams, WSL, Photos, Xbox and AI features (Copilot, Recall) can each be left alone.
4. Apply, then reboot when the wizard finishes.

XOS changes system files and settings. Use it on an installation you can afford to reinstall.

To uninstall, use the Troubleshooting page in XOS Toolkit. It restores Windows defaults, not your previous configuration. Removed Store apps have to be reinstalled by hand.

## Repository layout

- `playbook.conf`: playbook metadata and the options shown in AME Wizard.
- `Configuration/custom.yml`: every action the playbook runs.
- `Executables/`: helper scripts the actions call, `XSudo.exe` (the elevation helper), and the XOS wallpaper.

## Building

These files are not in the repository. Add them before packing:

| File | Source | Put it in |
|---|---|---|
| `XOS-Toolkit-Setup.exe` | Built from [xos-toolkit](https://github.com/imribiy/xos-toolkit), or taken from a release | `Executables/` |

Zip the contents of the repository (not the folder itself, and without `.git`, `.gitignore`, `README.md` or `LICENSE`) into `XOS V<version>.apbx` with the password `malte`, the AME Wizard default. AME Wizard opens that archive directly.

## License

Copyright (c) 2026 XOS (imribiy). Licensed under [CC BY-NC-ND 4.0](LICENSE): you may share XOS unchanged, with credit, for non-commercial purposes. You may not sell it, use it commercially, or distribute modified or rebranded versions.

## Credits

- AME Wizard by [Ameliorated](https://ameliorated.io).
- `Executables/XSudo.exe` is XSudo, the elevation helper, part of XOS; its source is in [xos-toolkit](https://github.com/imribiy/xos-toolkit) under `XSudo/`.
- `DefenderOFF.ps1` is based on LeanAndMean by AveYo (MIT).
