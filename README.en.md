# Dormer

**Run Windows apps on your Mac, no terminal required.** · [Español](README.md)

Dormer is a free, open-source, native macOS app that installs and runs Windows programs using [Wine](https://www.winehq.org). Each program (or group of programs) lives in its own **bottle**: an isolated environment with its own "C: drive". No accounts, no telemetry, no subscriptions.

> **Status: version 0.1.0, early development.** It works and is tested, but there is no published release to download yet. See [known limitations](#known-limitations) and the [plan](docs/DESIGN.md#7-plan-por-fases) (in Spanish).

## First, what it is and what it isn't

Wine **is not Windows**: it reimplements the Windows functions programs ask for, and the ones it lacks fail. Many classic programs work; others don't (those that depend on the full .NET Framework, WPF, WebView2, system drivers or anti-cheat, for example). Dormer makes Wine easy to use, but it can't make a program work if Wine can't. See the [compatibility table](docs/COMPATIBILITY.md), which includes what does **not** work.

If you need *any* Windows program to work, the closest thing to Windows is a virtual machine running Windows for Apple silicon (it needs a Windows license). Dormer is not one.

## What it does

- **Everything from the app, no terminal:** downloads Wine (SHA-256 verified), installs Rosetta if needed, creates bottles and runs `.exe`, `.msi` and `.bat` files (drag them in, or ⌘R).
- **Isolated bottles** (they can't see your Mac's disk by default) that you can duplicate, export to an `.aar` file and import on another Mac.
- **Programs with their real icon**, found through the shortcuts the installer leaves behind; pinnable, with their own arguments and environment variables.
- **`.app` launchers** to open a program with a double-click from Finder or the Dock.
- **Windows components** (Visual C++, .NET, fonts, DirectX…) through winetricks, from a searchable list.
- **Per-bottle settings:** Windows version, scale (DPI), Retina mode, environment variables and graphics backend (WineD3D, or DXMT as an experimental option for apps that need Direct3D 11).
- **Live Wine log** with filters, automatic suggestions (if a DLL is missing, it proposes the component) and "Copy for Report" without your user name or personal paths.
- Spanish and English. Accessible with VoiceOver and keyboard (code review; no user testing yet).

## Requirements

- An **Apple silicon** Mac running **macOS 14** or later.
- Free Wine engines for Mac are built for Intel processors, so they run through **Rosetta 2** (Dormer helps you install it). Apple will limit Rosetta starting with macOS 28.
- About 1.2 GB of disk for the Wine engine, plus whatever your programs take. Internet only for downloads you start.

## Install

1. **Disk image (`.dmg`):** once a release is published, download it from the *Releases* page, open the `.dmg` and drag Dormer to Applications. Its SHA-256 sits next to the file.
2. **Homebrew:** a cask template for a personal tap is in [packaging/homebrew](packaging/homebrew/dormer.rb); no tap is published yet.
3. **From source:** see below.

> **macOS notice (Gatekeeper):** Dormer is free software and is not signed with a paid Developer ID or notarized. The first time, macOS will block it: open *System Settings › Privacy & Security*, scroll to the message about Dormer and choose **"Open Anyway"**. (Since macOS 15, right-click › Open is no longer enough.)

## Getting started

1. Open Dormer: the assistant checks Rosetta, downloads the Wine engine (~230 MB, once) and creates your first bottle.
2. Drag an `.exe` or `.msi` installer onto the bottle (or press ⌘R). Dormer warns you if the file came from the internet.
3. When it finishes, the program shows up in the list: double-click to open it, pin it or create a launcher.
4. If it fails, check the **Logs** tab: it often suggests which component to install.

## Privacy and security

- **No telemetry, no accounts.** Everything is stored in `~/Library/Application Support/Dormer/` (plus the launchers you create).
- Downloads (Wine, winetricks, DXMT and its driver) use HTTPS and are checked against a size and SHA-256 pinned in the code.
- `.aar` bottle files are validated before being extracted.
- Wine is **not a security sandbox**: a malicious program inside a bottle can damage whatever the bottle can reach. Don't run software you don't trust. More in [SECURITY.md](SECURITY.md).

## Known limitations

- **Not everything works.** Tested and documented in [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md).
- **Power BI Desktop:** its installer fails inside Wine; don't expect it to work.
- **Notepad++:** the menu bar appears stacked in rows (a Wine issue with that app); it is usable.
- **Modern apps that need real Direct3D 11** (for example Audacity 4) won't open with WineD3D (it only offers level 9.3 on this Mac). With the **DXMT (experimental)** backend they do draw (tested with Audacity 4 and Warzone 2100); it uses a [patched Wine driver](packaging/wine/README.md) (in Spanish) that Dormer downloads. Few programs tested and no commercial game.
- **D3DMetal (Game Porting Toolkit):** you can import it, but it can't be used yet (it needs a Game Porting Toolkit build of Wine that Dormer doesn't include). DXVK is not offered (no releases since 2024).
- **Wine Gecko** (Windows' web engine) is unverified in isolated bottles.
- The `.dmg` build and automatic publishing (CI) are written but **not yet tested** on GitHub.

## Build and test

You need Xcode 16 or later (tested with Xcode 27.2).

```sh
git clone <repo-url> dormer && cd dormer
make run        # build and open Dormer.app
make test       # unit tests (no network)
make lint       # swift-format (and SwiftLint if installed: brew install swiftlint)
make dmg        # Release build into build/Dormer-<version>.dmg
make integration NPP=~/Downloads/npp.8.9.9.1.Installer.x64.exe   # real Wine test (~250 MB)
make probe INSTALLER=~/Downloads/setup.exe VERBS=vcrun2022 PROGRAM=name   # does this program work?
```

You can also open `Dormer.xcodeproj` and press ⌘R. With `DORMER_DATA_DIR=/folder`, test data won't touch your bottles.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) and the [Code of Conduct](CODE_OF_CONDUCT.md). Most helpful: test programs and report the result, including failures.

## License

[GPL-3.0-or-later](LICENSE). Wine, winetricks and DXMT are downloaded and run as independent components under their own licenses; see [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md). Dormer does not include or redistribute D3DMetal / Game Porting Toolkit.

Dormer is not affiliated with Microsoft or Apple. *Windows* is a trademark of Microsoft Corporation; *Mac* and *macOS* are trademarks of Apple Inc.
