# Strawberry Music Player
# Copyright 2026, Jonas Kvinge <jonas@jkvinge.net>
#
# Strawberry is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Strawberry is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Strawberry.  If not, see <http://www.gnu.org/licenses/>.
#

<#
.SYNOPSIS
  Build script for the Qt Installer Framework
.DESCRIPTION
  Builds a static Qt and the Qt Installer Framework (binarycreator, installerbase, repogen, archivegen, devtool) with MSVC, used to create the Qt StrawberrySetup installer.
  The Qt Installer Framework is always built as release with a static Qt and static MSVC runtime, so the tools and the installers created with them do not depend on any DLLs.
.PARAMETER arch
  Architecture: x64, x86_64, amd64, or arm64
.PARAMETER downloads_path
  Path to downloads directory (default: c:/data/projects/strawberry/msvc_/downloads)
.PARAMETER build_path
  Path to build directory (default: c:/data/projects/strawberry/msvc_/build_<arch>_qtifw)
.PARAMETER install_path
  Path the Qt Installer Framework tools are installed to (default: c:/strawberry_qtifw_<arch>)
.EXAMPLE
  ./StrawberryQtIFWBuild.ps1 -arch x86_64
.EXAMPLE
  ./StrawberryQtIFWBuild.ps1 -arch arm64 -build_path "c:/b" -install_path "c:/strawberry_qtifw_arm64"
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [ValidateSet("x64", "x86_64", "amd64", "arm64")]
  [string]$arch,

  [Parameter(Mandatory=$false)]
  [string]$downloads_path = "c:/data/projects/strawberry/msvc_/downloads",

  [Parameter(Mandatory=$false)]
  [string]$build_path = "",

  [Parameter(Mandatory=$false)]
  [string]$install_path = ""
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Green
Write-Host "Qt Installer Framework Build Script" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

# Load versions

$script_path = Split-Path -Parent $MyInvocation.MyCommand.Path
$version_file = Join-Path $script_path "StrawberryPackageVersions.txt"
$patch_path = Join-Path $script_path "patches"

if (-not (Test-Path $version_file)) {
  Write-Error "Package versions file not found: $version_file"
  exit 1
}

$versions = @{}
Get-Content $version_file | ForEach-Object {
  $line = $_.Trim()
  if ($line -and -not $line.StartsWith('#') -and $line -match '^([^=]+)=(.*)$') {
    $versions[$matches[1].Trim()] = $matches[2].Trim()
  }
}

$qt_version = $versions["QT_VERSION"]
$qt_ifw_version = $versions["QT_IFW_VERSION"]
$bzip2_version = $versions["BZIP2_VERSION"]
$xz_version = $versions["XZ_VERSION"]
foreach ($i in @("QT_VERSION", "QT_IFW_VERSION", "BZIP2_VERSION", "XZ_VERSION")) {
  if (-not $versions[$i]) {
    Write-Error "Missing $i in $version_file"
    exit 1
  }
}

$qt_version_full = [version]$qt_version
$qt_version_short = "$($qt_version_full.Major).$($qt_version_full.Minor)"

# Set arch

$arch = $arch.ToLower()
if ($arch -eq "x64" -or $arch -eq "x86_64" -or $arch -eq "amd64") {
  $arch = "x86_64"
  $vs_arch = "amd64"
  $vscmd_arch = "x64"
}
else {
  $vs_arch = "arm64"
  $vscmd_arch = "arm64"
}

switch ((Get-CimInstance Win32_Processor).Architecture) {
  0 { $vs_host_arch = "x86" }
  5 { $vs_host_arch = "arm64" }
  9 { $vs_host_arch = "amd64" }
  12 { $vs_host_arch = "arm64" }
  default {
    Write-Error "Unsupported host architecture"
    exit 1
  }
}

# Set paths

if ([string]::IsNullOrEmpty($build_path)) {
  $build_path = "c:/data/projects/strawberry/msvc_/build_${arch}_qtifw"
}
if ([string]::IsNullOrEmpty($install_path)) {
  $install_path = "c:/strawberry_qtifw_${arch}"
}

# Static Qt and the compression libraries the Qt Installer Framework links to are only needed while building, they are installed into the build directory.
$static_path = "$build_path/static"

Write-Host "Build Configuration:" -ForegroundColor Cyan
Write-Host "  Downloads path:      $downloads_path"
Write-Host "  Build path:          $build_path"
Write-Host "  Static prefix path:  $static_path"
Write-Host "  Install path:        $install_path"
Write-Host "  Build Architecture:  $arch"
Write-Host "  Qt version:          $qt_version"
Write-Host "  Qt IFW version:      $qt_ifw_version"
Write-Host ""

foreach ($i in @($downloads_path, $build_path, $static_path, "$install_path/bin")) {
  if (-not (Test-Path $i)) {
    New-Item -ItemType Directory -Path $i -Force | Out-Null
  }
}

# Setup environment
# Make sure nothing from the shared Strawberry MSVC dependencies is picked up by the static Qt build.

$env:PATH = ($env:PATH -split ';' | Where-Object { $_ -and $_ -notmatch 'strawberry_msvc_' }) -join ';'
Remove-Item Env:PKG_CONFIG_PATH -ErrorAction SilentlyContinue
Remove-Item Env:PKG_CONFIG_EXECUTABLE -ErrorAction SilentlyContinue
Remove-Item Env:CMAKE_PREFIX_PATH -ErrorAction SilentlyContinue
$env:CL = "/MP"

if ($env:VSCMD_ARG_TGT_ARCH -eq $vscmd_arch) {
  Write-Host "Using already initialized Visual Studio $arch environment" -ForegroundColor Cyan
}
else {
  $vs_where_path = "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
  if (-not (Test-Path $vs_where_path)) {
    Write-Error "Could not locate VS where $vs_where_path"
    exit 1
  }
  $vs_install_path = & "${vs_where_path}" -latest -property installationPath 2>$null
  if (-not $vs_install_path -or -not (Test-Path $vs_install_path)) {
    Write-Error "Could not locate VS installation path"
    exit 1
  }
  $vs_dev_shell_path = Join-Path $vs_install_path "Common7/Tools/Launch-VsDevShell.ps1"
  if (-not (Test-Path $vs_dev_shell_path)) {
    Write-Error "Could not locate VS dev shell $vs_dev_shell_path"
    exit 1
  }
  Write-Host "Initializing Visual Studio $arch environment..." -ForegroundColor Cyan
  & $vs_dev_shell_path -Arch $vs_arch -HostArch $vs_host_arch -SkipAutomaticLocation
}

# GNU tar and patch from Git for Windows, appended to PATH so they don't shadow MSVC tools such as link.exe.
# bsdtar (libarchive) gets stuck when extracting tar.xz archives

$git_usr_bin_path = "C:/Program Files/Git/usr/bin"
if (Test-Path $git_usr_bin_path) {
  $env:PATH = "$env:PATH;$git_usr_bin_path"
}

$tar_cmd_path = Get-Command tar -All -ErrorAction SilentlyContinue | Where-Object CommandType -eq Application | Select-Object -ExpandProperty Source -Unique | Where-Object { (& $_ --version 2>&1 | Out-String) -match '^(?m)tar \(GNU tar\)' } | Select-Object -First 1
if (-not $tar_cmd_path) {
  Write-Error "GNU tar not found on PATH."
  exit 1
}

foreach ($i in @("cmake", "ninja", "nmake", "cl", "patch")) {
  if (-not (Get-Command $i -ErrorAction SilentlyContinue)) {
    Write-Error "Missing $i"
    exit 1
  }
}

function DownloadFileIfNotExists {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true)]
    [string]$url
  )
  $file_path = Join-Path $downloads_path (Split-Path $url -Leaf)
  if (Test-Path $file_path) {
    Write-Host "Using cached $file_path" -ForegroundColor Cyan
    return $file_path
  }
  Write-Host "Downloading $url" -ForegroundColor Yellow
  try {
    Invoke-WebRequest -Uri $url -OutFile $file_path -UseBasicParsing -MaximumRedirection 5 -UserAgent "Wget"
    if ((Get-Item $file_path).Length -eq 0) {
      throw "Downloaded file is empty (0 bytes)"
    }
  }
  catch {
    if (Test-Path $file_path) {
      Remove-Item $file_path -Force
    }
    throw "Failed to download $url : $_"
  }
  return $file_path
}

# Extracts the archive into $package_dir, stripping the top-level directory, since some archives do not use the expected top-level directory name.
function ExtractPackage {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true)]
    [string]$url,

    [Parameter(Mandatory=$true)]
    [string]$package_dir
  )
  $file_path = DownloadFileIfNotExists -url $url
  if (Test-Path $package_dir) {
    return
  }
  Write-Host "Extracting $file_path" -ForegroundColor Cyan
  New-Item -ItemType Directory -Path $package_dir -Force | Out-Null
  & $tar_cmd_path -xf $file_path -C $package_dir --strip-components=1 --force-local
  if ($LASTEXITCODE -ne 0) {
    Remove-Item $package_dir -Recurse -Force
    throw "Failed to extract $file_path"
  }
}

function StaticCMakeBuild {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true)]
    [string]$package_dir,

    [Parameter(Mandatory=$false)]
    [string[]]$additional_args = @()
  )
  Write-Host "Building $package_dir with CMake" -ForegroundColor Cyan
  $configure_args = @(
    "-G", "Ninja",
    "-S", "$package_dir",
    "-B", "$package_dir/build",
    "-DCMAKE_BUILD_TYPE=Release",
    "-DCMAKE_PREFIX_PATH=$static_path",
    "-DCMAKE_INSTALL_PREFIX=$static_path",
    "-DBUILD_SHARED_LIBS=OFF",
    "-DCMAKE_POLICY_DEFAULT_CMP0091=NEW",
    "-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded"
  ) + $additional_args
  Write-Host "cmake" @configure_args
  & cmake @configure_args
  if ($LASTEXITCODE -ne 0) {
    throw "CMake configuration of $package_dir failed"
  }
  & cmake --build "$package_dir/build"
  if ($LASTEXITCODE -ne 0) {
    throw "CMake build of $package_dir failed"
  }
  & cmake --install "$package_dir/build"
  if ($LASTEXITCODE -ne 0) {
    throw "CMake install of $package_dir failed"
  }
}

function Build-BZip2 {
  Write-Host "Building bzip2" -ForegroundColor Yellow
  ExtractPackage -url "https://sourceware.org/pub/bzip2/bzip2-$bzip2_version.tar.gz" -package_dir "bzip2"
  & patch -d "bzip2" -p1 -N -i "$patch_path/bzip2-cmake.patch" 2>&1 | Out-Null
  StaticCMakeBuild -package_dir "bzip2" -additional_args @("-DCMAKE_POLICY_VERSION_MINIMUM=3.5", "-DBZIP2_SKIP_TOOLS=ON")
}

function Build-XZ {
  Write-Host "Building xz" -ForegroundColor Yellow
  ExtractPackage -url "https://downloads.sourceforge.net/project/lzmautils/xz-$xz_version.tar.gz" -package_dir "xz"
  StaticCMakeBuild -package_dir "xz" -additional_args @("-DBUILD_TESTING=OFF", "-DXZ_NLS=OFF", "-DXZ_TOOL_XZ=OFF", "-DXZ_TOOL_XZDEC=OFF", "-DXZ_TOOL_LZMADEC=OFF", "-DXZ_TOOL_LZMAINFO=OFF")
}

function Build-QtModule {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true)]
    [string]$module,

    [Parameter(Mandatory=$false)]
    [string[]]$additional_args = @()
  )
  Write-Host "Building static $module" -ForegroundColor Yellow
  ExtractPackage -url "https://download.qt.io/official_releases/qt/$qt_version_short/$qt_version/submodules/$module-everywhere-src-$qt_version.tar.xz" -package_dir $module
  StaticCMakeBuild -package_dir $module -additional_args (@(
    "-DQT_BUILD_EXAMPLES=OFF",
    "-DQT_BUILD_EXAMPLES_BY_DEFAULT=OFF",
    "-DQT_BUILD_TESTS=OFF",
    "-DQT_GENERATE_SBOM=OFF"
  ) + $additional_args)
}

# Configuration as recommended by the Qt Installer Framework documentation, using the libraries bundled with Qt.
function Build-QtBase {
  Build-QtModule -module "qtbase" -additional_args @(
    "-DFEATURE_static_runtime=ON",
    "-DFEATURE_accessibility=ON",
    "-DFEATURE_icu=OFF",
    "-DFEATURE_openssl=OFF",
    "-DFEATURE_dbus=OFF",
    "-DFEATURE_glib=OFF",
    "-DFEATURE_pkg_config=OFF",
    "-DFEATURE_zstd=OFF",
    "-DFEATURE_brotli=OFF",
    "-DFEATURE_libproxy=OFF",
    "-DFEATURE_sql_sqlite=OFF",
    "-DFEATURE_sql_odbc=OFF",
    "-DFEATURE_system_zlib=OFF",
    "-DFEATURE_system_png=OFF",
    "-DFEATURE_system_jpeg=OFF",
    "-DFEATURE_system_pcre2=OFF",
    "-DFEATURE_system_freetype=OFF",
    "-DFEATURE_system_harfbuzz=OFF",
    "-DFEATURE_system_doubleconversion=OFF"
  )
}

function Build-QtDeclarative {
  Build-QtModule -module "qtdeclarative" -additional_args @("-DFEATURE_qml_debug=OFF")
}

function Build-QtTools {
  Build-QtModule -module "qttools" -additional_args @(
    "-DFEATURE_assistant=OFF",
    "-DFEATURE_designer=OFF",
    "-DFEATURE_distancefieldgenerator=OFF",
    "-DFEATURE_kmap2qmap=OFF",
    "-DFEATURE_pixeltool=OFF",
    "-DFEATURE_qdbus=OFF",
    "-DFEATURE_qev=OFF",
    "-DFEATURE_qtattributionsscanner=OFF",
    "-DFEATURE_qtdiag=OFF",
    "-DFEATURE_qtplugininfo=OFF",
    "-DFEATURE_clang=OFF",
    "-DFEATURE_linguist=ON"
  )
}

function Build-Qt5Compat {
  Build-QtModule -module "qt5compat"
}

function Build-QtIFW {
  Write-Host "Building Qt Installer Framework" -ForegroundColor Yellow
  ExtractPackage -url "https://download.qt.io/official_releases/qt-installer-framework/$qt_ifw_version/installer-framework-everywhere-src-$qt_ifw_version.tar.xz" -package_dir "installer-framework"
  New-Item -ItemType Directory -Path "installer-framework/build" -Force | Out-Null
  Push-Location "installer-framework/build"
  try {
    # Use the zlib bundled with Qt, the Qt Installer Framework only detects it from the Qt 5 zlib module name.
    & "$static_path/bin/qmake.exe" ../installerfw.pro `
      "IFW_ZLIB_LIBRARY=$static_path/lib/Qt6BundledZLIB.lib" `
      "IFW_BZIP2_LIBRARY=$static_path/lib/bz2.lib" `
      "IFW_LZMA_LIBRARY=$static_path/lib/lzma.lib" `
      "INCLUDEPATH+=$static_path/include $static_path/include/QtZlib"
    if ($LASTEXITCODE -ne 0) {
      throw "qmake failed"
    }
    & nmake
    if ($LASTEXITCODE -ne 0) {
      throw "nmake failed"
    }
    Copy-Item "bin/*.exe" "$install_path/bin/" -Force
  }
  finally {
    Pop-Location
  }
}

Write-Host "Starting build process..." -ForegroundColor Cyan
Write-Host ""

Push-Location $build_path
try {
  $build_queue = @()
  if (-not (Test-Path "$static_path/lib/bz2.lib")) { $build_queue += "bzip2" }
  if (-not (Test-Path "$static_path/lib/lzma.lib")) { $build_queue += "xz" }
  if (-not (Test-Path "$static_path/bin/qmake.exe")) { $build_queue += "qtbase" }
  if (-not (Test-Path "$static_path/lib/Qt6Qml.lib")) { $build_queue += "qtdeclarative" }
  if (-not (Test-Path "$static_path/lib/Qt6UiTools.lib")) { $build_queue += "qttools" }
  if (-not (Test-Path "$static_path/lib/Qt6Core5Compat.lib")) { $build_queue += "qt5compat" }
  if (-not (Test-Path "$install_path/bin/binarycreator.exe")) { $build_queue += "installer-framework" }

  if ($build_queue.Count -eq 0) {
    Write-Host "Qt Installer Framework already built!" -ForegroundColor Green
    exit 0
  }

  Write-Host "Build queue: $($build_queue -join ', ')" -ForegroundColor Cyan
  Write-Host ""

  foreach ($component in $build_queue) {
    Write-Host "========================================" -ForegroundColor Magenta
    Write-Host "Building: $component" -ForegroundColor Magenta
    Write-Host "========================================" -ForegroundColor Magenta
    switch ($component) {
      "bzip2" { Build-BZip2 }
      "xz" { Build-XZ }
      "qtbase" { Build-QtBase }
      "qtdeclarative" { Build-QtDeclarative }
      "qttools" { Build-QtTools }
      "qt5compat" { Build-Qt5Compat }
      "installer-framework" { Build-QtIFW }
    }
    Write-Host "Completed: $component" -ForegroundColor Green
    Write-Host ""
  }

  Write-Host "========================================" -ForegroundColor Green
  Write-Host "Qt Installer Framework built successfully!" -ForegroundColor Green
  Write-Host "========================================" -ForegroundColor Green
}
catch {
  Write-Host ""
  Write-Host "========================================" -ForegroundColor Red
  Write-Host "Build failed!" -ForegroundColor Red
  Write-Host "Error: $_" -ForegroundColor Red
  Write-Host "========================================" -ForegroundColor Red
  exit 1
}
finally {
  Pop-Location
}
