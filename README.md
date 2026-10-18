# :hammer_and_wrench: Strawberry MSVC Build Tools

This repository contains tools to build all the Strawberry Music Player dependencies with Visual Studio 2022 or 2026.

Instructions here are provided as-is, primarily intended for developers working on Strawberry for Windows.

If something here does not work as expected, consider opening a pull request to fix the issue. Due to lack of time, I can not offer much support.

### Requirements

* [Git for Windows](https://gitforwindows.org/)
* [Powershell 7](https://learn.microsoft.com/en-us/powershell/scripting/install/install-powershell-on-windows)
* [Visual Studio 2022 or 2026](https://visualstudio.microsoft.com/vs/)
* [Qt Visual Studio Tools](https://marketplace.visualstudio.com/items?itemName=TheQtCompany.QtVisualStudioTools2022)
* [CMake](https://cmake.org/)
* [Meson](https://mesonbuild.com/)
* [NASM](https://www.nasm.us/)
* [Strawberry Perl](https://strawberryperl.com/)
* [Python](https://www.python.org/downloads/windows/)
* [7-Zip](https://www.7-zip.org/download.html)
* [Win Flex/Bison](https://sourceforge.net/projects/winflexbison/)
* [Rust compiler MSVC](https://www.rust-lang.org)
* [NSIS](https://nsis.sourceforge.io/)
* [NSIS LockedList Plugin](https://nsis.sourceforge.io/LockedList_plug-in)

## Windows setup

### Manual installation on Windows

Download and install manually:
- [Git](https://git-scm.com/downloads)
    - Default settings can be used
- [Visual Studio 2022/2026 Community](https://visualstudio.microsoft.com/vs/)
    - Select `Desktop development with C++`

### Clone repositories and download tools/dependencies

Open a `PowerShell 7` shell and type:

```powershell
mkdir C:\data\projects\strawberry
cd C:\data\projects\strawberry
git clone https://github.com/strawberrymusicplayer/strawberry.git
git clone https://github.com/strawberrymusicplayer/strawberry-msvc.git
cd strawberry-msvc
```

### Installation

Install manually from `C:\data\projects\strawberry\msvc_\downloads`:
- **Required**:
    - Install `7z<VERSION>-x64.exe`
    - Install `cmake-<VERSION>-windows-x86_64.msi`
    - Install `python-<VERSION>-amd64.exe`
        - In first dialog:
            - Check: `Add python.exe to PATH`
            - Click `Install Now` (to use defaults)
        - In dialog `Setup was successful`:
            - Click: `Disable path length limit`
    - Install `strawberry-perl-<VERSION>-64bit.msi`
    - Extract `win_flex_bison-<VERSION>.zip` to `C:\win_flex_bison`
    - Install `rustup-init.exe`
        - Type in a Command Prompt: `cargo install cargo-c`
- **Recommended: When building dependencies from source**:
    - Install `nasm-<VERSION>-installer-x64.exe`
        - Run as `Administrator` and install into `C:\Program Files\NASM`.
- **Recommended: When creating NSIS Windows installer**:
    - Install NSIS: `nsis-<NSIS_VERSION>-setup.exe`
    - Extract NSIS `LockedList.zip` plugin:
        - Copy `LockedList\Plugins\LockedList64.dll` to `C:\Program Files (x86)\NSIS\Plugins\LockedList64.dll`
        - Copy `LockedList\Plugins\x86-unicode\LockedList.dll` to `C:\Program Files (x86)\NSIS\Plugins\x86-unicode\LockedList.dll`

### Configure PATH environment variable

Windows Settings | System | About | Advanced system settings | Tab Advanced | Environment Variables:
- System variables | Path | Edit:
    - Add: `C:\Program Files\Git\bin` (This is for Unix commands such `sed` and `patch`)
    - Add: `C:\Program Files (x86)\NSIS`
    - Make sure no GCC / MinGW-W64 installation is in `PATH` (gcc, g++, etc commands), as that can cause those to be picked up as compiler instead of MSVC.

### Meson installation

Building with Meson 1.6.0 installation results in build issues
[meson: error: unrecognized arguments:](https://github.com/strawberrymusicplayer/strawberry-msvc/issues/6).

A temporary solution is to remove Meson via Windows Settings | `Apps or remove programs`.
Then install Meson via Python PIP system wide. Start | `PowerShell 7` and type:

```
pip install meson
```

### Optional: Prebuilt binary dependencies

Prebuilt MSVC binaries can be optionally used to speed-up the build process. When this step is skipped, all libraries and dependencies are build from source.

To use prebuilds, download the following `tar.xz` files from Github [strawberry-msvc-dependencies/releases](https://github.com/strawberrymusicplayer/strawberry-msvc-dependencies/releases):
- For debug, extract `strawberry-msvc-x86_64-debug.tar.xz` to `C:\strawberry_msvc_x86_64_debug`
- For release, extract `strawberry-msvc-x86_64-release.tar.xz` to `C:\strawberry_msvc_x86_64_release`

## Build Strawberry from source including dependencies

- Set one debug or release in `PATH` environment variable:
    - For debug: `C:\strawberry_msvc_x86_64_debug\bin`, or:
    - For release: `C:\strawberry_msvc_x86_64_release\bin`

- Start | `PowerShell 7`

```powershell
cd C:\data\projects\strawberry\strawberry-msvc

rem For debug build:
.\StrawberryMSVCBuild.ps1 -build_type debug -arch x86_64 -build_strawberry $true

rem For release build:
.\StrawberryMSVCBuild.ps1 -build_type release -arch x86_64 -build_strawberry $true
```

Strawberry and Windows installer executables are generated in:
- For debug: `C:\data\projects\strawberry\msvc_\build_debug\strawberry\build\`
- For release: `C:\data\projects\strawberry\msvc_\build_release\strawberry\build\`

Two Windows installers are created in the `StrawberrySetup` directory of the build path, one with NSIS and one with the [Qt Installer Framework](https://doc.qt.io/qtinstallerframework/) (`StrawberrySetup-*-qtifw.exe`).

## Build the Qt Installer Framework

The Qt Installer Framework is built automatically by `StrawberryMSVCBuild.ps1` when building Strawberry. It can also be built separately:

```powershell
cd C:\data\projects\strawberry\strawberry-msvc-build-tools
.\StrawberryQtIFWBuild.ps1 -arch x86_64
```

This builds a static Qt (qtbase, qtdeclarative, qttools and qt5compat) with the static MSVC runtime, and the Qt Installer Framework with it, independent of the debug or release build type.
The tools (`binarycreator.exe`, `installerbase.exe`, `repogen.exe`, `archivegen.exe` and `devtool.exe`) are installed to `C:\strawberry_qtifw_x86_64\bin`.
The versions are set with `QT_VERSION` and `QT_IFW_VERSION` in `StrawberryPackageVersions.txt`.

## Setting up Strawberry for development in Visual Studio 2022 or 2026

Optional `Qt Visual Studio Tools` can be installed via the toolbar `Extensions | Manage Extensions` and search for `Qt Visual Studio Tools`. Then click `Install`.

Debug build:
- Make sure the path `C:\strawberry_msvc_x86_64_debug\bin` is added to the `PATH` environment variable before starting Visual Studio 2022 or 2026.
- Start | Visual Studio 2022 or 2026
- Open a local folder `C:\data\projects\strawberry\strawberry`
- Toolbar Project | CMake Settings:
    - Select Configurations `x64-Debug`
    - Add `CMake command arguments`: `-DARCH=x86_64 -DICU_ROOT=c:\\strawberry_msvc_x86_64_debug -DBUILD_WERROR=ON -DENABLE_WIN32_CONSOLE=ON -DENABLE_AUDIOCD=OFF -DENABLE_MTP=OFF -DENABLE_GPOD=OFF`
- Select in the toolbar `x64-Debug`
- Toolbar: Build | Build All

Release build:
- Make sure the path `C:\strawberry_msvc_x86_64_release\bin` is added to the `PATH` environment variable before starting Visual Studio 2022 or 2026.
- Start | Visual Studio 2022 or 2026
- Open a local folder `C:\data\projects\strawberry\strawberry`
- Toolbar Project | CMake Settings:
    - Create new `x64-Release`
    - Select Configurations `x64-Release`
    - Add `CMake command arguments`: `-DARCH=x86_64 -DICU_ROOT=c:\\strawberry_msvc_x86_64_release -DBUILD_WERROR=ON -DENABLE_WIN32_CONSOLE=OFF -DENABLE_AUDIOCD=OFF -DENABLE_MTP=OFF -DENABLE_GPOD=OFF`
    - Save the changes
    - In the toolbar select `x64-Release`
    - Project | Delete Cache and Reconfigure
- Toolbar: Build | Build All

Set breakpoint and press F5 to start debugging and use F10 to step into and F11 to step over.
