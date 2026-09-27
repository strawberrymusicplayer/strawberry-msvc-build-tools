# Strawberry Music Player
# Copyright 2025-2026, Jonas Kvinge <jonas@jkvinge.net>
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
  Build script for Strawberry MSVC dependencies
.DESCRIPTION
  Builds all dependencies required for Strawberry Music Player on Windows using MSVC
.PARAMETER build_type
  Build type: debug or release (default: debug)
.PARAMETER arch
  Architecture: x86, x64, x86_64, amd64, or arm64
.PARAMETER downloads_path
  Path to downloads directory (default: c:/data/projects/strawberry/msvc_/downloads)
.PARAMETER build_path
  Path to build directory (default: c:/data/projects/strawberry/msvc_/build_<arch>_<build_type>, where <arch> and <build_type> are substituted with the actual parameter values)
.EXAMPLE
  ./StrawberryMSVCBuild.ps1 -build_type release -arch x86_64
.EXAMPLE
  ./StrawberryMSVCBuild.ps1 -build_type debug -arch x86_64 -downloads_path "D:/strawberry/downloads" -build_path "D:/strawberry/build"
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [ValidateSet("debug", "release", "Debug", "Release")]
  [string]$build_type,

  [Parameter(Mandatory=$true)]
  [ValidateSet("x86", "x64", "x86_64", "amd64", "arm64")]
  [string]$arch,

  [Parameter(Mandatory=$false)]
  [string]$downloads_path = "c:/data/projects/strawberry/msvc_/downloads",

  [Parameter(Mandatory=$false)]
  [string]$build_path = ""
)

function AppendPathToEnvPath() {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true)]
    [string]$path
  )
  $path_normalized = $path.TrimEnd('\').ToLowerInvariant()
  $paths = $env:PATH -split ';' | ForEach-Object { $_.TrimEnd('\') }
  if ($paths -notcontains $path_normalized) {
    $env:PATH += ";$path"
  }
}

function PrependPathToEnvPath() {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true)]
    [string]$path
  )
  $path_normalized = $path.TrimEnd('\').ToLowerInvariant()
  $paths = $env:PATH -split ';' | ForEach-Object { $_.TrimEnd('\') }
  if ($paths -notcontains $path_normalized) {
    $env:PATH = "$path;$env:PATH"
  }
}

function RemovePathFromEnvPath() {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true)]
    [string]$path
  )
  $path_normalized = $path.TrimEnd('\').ToLowerInvariant()
  $env:PATH = ($env:PATH -split ';' | Where-Object { $_.TrimEnd('\').ToLowerInvariant() -ne $path_normalized }) -join ';'
}

# Set strict mode
$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Green
Write-Host "Strawberry MSVC Dependencies Build Script" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

# Load versions

$script_path = Split-Path -Parent $MyInvocation.MyCommand.Path
$version_file = Join-Path $script_path "StrawberryPackageVersions.txt"
$patch_path = Join-Path $script_path "patches"

if (Test-Path $version_file) {
  Get-Content $version_file | ForEach-Object {
    $line = $_.Trim()
    # Skip empty lines and comments
    if ($line -and -not $line.StartsWith('#')) {
      if ($line -match '^([^=]+)=(.*)$') {
        $name = $matches[1].Trim()
        $value = $matches[2].Trim()
        # Only set variable if value is not empty
        if ($value) {
          # Convert variable name to lowercase
          $name_lower = $name.ToLower()
          # Set as global variable with lowercase name
          Set-Variable -Name $name_lower -Value $value -Scope Global
        }
      }
    }
  }
}
else {
  Write-Error "Package versions file not found: $version_file"
  exit 1
}

$boost_version_underscore = $boost_version.Replace(".", "_")
$expat_version_underscore = $expat_version.Replace(".", "_")
$libxml2_version_full = [version]$libxml2_version
$libxml2_version_short = "$($libxml2_version_full.Major).$($libxml2_version_full.Minor)"
$qt_version_full = [version]$qt_version
$qt_version_short = "$($qt_version_full.Major).$($qt_version_full.Minor)"

# Set build configuration - normalize input to lowercase for internal use
$build_type = $build_type.ToLower()

# Set build system specific configurations
$cmake_build_type = if ($build_type -eq "debug") { "Debug" } else { "Release" }
$meson_build_type = $build_type  # meson uses lowercase
$lib_postfix = if ($build_type -eq "debug") { "d" } else { "" }

# Set arch

$arch_numeric_id = (Get-CimInstance Win32_Processor).Architecture
switch ($arch_numeric_id) {
  0 { $vs_host_arch = "x86" }
  5 { $vs_host_arch = "arm64" }
  9 { $vs_host_arch = "amd64" }
  default {
    Write-Error "Unsupported host architecture: $arch_numeric_id"
    exit 1
  }
}

$vs_host_arch = $vs_host_arch.ToLower()
$arch = $arch.ToLower()

if ($arch -eq "x64" -or $arch -eq "x86_64" -or $arch -eq "amd64") {
  $arch="x86_64"
  $vs_arch="amd64"
  $openssl_platform="VC-WIN64A"
  $msbuild_platform="x64"
  $arch_short="x64"
  $arch_win="win64"
  $arch_bits="64"
  $libdir="lib64"
  $bindir="bin64"
  $lib_machine="x64"
  $vs_platform="x64"
  $libjpeg_turbo_simd="ON"
  $boost_architecture="x86"
  $lame_msvcver="X64"
}
elseif ($arch -eq "arm64") {
  $arch="arm64"
  $vs_arch="arm64"
  $openssl_platform="VC-WIN64-ARM"
  $msbuild_platform="arm64"
  $arch_short="arm64"
  $arch_win="win64"
  $arch_bits="64"
  $libdir="libARM64"
  $bindir="binARM64"
  $lib_machine="ARM64"
  $vs_platform="ARM64"
  $libjpeg_turbo_simd="OFF"
  $boost_architecture="arm"
  $lame_msvcver="ARM64"
}
else {
  Write-Error "Unknown arch: $arch"
  exit 1
}

# Set paths
# Use default build path if not specified
if ([string]::IsNullOrEmpty($build_path)) {
  $build_path = "c:/data/projects/strawberry/msvc_/build_${arch}_${build_type}"
}

$prefix_path = "c:/strawberry_msvc_${arch}_${build_type}"
$qt_dev = "OFF"
$gst_dev = "OFF"

$cmake_loglevel = "DEBUG"
$cmake_generator = "Ninja"

# Display configuration
Write-Host "Build Configuration:" -ForegroundColor Cyan
Write-Host "  Downloads path:      $downloads_path"
Write-Host "  Build path:          $build_path"
Write-Host "  Build type:          $build_type"
Write-Host "  Build Architecture:  $arch"
Write-Host "  CMake build type:    $cmake_build_type"
Write-Host "  Meson build type:    $meson_build_type"
Write-Host "  Prefix path:         $prefix_path"
Write-Host ""

# Create directories
Write-Host "Creating directories..." -ForegroundColor Cyan
try {
  @($downloads_path, $build_path, $prefix_path, "$prefix_path/include", "$prefix_path/lib", "$prefix_path/lib/pkgconfig", "$prefix_path/lib/cmake", "$prefix_path/bin") | ForEach-Object {
    if (-not (Test-Path $_)) {
      New-Item -ItemType Directory -Path $_ -Force | Out-Null
      Write-Host "  Created: $_" -ForegroundColor Green
    }
  }
}
catch {
  Write-Error "Failed to create directories: $_"
  exit 1
}

# Copy sed.exe if needed
if (-not (Test-Path "$prefix_path/bin/sed.exe")) {
  if (Test-Path "$downloads_path/sed.exe") {
    Copy-Item "$downloads_path/sed.exe" "$prefix_path/bin/" -Force
  }
}

# Setup environment variables
Write-Host "Setting up environment variables..." -ForegroundColor Cyan
$env:PKG_CONFIG_EXECUTABLE = "$prefix_path/bin/pkgconf.exe"
$env:PKG_CONFIG_PATH = "$prefix_path/lib/pkgconfig"
$env:PKG_CONFIG_ALLOW_SYSTEM_CFLAGS = "1"
$env:PKG_CONFIG_ALLOW_SYSTEM_LIBS = "1"
$env:CL = "-MP"
$env:YASMPATH = "$prefix_path/bin"

PrependPathToEnvPath -path "$prefix_path/bin"

# Remove Strawberry Perl bin path
RemovePathFromEnvPath -path 'C:\Strawberry\c\bin'

Write-Host "  Setting Visual Studio environment..." -ForegroundColor Cyan
$vs_where_path = "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
if (-not (Test-Path $vs_where_path)) {
  Write-Error "Could not locate VS where $vs_where_path"
  exit 1
}

$vs_install_path = & "${vs_where_path}" -latest -property installationPath 2>$null
if (-not $vs_install_path) {
  Write-Error "Could not locate VS installation path"
  exit 1
}

if (-not (Test-Path $vs_install_path)) {
  Write-Error "VS installation path $vs_install_path does not exist"
  exit 1
}

$vs_dev_shell_path = Join-Path $vs_install_path "Common7/Tools/Launch-VsDevShell.ps1"
if (-not (Test-Path $vs_dev_shell_path)) {
  Write-Error "Could not locate VS dev shell $vs_dev_shell_path"
  exit 1
}

$vs_dev_env_path = Join-Path $vs_install_path "Common7/IDE/devenv.com"
if (-not (Test-Path $vs_dev_env_path)) {
  Write-Error "Could not locate VS dev shell $vs_dev_env_path"
  exit 1
}

Write-Host "  Initializing Visual Studio $arch environment..." -ForegroundColor Cyan
& $vs_dev_shell_path -Arch $vs_arch -HostArch $vs_host_arch -SkipAutomaticLocation
Write-Host "  Visual Studio $arch environment initialized" -ForegroundColor Green

function Test-Command {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true)]
    [string]$command
  )

  $null = Get-Command $command -ErrorAction SilentlyContinue
  return $?
}

function Assert-Command {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true)]
    [string]$command,

    [Parameter(Mandatory=$false)]
    [string]$path,

    [Parameter(Mandatory=$true)]
    [string]$error_message
  )

  if (-not (Test-Command $command)) {
    if ($path -and (Test-Path $path)) {
      $env:PATH = "$path;$env:PATH"
    }

    if (-not (Test-Command $command)) {
      throw $error_message
    }
  }
}

# Check for required tools
Write-Host "Checking requirements..." -ForegroundColor Cyan

$cmd_checks = @(
  @{ Command = "sed"; Paths = @("C:/Program Files/Git/usr/bin"); Message = "Missing sed" }
  @{ Command = "patch"; Paths = @("C:/Program Files/Git/usr/bin"); Message = "Missing patch" }
  @{ Command = "nasm"; Paths = @("C:/Program Files/nasm"); Message = "Missing nasm. Download from https://www.nasm.us/" }
  @{ Command = "win_flex"; Paths = @("C:/win_flex_bison"); Message = "Missing win_flex. Download from https://sourceforge.net/projects/winflexbison/" }
  @{ Command = "win_bison"; Paths = @("C:/win_flex_bison"); Message = "Missing win_bison. Download from https://sourceforge.net/projects/winflexbison/" }
  @{ Command = "perl"; Paths = @("C:/Strawberry/perl/bin"); Message = "Missing perl. Download Strawberry Perl from https://strawberryperl.com/" }
  @{ Command = "python"; Paths = @("C:/Program Files/Python314", "C:/Program Files/Python313", "C:/Program Files/Python312", "C:/Program Files/Python311", "C:/Program Files/Python310"); Message = "Missing python. Download from https://www.python.org/" }
  @{ Command = "bzip2"; Paths = @("C:/Program Files/Git/usr/bin"); Message = "Missing bzip2" }
  @{ Command = "7z"; Paths = @("C:/Program Files/7-Zip"); Message = "Missing 7z. Download 7-Zip from https://www.7-zip.org/download.html" }
  @{ Command = "cmake"; Paths = @("C:/Program Files/CMake/bin"); Message = "Missing cmake. Download from https://cmake.org/" }
  @{ Command = "meson"; Paths = @("C:/Program Files/Meson"); Message = "Missing meson. Download from https://mesonbuild.com/" }
  @{ Command = "nmake"; Paths = @(); Message = "Missing nmake. Install Visual Studio 2022 or 2026" }
)

foreach ($cmd_check in $cmd_checks) {
  if (-not (Test-Command $cmd_check.Command)) {
    foreach ($path in $cmd_check.Paths) {
      if (Test-Path $path) {
        $cmd_path = "$path/${cmd_check.Command}"
        if (Test-Path $cmd_path) {
          $env:PATH = "$env:PATH;$path"
          break
        }
      }
    }
    if (-not (Test-Command $cmd_check.Command)) {
      Write-Error $cmd_check.Message
      exit 1
    }
  }
  Write-Host "  $($cmd_check.Command) found" -ForegroundColor Green
}

# Check for GNU tar
# bsdtar (libarchive) gets stuck when extracting tar.xz archives

$tar_candidates = Get-Command tar -All -ErrorAction SilentlyContinue | Where-Object CommandType -eq Application | Select-Object -ExpandProperty Source -Unique
$tar_results = foreach ($i in $tar_candidates) {
  $out = & $i --version 2>&1 | Out-String
  [pscustomobject]@{
    Path       = $i
    IsGnuTar   = ($out -match '^(?m)tar \(GNU tar\)')
    IsBsdTar   = ($out -match '(?im)\bbsdtar\b')
    VersionRaw = ($out -replace '\r','').Trim()
  }
}
$tar_cmd_path = ($tar_results | Where-Object IsGnuTar | Select-Object -First 1 -ExpandProperty Path)
if (-not $tar_cmd_path) {
  Write-Host "No GNU tar found. Candidates and their banners:"
  $tar_results | ForEach-Object { "{0}`n  {1}`n" -f $_.Path, ($_.VersionRaw -split "`n" | Select-Object -First 1) }
  throw "GNU tar not found on PATH."
}

Write-Host ""
Write-Host "All requirements satisfied!" -ForegroundColor Green
Write-Host ""
Write-Host "Using GNU tar from $tar_cmd_path"
Write-Host ""

function RecursiveCopy {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true)]
    [string]$source_path,

    [Parameter(Mandatory=$true)]
    [string]$destination_path
  )
  $source_path_backslash = $source_path -replace '/', '\'
  $destination_path_backslash = $destination_path -replace '/', '\'
  xcopy /E /V /I /F /H /R /Y /B $source_path_backslash $destination_path_backslash
}

function DownloadFileIfNotExists {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true)]
    [string]$url,

    [Parameter(Mandatory=$true)]
    [string]$destination_path
  )
  # Handle SourceForge URLs that end with /download
  $filename = Split-Path $url -Leaf
  if ($filename -eq 'download' -and $url -match '/([^/]+)/download$') {
    $filename = $matches[1]
  }
  $file_path = Join-Path $destination_path $filename
  if (-not (Test-Path $file_path)) {
    Write-Host "Downloading $url" -ForegroundColor Yellow
    try {
      Invoke-WebRequest -Uri $url -OutFile $file_path -UseBasicParsing -MaximumRedirection 5 -UserAgent "Wget"
      # Verify file was downloaded and has content
      if (-not (Test-Path $file_path)) {
        throw "Downloaded file not found at $file_path"
      }
      $file_size = (Get-Item $file_path).Length
      if ($file_size -eq 0) {
        Remove-Item $file_path -Force
        throw "Downloaded file is empty (0 bytes)"
      }
      Write-Host "Downloaded $filename ($file_size bytes)" -ForegroundColor Green
    }
    catch {
      if (Test-Path $file_path) {
        Remove-Item $file_path -Force
      }
      Write-Error "Failed to download $url : $_"
      throw
    }
  }
  else {
    Write-Host "Using cached $filename" -ForegroundColor Cyan
  }
}

function SyncGitRepository {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true)]
    [string]$url,

    [Parameter(Mandatory=$true)]
    [string]$destination_path
  )

  $repo_name = Split-Path $url -Leaf
  $repo_path = Join-Path $destination_path $repo_name

  if (Test-Path $repo_path) {
    Write-Host "Updating repository $url" -ForegroundColor Yellow
    Push-Location $repo_path
    try {
      & git pull --rebase
      if ($LASTEXITCODE -ne 0) {
        Write-Warning "Failed to update repository $url"
      }
    }
    finally {
      Pop-Location
    }
  }
  else {
    Write-Host "Cloning repository $url" -ForegroundColor Yellow
    & git clone --recurse-submodules $url $repo_path
    if ($LASTEXITCODE -ne 0) {
      throw "Failed to clone repository $url"
    }
  }
}

function GetPackageUrls {
  [CmdletBinding()]
  param()
  $package_urls = @{
    'pkgconf' = "https://github.com/pkgconf/pkgconf/archive/refs/tags/pkgconf-$pkgconf_version.tar.gz"
    'proxy-libintl' = "https://github.com/frida/proxy-libintl/archive/refs/tags/$proxy_libintl_version/proxy-libintl-$proxy_libintl_version.tar.gz"
    'getopt-win' = "https://github.com/ludvikjerabek/getopt-win/archive/refs/tags/v$getopt_win_version/getopt-win-$getopt_win_version.tar.gz"
    'zlib' = "https://zlib.net/zlib-$zlib_version.tar.gz"
    'openssl' = "https://github.com/openssl/openssl/releases/download/openssl-$openssl_version/openssl-$openssl_version.tar.gz"
    'libpng' = "https://downloads.sourceforge.net/project/libpng/libpng16/$libpng_version/libpng-$libpng_version.tar.gz"
    'libjpeg-turbo' = "https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/$libjpeg_turbo_version/libjpeg-turbo-$libjpeg_turbo_version.tar.gz"
    'pcre2' = "https://github.com/PCRE2Project/pcre2/releases/download/pcre2-$pcre2_version/pcre2-$pcre2_version.tar.gz"
    'bzip2' = "https://sourceware.org/pub/bzip2/bzip2-$bzip2_version.tar.gz"
    'xz' = "https://downloads.sourceforge.net/project/lzmautils/xz-$xz_version.tar.gz"
    'brotli' = "https://github.com/google/brotli/archive/refs/tags/v$brotli_version/brotli-$brotli_version.tar.gz"
    'icu4c' = "https://github.com/unicode-org/icu/releases/download/release-$icu4c_version/icu4c-$icu4c_version-sources.tgz"
    'pixman' = "https://www.cairographics.org/releases/pixman-$pixman_version.tar.gz"
    'expat' = "https://github.com/libexpat/libexpat/releases/download/R_$expat_version_underscore/expat-$expat_version.tar.gz"
    'boost' = "https://archives.boost.io/release/$boost_version/source/boost_$boost_version_underscore.tar.gz"
    'libxml2' = "https://download.gnome.org/sources/libxml2/$libxml2_version_short/libxml2-$libxml2_version.tar.xz"
    'nghttp2' = "https://github.com/nghttp2/nghttp2/releases/download/v$nghttp2_version/nghttp2-$nghttp2_version.tar.gz"
    'dlfcn-win32' = "https://github.com/dlfcn-win32/dlfcn-win32/archive/refs/tags/v$dlfcn_version/dlfcn-win32-$dlfcn_version.tar.gz"
    'libpsl' = "https://github.com/rockdaboot/libpsl/releases/download/$libpsl_version/libpsl-$libpsl_version.tar.gz"
    'orc' = "https://gstreamer.freedesktop.org/src/orc/orc-$orc_version.tar.xz"
    'sqlite' = "https://sqlite.org/2026/sqlite-autoconf-$sqlite_version.tar.gz"
    'libproxy' = "https://github.com/libproxy/libproxy/archive/refs/tags/$libproxy_version/libproxy-$libproxy_version.tar.gz"
    'glib' = "https://download.gnome.org/sources/glib/2.90/glib-$glib_version.tar.xz"
    'libsoup' = "https://download.gnome.org/sources/libsoup/3.6/libsoup-$libsoup_version.tar.xz"
    'glib-networking' = "https://download.gnome.org/sources/glib-networking/2.80/glib-networking-$glib_networking_version.tar.xz"
    'freetype' = "https://sourceforge.net/projects/freetype/files/freetype2/$freetype_version/freetype-$freetype_version.tar.gz"
    'cairo' = "https://cairographics.org/releases/cairo-$cairo_version.tar.xz"
    'harfbuzz' = "https://github.com/harfbuzz/harfbuzz/releases/download/$harfbuzz_version/harfbuzz-$harfbuzz_version.tar.xz"
    'jasper' = "https://github.com/jasper-software/jasper/releases/download/version-$jasper_version/jasper-$jasper_version.tar.gz"
    'tiff' = "https://download.osgeo.org/libtiff/tiff-$tiff_version.tar.gz"
    'libwebp' = "https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-$libwebp_version.tar.gz"
    'libogg' = "https://downloads.xiph.org/releases/ogg/libogg-$libogg_version.tar.gz"
    'libvorbis' = "https://downloads.xiph.org/releases/vorbis/libvorbis-$libvorbis_version.tar.gz"
    'flac' = "https://ftp.osuosl.org/pub/xiph/releases/flac/flac-$flac_version.tar.xz"
    'wavpack' = "https://www.wavpack.com/wavpack-$wavpack_version.tar.bz2"
    'opus' = "https://downloads.xiph.org/releases/opus/opus-$opus_version.tar.gz"
    'opusfile' = "https://ftp.osuosl.org/pub/xiph/releases/opus/opusfile-$opusfile_version.tar.gz"
    'speex' = "https://gitlab.xiph.org/xiph/speex/-/archive/Speex-$speex_version/speex-Speex-$speex_version.tar.gz"
    'mpg123' = "https://downloads.sourceforge.net/project/mpg123/mpg123/$mpg123_version/mpg123-$mpg123_version.tar.bz2"
    'lame' = "https://downloads.sourceforge.net/project/lame/lame/$lame_version/lame-$lame_version.tar.gz"
    'fftw' = "https://github.com/strawberrymusicplayer/fftw3-mingw-cross/releases/download/${fftw_version}/fftw-${arch}-w64-mingw32-${build_type}-${fftw_version}.tar.xz"
    'musepack' = "https://files.musepack.net/source/musepack_src_r$musepack_version.tar.gz"
    'libopenmpt' = "https://lib.openmpt.org/files/libopenmpt/src/libopenmpt-$libopenmpt_version+release.msvc.zip"
    'libgme' = "https://github.com/libgme/game-music-emu/releases/download/$libgme_version/libgme-$libgme_version-src.tar.gz"
    'fdk-aac' = "https://downloads.sourceforge.net/project/opencore-amr/fdk-aac/fdk-aac-$fdk_aac_version.tar.gz"
    'faad2' = "https://github.com/knik0/faad2/tarball/$faad2_version/faad2-$faad2_version.tar.gz"
    'faac' = "https://github.com/knik0/faac/archive/refs/tags/faac-$faac_version.tar.gz"
    'utfcpp' = "https://github.com/nemtrif/utfcpp/archive/refs/tags/v$utfcpp_version/utfcpp-$utfcpp_version.tar.gz"
    'taglib' = "https://taglib.org/releases/taglib-$taglib_version.tar.gz"
    'libbs2b' = "https://downloads.sourceforge.net/project/bs2b/libbs2b/$libbs2b_version/libbs2b-$libbs2b_version.tar.bz2"
    'libebur128' = "https://github.com/jiixyj/libebur128/archive/refs/tags/v$libebur128_version/libebur128-$libebur128_version.tar.gz"
    'chromaprint' = "https://github.com/acoustid/chromaprint/releases/download/v$chromaprint_version/chromaprint-$chromaprint_version.tar.gz"
    'gstreamer' = "https://gstreamer.freedesktop.org/src/gstreamer/gstreamer-$gstreamer_version.tar.xz"
    'gst-plugins-base' = "https://gstreamer.freedesktop.org/src/gst-plugins-base/gst-plugins-base-$gstreamer_version.tar.xz"
    'gst-plugins-good' = "https://gstreamer.freedesktop.org/src/gst-plugins-good/gst-plugins-good-$gstreamer_version.tar.xz"
    'gst-plugins-bad' = "https://gstreamer.freedesktop.org/src/gst-plugins-bad/gst-plugins-bad-$gstreamer_version.tar.xz"
    'gst-plugins-ugly' = "https://gstreamer.freedesktop.org/src/gst-plugins-ugly/gst-plugins-ugly-$gstreamer_version.tar.xz"
    'gst-libav' = "https://gstreamer.freedesktop.org/src/gst-libav/gst-libav-$gstreamer_version.tar.xz"
    'sparsehash' = "https://github.com/sparsehash/sparsehash/archive/refs/tags/sparsehash-$sparsehash_version.tar.gz"
    'abseil-cpp' = "https://github.com/abseil/abseil-cpp/archive/refs/tags/$abseil_version/abseil-cpp-$abseil_version.tar.gz"
    'protobuf' = "https://github.com/protocolbuffers/protobuf/releases/download/v$protobuf_version/protobuf-$protobuf_version.tar.gz"
    'qtbase' = "https://download.qt.io/official_releases/qt/$qt_version_short/$qt_version/submodules/qtbase-everywhere-src-$qt_version.tar.xz"
    'qttools' = "https://download.qt.io/official_releases/qt/$qt_version_short/$qt_version/submodules/qttools-everywhere-src-$qt_version.tar.xz"
    'qtimageformats' = "https://download.qt.io/official_releases/qt/$qt_version_short/$qt_version/submodules/qtimageformats-everywhere-src-$qt_version.tar.xz"
    'qtgrpc' = "https://download.qt.io/official_releases/qt/$qt_version_short/$qt_version/submodules/qtgrpc-everywhere-src-$qt_version.tar.xz"
    'kdsingleapplication' = "https://github.com/KDAB/KDSingleApplication/releases/download/v$kdsingleapplication_version/kdsingleapplication-$kdsingleapplication_version.tar.gz"
    'glew' = "https://downloads.sourceforge.net/project/glew/glew/$glew_version/glew-$glew_version.tgz"
    'libprojectm' = "https://github.com/projectM-visualizer/projectm/releases/download/v$libprojectm_version/libprojectm-$libprojectm_version.tar.gz"
    'pe-parse' = "https://github.com/trailofbits/pe-parse/archive/refs/tags/v$peparse_version/pe-parse-$peparse_version.tar.gz"
    'vc-redist-x86' = "https://aka.ms/vc14/vc_redist.x86.exe"
    'vc-redist-x64' = "https://aka.ms/vc14/vc_redist.x64.exe"
    "vc-redist-arm64" = "https://aka.ms/vc14/vc_redist.arm64.exe"
  }
  return $package_urls
}

function GetGitRepoUrls {
  $git_repo_urls = @{
    'glib-networking' = "https://gitlab.gnome.org/GNOME/glib-networking"
    'qtbase' = "https://code.qt.io/qt/qtbase"
    'qttools' = "https://code.qt.io/qt/qttools"
    'qtsparkle' = "https://github.com/strawberrymusicplayer/qtsparkle"
    'libffi' = "https://gitlab.freedesktop.org/gstreamer/meson-ports/libffi"
    'ffmpeg' = "https://gitlab.freedesktop.org/gstreamer/meson-ports/ffmpeg"
    'gstreamer' = "https://gitlab.freedesktop.org/gstreamer/gstreamer"
    'gst-plugins-rs' = "https://gitlab.freedesktop.org/gstreamer/gst-plugins-rs"
    'tinysvcmdns' = "https://github.com/Pro/tinysvcmdns"
    'yasm' = "https://github.com/yasm/yasm"
    'pe-util' = "https://github.com/gsauthof/pe-util"
    'strawberry' = "https://github.com/strawberrymusicplayer/strawberry"
  }
  return $git_repo_urls
}

function GetPackageUrl {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true)]
    [string]$package_name
  )
  $package_urls = GetPackageUrls
  if (!$package_urls.ContainsKey($package_name)) {
    throw "Package '$package_name' not found in package URLs"
  }
  return $package_urls[$package_name]
}

function GetGitRepoUrl {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true)]
    [string]$git_repo_name
  )
  $git_repo_urls = GetGitRepoUrls
  if (!$git_repo_urls.ContainsKey($git_repo_name)) {
    throw "Git repo '$git_repo_name' not found in git repo URLs"
  }
  return $git_repo_urls[$git_repo_name]
}

function DownloadPackage {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true)]
    [string]$package_name
  )
  Write-Host "Checking package: $package_name" -ForegroundColor Cyan
  try {
    if (-not (Test-Path $downloads_path)) {
      New-Item -ItemType Directory -Path $downloads_path -Force | Out-Null
    }
    $package_urls = GetPackageUrls
    if (!$package_urls.ContainsKey($package_name)) {
      throw "Package '$package_name' not found in dependency configuration"
    }
    $package_url = $package_urls[$package_name]
    DownloadFileIfNotExists -url $package_url -destination_path $downloads_path
    Write-Host "✓ Package $package_name is available" -ForegroundColor Green
  }
  catch {
    Write-Warning "Failed to download package $package_name : $_"
    throw
  }
}

function CloneGitRepo {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true)]
    [string]$git_repo_name
  )
  Write-Host "Checking git repository: $git_repo_name" -ForegroundColor Cyan
  if (-not (Test-Path $downloads_path)) {
    New-Item -ItemType Directory -Path $downloads_path -Force | Out-Null
  }
  try {
    $git_repo_urls = GetGitRepoUrls
    if (!$git_repo_urls.ContainsKey($git_repo_name)) {
      throw "git repository '$git_repo_name' not found in dependency configuration"
    }
    $git_repo_url = $git_repo_urls[$git_repo_name]
    SyncGitRepository -url $git_repo_url -destination_path $downloads_path
    Write-Host "✓ Repository $git_repo_name is available" -ForegroundColor Green
  }
  catch {
    Write-Warning "Failed to clone git repository $git_repo_name : $_"
    throw
  }
}

function ExtractPackage {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true)]
    [string]$package_file,

    [Parameter(Mandatory=$false)]
    [string]$package_dir,

    [Parameter(Mandatory=$false)]
    [bool]$ignore_errors = $false
  )
  if (-not $package_dir) {
    $package_dir = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetFileNameWithoutExtension($package_file))
    if (-not $package_dir) {
      throw "Could not get filename from path $package_file"
    }
  }
  if (Test-Path $package_dir) {
    return
  }
  Write-Host "Extracting $package_file" -ForegroundColor Cyan
  $extension = [System.IO.Path]::GetExtension($package_file)
  if ($extension -eq ".gz" -or $extension -eq ".tgz" -or $extension -eq ".bz2" -or $extension -eq ".xz") {
    & $tar_cmd_path -xf "$downloads_path/$package_file" --force-local
    if ($LASTEXITCODE -ne 0) {
      if (-not $ignore_errors) {
        throw "Failed to extract $package_file"
      }
    }
  }
  else {
    throw "Unknown extension for package $package_file"
  }
}

function CMakeBuild {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$false)]
    [string]$source_path = ".",

    [Parameter(Mandatory=$false)]
    [string]$build_path = "build",

    [Parameter(Mandatory=$false)]
    [string]$cmake_build_type_override = "$cmake_build_type",

    [Parameter(Mandatory=$false)]
    [bool]$build_static_libs = $false,

    [Parameter(Mandatory=$false)]
    [bool]$build_shared_libs = $true,

    [Parameter(Mandatory=$false)]
    [string[]]$additional_args = @()
  )
  $package_name = (Get-Item -Path $PWD).Name
  Write-Host "Building $package_name with CMake" -ForegroundColor Cyan
  if (-not (Test-Path $build_path)) {
    New-Item -ItemType Directory -Path $build_path -Force | Out-Null
  }
  $build_static_libs_toggle = if ($build_static_libs) { "ON" } else { "OFF" }
  $build_shared_libs_toggle = if ($build_shared_libs) { "ON" } else { "OFF" }
  $configure_args = @(
    "--log-level=$cmake_loglevel",
    "-G", "$cmake_generator",
    "-S", "$source_path",
    "-B", "$build_path",
    "-DCMAKE_BUILD_TYPE=$cmake_build_type_override",
    "-DCMAKE_PREFIX_PATH=$prefix_path/lib/cmake",
    "-DCMAKE_INSTALL_PREFIX=$prefix_path",
    "-DBUILD_STATIC_LIBS=$build_static_libs_toggle",
    "-DBUILD_SHARED_LIBS=$build_shared_libs_toggle",
    "-DPKG_CONFIG_EXECUTABLE=$prefix_path/bin/pkgconf.exe"
  )
  if ($additional_args) {
    $configure_args += $additional_args
  }
  Write-Host "cmake" @configure_args
  RemovePathFromEnvPath -path 'C:\Strawberry\perl\bin'
  RemovePathFromEnvPath -path 'C:\Strawberry\perl\site\bin'
  & cmake @configure_args
  if ($LASTEXITCODE -ne 0) {
    throw "CMake configuration failed"
  }
  Push-Location $build_path
  try {
    & cmake --build .
    if ($LASTEXITCODE -ne 0) {
      throw "CMake build failed"
    }
    & cmake --install .
    if ($LASTEXITCODE -ne 0) {
      throw "CMake install failed"
    }
  }
  finally {
    Pop-Location
  }
}

function MesonBuild {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$false)]
    [string]$source_path = ".",

    [Parameter(Mandatory=$false)]
    [string]$build_path = "build",

    [Parameter(Mandatory=$false)]
    [string]$default_library = "shared",

    [Parameter(Mandatory=$false)]
    [string]$pkg_config_path = "$prefix_path/lib/pkgconfig",

    [Parameter(Mandatory=$false)]
    [string]$wrap_mode = "nodownload",

    [Parameter(Mandatory=$false)]
    [string[]]$additional_args = @()
  )
  $package_name = (Get-Item -Path $PWD).Name
  Write-Host "Building $package_name with Meson" -ForegroundColor Cyan
  Push-Location $source_path
  try {
    if (-not (Test-Path "$build_path/build.ninja")) {
      $setup_args = @(
        "--buildtype=$build_type",
        "--default-library=$default_library",
        "--pkg-config-path=$pkg_config_path",
        "--includedir=$prefix_path/include",
        "--libdir=$prefix_path/lib",
        "--prefix=$prefix_path",
        "--wrap-mode=$wrap_mode",
        "-Dc_args=-I$prefix_path/include",
        "-Dcpp_args=-I$prefix_path/include",
        "-Dc_link_args=-L$prefix_path/lib",
        "-Dcpp_link_args=-L$prefix_path/lib"
      )
      if ($additional_args) {
        $setup_args += $additional_args
      }
      $setup_args += $build_path
      Write-Host "meson setup" @setup_args
      RemovePathFromEnvPath -path 'C:\Strawberry\perl\bin'
      RemovePathFromEnvPath -path 'C:\Strawberry\perl\site\bin'
      & meson setup @setup_args
      if ($LASTEXITCODE -ne 0) {
        throw "Meson setup failed"
      }
    }
    Push-Location $build_path
    try {
      & ninja
      if ($LASTEXITCODE -ne 0) {
        throw "Ninja build failed"
      }
      & ninja install
      if ($LASTEXITCODE -ne 0) {
        throw "Ninja install failed"
      }
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function UpgradeVSProject {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true)]
    [string]$project_path
  )
  Write-Host "Upgrading Visual Studio project: $project_path" -ForegroundColor Cyan
  if (-not $vs_dev_env_path) {
    throw "Could not locate devenv.com"
  }
  Start-Process -FilePath "$vs_dev_env_path" -ArgumentList "$project_path /upgrade" -Wait -NoNewWindow
}

function MSBuildProject {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true)]
    [string]$project_path,

    [Parameter(Mandatory=$false)]
    [string]$configuration = "${build_type}DLL",

    [Parameter(Mandatory=$false)]
    [string]$platform = "$msbuild_platform",

    [Parameter(Mandatory=$false)]
    [string[]]$additional_args = @()
  )
  Write-Host "Building $project_path with MSBuild" -ForegroundColor Cyan
  $build_args = @(
    $project_path,
    "-p:Configuration=$configuration",
    "-p:Platform=$platform",
    "-p:UseEnv=true"
  )
  if ($additional_args) {
    $build_args += $additional_args
  }
  & msbuild @build_args
  if ($LASTEXITCODE -ne 0) {
    throw "MSBuild failed"
  }
}

function CreatePkgConfigFile {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true)]
    [string]$name,

    [Parameter(Mandatory=$true)]
    [string]$description,

    [Parameter(Mandatory=$false)]
    [string]$url,

    [Parameter(Mandatory=$true)]
    [string]$version,

    [Parameter(Mandatory=$true)]
    [string]$prefix,

    [Parameter(Mandatory=$false)]
    [string]$libs = "",

    [Parameter(Mandatory=$false)]
    [string]$libs_private = "",

    [Parameter(Mandatory=$false)]
    [string]$cflags = "",

    [Parameter(Mandatory=$false)]
    [string]$requires = "",

    [Parameter(Mandatory=$true)]
    [string]$output_file
  )

  $pc_dir = Split-Path -Path $output_file -Parent
  if (-not (Test-Path $pc_dir)) {
    New-Item -ItemType Directory -Path $pc_dir -Force | Out-Null
  }

  $content = @"
prefix=$prefix
exec_prefix=`${prefix}
libdir=`${exec_prefix}/lib
includedir=`${prefix}/include

Name: $name
Description: $description

"@

  if ($url) {
    $content += "Url: ${url}`n"
  }

  $content += "Version: ${version}`n"

  if ($requires) {
    $content += "Requires: ${requires}`n"
  }

  if ($libs) {
    $content += "Libs: ${libs}`n"
  }

  if ($libs_private) {
    $content += "Libs.private: ${libs_private}`n"
  }

  if ($cflags) {
    $content += "Cflags: ${cflags}`n"
  }

  Set-Content -Path $output_file -Value $content -Encoding ASCII
}

function CreateLibFile() {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true)]
    [string]$name
  )

  $def = "${name}.def"
  $dll = "${name}.dll"

  # Create/overwrite the .def header
  @(
    "LIBRARY $dll"
    "EXPORTS"
  ) | Set-Content -Encoding ASCII $def

  # Append exported symbol names from dumpbin output
  dumpbin /exports $dll |
    Select-Object -Skip 19 |
    ForEach-Object {
      # Split on whitespace; token 4 in cmd for/f == index 3 here
      $parts = ($_ -split '\s+')
      if ($parts.Length -ge 4) { $parts[3] }
    } |
    Where-Object { $_ } |
    Add-Content -Encoding ASCII $def

  # Build the import library from the .def
  & lib /machine:$lib_machine /def:$def

}


#region Build Functions

function Build-PkgConf {
  Write-Host "Building pkgconf" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "pkgconf"
    ExtractPackage "pkgconf-$pkgconf_version.tar.gz"
    Push-Location "pkgconf-pkgconf-$pkgconf_version"
    try {
      MesonBuild
      Copy-Item "$prefix_path/bin/pkgconf.exe" "$prefix_path/bin/pkg-config.exe" -Force
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-Yasm {
  Write-Host "Building yasm" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    CloneGitRepo -git_repo_name "yasm"
    if (-not (Test-Path "yasm")) {
      RecursiveCopy "$downloads_path/yasm" "$build_path/yasm"
    }
    Push-Location "yasm"
    try {
      CMakeBuild
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-ProxyIntl {
  Write-Host "Building proxy-libintl" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "proxy-libintl"
    ExtractPackage "proxy-libintl-$proxy_libintl_version.tar.gz" -ignore_errors $true
    Push-Location "proxy-libintl-$proxy_libintl_version"
    try {
      MesonBuild
      CreatePkgConfigFile -prefix $prefix_path -name "libintl" -description "libintl" -url "https://github.com/frida/proxy-libintl" -version $proxy_libintl_version -libs "-L`${libdir} -lintl" -cflags "-I`${includedir}" -output_file "$prefix_path/lib/pkgconfig/intl.pc"
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-GetOptWin {
  Write-Host "Building getopt-win" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "getopt-win"
    ExtractPackage "getopt-win-$getopt_win_version.tar.gz"
    Push-Location "getopt-win-$getopt_win_version"
    try {
      CMakeBuild -additional_args @(
          "-DBUILD_SHARED_LIB=ON",
          "-DBUILD_STATIC_LIB=OFF",
          "-DBUILD_TESTING=OFF"
        )
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-ZLib {
  Write-Host "Building zlib" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "zlib"
    ExtractPackage "zlib-$zlib_version.tar.gz"
    Push-Location "zlib-$zlib_version"
    try {
      CMakeBuild
      if ($build_type -eq "debug") {
        & sed -i 's/-lz$/-lzd/g' "$prefix_path/lib/pkgconfig/zlib.pc"
        Copy-Item "$prefix_path/lib/zd.lib" "$prefix_path/lib/z.lib" -Force
      }
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-OpenSSL {
  Write-Host "Building OpenSSL" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    PrependPathToEnvPath -path 'C:\Strawberry\perl\bin'
    PrependPathToEnvPath -path 'C:\Strawberry\perl\site\bin'
    DownloadPackage -package_name "openssl"
    ExtractPackage "openssl-$openssl_version.tar.gz"
    Push-Location "openssl-$openssl_version"
    try {
      $is_debug = $build_type -eq "debug"
      $build_flag = if ($is_debug) { "--debug" } else { "--release" }
      & perl Configure $openssl_platform shared zlib no-capieng no-tests --prefix="$prefix_path" --libdir=lib --openssldir="$prefix_path/ssl" $build_flag --with-zlib-include="$prefix_path/include" --with-zlib-lib="$prefix_path/lib/z${lib_postfix}.lib"
      if ($LASTEXITCODE -ne 0) { throw "OpenSSL configure failed" }
      & nmake
      if ($LASTEXITCODE -ne 0) { throw "OpenSSL build failed" }
      & nmake install_sw
      if ($LASTEXITCODE -ne 0) { throw "OpenSSL install failed" }
      Copy-Item "$prefix_path/lib/libssl.lib" "$prefix_path/lib/ssl.lib" -Force
      Copy-Item "$prefix_path/lib/libcrypto.lib" "$prefix_path/lib/crypto.lib" -Force
      Copy-Item "exporters/*.pc" "$prefix_path/lib/pkgconfig" -Force
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-LibPNG {
  Write-Host "Building libpng" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "libpng"
    ExtractPackage "libpng-$libpng_version.tar.gz"
    Push-Location "libpng-$libpng_version"
    try {
      & patch -p1 -N -i "$patch_path/libpng-pkgconf.patch" 2>&1 | Out-Null
      CMakeBuild
      Remove-Item "$prefix_path/lib/libpng16_static${lib_postfix}.lib" -Force -ErrorAction SilentlyContinue
      if ($build_type -eq "debug") {
        Copy-Item "$prefix_path/lib/libpng16d.lib" "$prefix_path/lib/png16.lib" -Force
      }
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-LibJPEGTurbo {
  Write-Host "Building libjpeg-turbo" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "libjpeg-turbo"
    ExtractPackage "libjpeg-turbo-$libjpeg_turbo_version.tar.gz"
    Push-Location "libjpeg-turbo-$libjpeg_turbo_version"
    try {
      CMakeBuild -additional_args @(
          "-DENABLE_SHARED=ON",
          "-DENABLE_STATIC=OFF",
          "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
        )
      Remove-Item "$prefix_path/lib/jpeg-static.lib" -Force -ErrorAction SilentlyContinue
      Remove-Item "$prefix_path/lib/turbojpeg-static.lib" -Force -ErrorAction SilentlyContinue
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-PCRE2 {
  Write-Host "Building pcre2" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "pcre2"
    ExtractPackage "pcre2-$pcre2_version.tar.gz"
    Push-Location "pcre2-$pcre2_version"
    try {
      CMakeBuild -additional_args @(
          "-DPCRE2_BUILD_PCRE2_16=ON",
          "-DPCRE2_BUILD_PCRE2_32=ON",
          "-DPCRE2_BUILD_PCRE2_8=ON",
          "-DPCRE2_BUILD_TESTS=OFF",
          "-DPCRE2_SUPPORT_UNICODE=ON"
        )
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-BZip2 {
  Write-Host "Building bzip2" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "bzip2"
    ExtractPackage "bzip2-$bzip2_version.tar.gz"
    Push-Location "bzip2-$bzip2_version"
    try {
      & patch -p1 -N -i "$patch_path/bzip2-cmake.patch" 2>&1 | Out-Null
      CMakeBuild -build_path "build2" -additional_args @("-DCMAKE_POLICY_VERSION_MINIMUM=3.5")
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-XZ {
  Write-Host "Building xz" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "xz"
    ExtractPackage "xz-$xz_version.tar.gz"
    Push-Location "xz-$xz_version"
    try {
      CMakeBuild -additional_args @(
          "-DBUILD_TESTING=OFF",
          "-DXZ_NLS=OFF"
        )
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-Brotli {
  Write-Host "Building brotli" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "brotli"
    ExtractPackage "brotli-$brotli_version.tar.gz"
    Push-Location "brotli-$brotli_version"
    try {
      CMakeBuild -build_path "build2" -additional_args @("-DBUILD_TESTING=OFF")
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-ICU4C {
  Write-Host "Building icu4c" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "icu4c"
    ExtractPackage "icu4c-$icu4c_version-sources.tgz" "icu"
    Push-Location "icu/source/allinone"
    try {
      MSBuildProject -project_path "allinone.sln" -configuration "$build_type" -additional_args @("-p:SkipUWP=true")
    }
    finally {
      Pop-Location
    }
    Push-Location "icu"
    try {
      if (-not (Test-Path "include")) {
        throw "Missing icu4c include dir"
      }
      Copy-Item "include/unicode" "$prefix_path/include/" -Recurse -Force
      Copy-Item "$libdir/*.*" "$prefix_path/lib/" -Force
      Copy-Item "$bindir/*.*" "$prefix_path/bin/" -Force
      CreatePkgConfigFile -prefix $prefix_path -name "icu-uc" -description "International Components for Unicode: Common and Data libraries" -version $icu4c_version -libs "-L`${libdir} -licuuc$lib_postfix -licudt" -libs_private "-lpthread -lm" -output_file "$prefix_path/lib/pkgconfig/icu-uc.pc"
      CreatePkgConfigFile -prefix $prefix_path -name "icu-i18n" -description "International Components for Unicode: Stream and I/O Library" -version $icu4c_version -libs "-licuin$lib_postfix" -requires "icu-uc" -output_file "$prefix_path/lib/pkgconfig/icu-i18n.pc"
      CreatePkgConfigFile -prefix $prefix_path -name "icu-io" -description "International Components for Unicode: Stream and I/O Library" -version $icu4c_version -libs "-licuio$lib_postfix" -requires "icu-i18n" -output_file "$prefix_path/lib/pkgconfig/icu-io.pc"
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-Pixman {
  Write-Host "Building pixman" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "pixman"
    ExtractPackage "pixman-$pixman_version.tar.gz" -ignore_errors $true
    Push-Location "pixman-$pixman_version"
    try {
      MesonBuild -additional_args @("-Dgtk=disabled", "-Dlibpng=enabled")
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-Expat {
  Write-Host "Building expat" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "expat"
    ExtractPackage "expat-$expat_version.tar.gz"
    Push-Location "expat-$expat_version"
    try {
      CMakeBuild -additional_args @(
          "-DEXPAT_BUILD_DOCS=OFF",
          "-DEXPAT_BUILD_EXAMPLES=OFF",
          "-DEXPAT_BUILD_FUZZERS=OFF",
          "-DEXPAT_BUILD_TESTS=OFF",
          "-DEXPAT_BUILD_TOOLS=OFF",
          "-DEXPAT_BUILD_PKGCONFIG=ON"
        )
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-Boost {
  Write-Host "Building boost" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "boost"
    ExtractPackage "boost_$boost_version_underscore.tar.gz"
    Push-Location "boost_$boost_version_underscore"
    try {
      if (Test-Path "b2.exe") { Remove-Item "b2.exe" -Force }
      if (Test-Path "bjam.exe") { Remove-Item "bjam.exe" -Force }
      if (Test-Path "stage") { Remove-Item "stage" -Recurse -Force }
      Write-Host "Running bootstrap.bat" -ForegroundColor Cyan
      & ./bootstrap.bat msvc
      if ($LASTEXITCODE -ne 0) { throw "Boost bootstrap failed" }
      Write-Host "Running b2.exe" -ForegroundColor Cyan
      & ./b2.exe -a -q -j 4 -d1 --ignore-site-config --stagedir="stage" --layout="tagged" --prefix="$prefix_path" --exec-prefix="$prefix_path/bin" --libdir="$prefix_path/lib" --includedir="$prefix_path/include" --with-headers toolset=msvc architecture=$boost_architecture address-model=$arch_bits link=shared runtime-link=shared threadapi=win32 threading=multi variant=$build_type install
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-LibXML2 {
  Write-Host "Building libxml2" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "libxml2"
    ExtractPackage "libxml2-$libxml2_version.tar.xz"
    Push-Location "libxml2-$libxml2_version"
    try {
      CMakeBuild -additional_args @(
          "-DLIBXML2_WITH_PYTHON=OFF",
          "-DLIBXML2_WITH_ZLIB=ON",
          "-DLIBXML2_WITH_LZMA=ON",
          "-DLIBXML2_WITH_ICONV=OFF",
          "-DLIBXML2_WITH_ICU=ON",
          "-DLIBXML2_WITH_REGEXPS=ON",
          "-DLIBXML2_WITH_HTML=ON",
          "-DICU_ROOT=$prefix_path"
        )
      if ($build_type -eq "debug") {
        Copy-Item "$prefix_path/lib/libxml2d.lib" "$prefix_path/lib/libxml2.lib" -Force
      }
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-NgHttp2 {
  Write-Host "Building nghttp2" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "nghttp2"
    ExtractPackage "nghttp2-$nghttp2_version.tar.gz"
    Push-Location "nghttp2-$nghttp2_version"
    try {
      CMakeBuild
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-LibFFI {
  Write-Host "Building libffi" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    CloneGitRepo "libffi"
    if (-not (Test-Path "libffi")) {
      RecursiveCopy "$downloads_path/libffi" "libffi"
    }
    Push-Location "libffi"
    try {
      MesonBuild
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-DlfcnWin32 {
  Write-Host "Building dlfcn-win32" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "dlfcn-win32"
    ExtractPackage "dlfcn-win32-$dlfcn_version.tar.gz"
    Push-Location "dlfcn-win32-$dlfcn_version"
    try {
      CMakeBuild
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-LibPSL {
  Write-Host "Building libpsl" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "libpsl"
    ExtractPackage "libpsl-$libpsl_version.tar.gz"
    Push-Location "libpsl-$libpsl_version"
    try {
      MesonBuild `
        -additional_args @(
          "-Druntime=libicu"
        )
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-Orc {
  Write-Host "Building orc" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "orc"
    ExtractPackage "orc-$orc_version.tar.xz"
    Push-Location "orc-$orc_version"
    try {
      MesonBuild
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-SQLite {
  Write-Host "Building sqlite" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "sqlite"
    ExtractPackage "sqlite-autoconf-$sqlite_version.tar.gz"
    Push-Location "sqlite-autoconf-$sqlite_version"
    try {
      & cl -DSQLITE_API="__declspec(dllexport)" -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_COLUMN_METADATA sqlite3.c -link -dll -out:sqlite3.dll
      if ($LASTEXITCODE -ne 0) { throw "SQLite DLL build failed" }
      & cl shell.c sqlite3.c -Fe:sqlite3.exe
      if ($LASTEXITCODE -ne 0) { throw "SQLite shell build failed" }
      Copy-Item "*.h" "$prefix_path/include/" -Force
      Copy-Item "*.lib" "$prefix_path/lib/" -Force
      Copy-Item "*.dll" "$prefix_path/bin/" -Force
      Copy-Item "*.exe" "$prefix_path/bin/" -Force
      CreatePkgConfigFile -prefix $prefix_path -name "SQLite" -description "SQL database engine" -url "https://www.sqlite.org/" -version $sqlite_version -libs "-L`${libdir} -lsqlite3" -cflags "-I`${includedir}" -output_file "$prefix_path/lib/pkgconfig/sqlite3.pc"
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-Glib {
  Write-Host "Building glib" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "glib"
    ExtractPackage "glib-$glib_version.tar.xz" -ignore_errors $true
    Push-Location "glib-$glib_version"
    try {
      MesonBuild `
        -additional_args @(
          "-Dtests=false"
        )
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-LibSoup {
  Write-Host "Building libsoup" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "libsoup"
    ExtractPackage "libsoup-$libsoup_version.tar.xz"
    Push-Location "libsoup-$libsoup_version"
    try {
      MesonBuild `
        -additional_args @(
          "-Dtests=false",
          "-Dvapi=disabled",
          "-Dgssapi=disabled",
          "-Dintrospection=disabled",
          "-Dsysprof=disabled",
          "-Dtls_check=false"
        )
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-GlibNetworking {
  Write-Host "Building glib-networking" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    #DownloadPackage -package_name "glib-networking"
    #ExtractPackage "glib-networking-$glib_networking_version.tar.xz"
    #Set-Location "glib-networking-$glib_networking_version"
    CloneGitRepo -git_repo_name "glib-networking"
    RecursiveCopy "$downloads_path/glib-networking" "glib-networking"
    Push-Location "glib-networking"
    try {
      & patch -p1 -N -i $patch_path/glib-networking.patch
      MesonBuild `
        -additional_args @(
          "-Dgnutls=disabled",
          "-Dopenssl=enabled",
          "-Dgnome_proxy=disabled",
          "-Dlibproxy=disabled",
          "-Dtests=false"
        )
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-Freetype {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true)]
    [bool]$with_harfbuzz
  )
  $harfbuzz_type = if ($with_harfbuzz) { "with harfbuzz" } else { "without harfbuzz" }
  Write-Host "Building freetype $harfbuzz_type" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "freetype"
    ExtractPackage "freetype-$freetype_version.tar.gz"
    Push-Location "freetype-$freetype_version"
    try {
      $disable_harfbuzz = if ($with_harfbuzz) { "OFF" } else { "ON" }
      CMakeBuild -additional_args @("-DFT_DISABLE_HARFBUZZ=$disable_harfbuzz")
      if ($build_type -eq "debug") {
        Copy-Item "$prefix_path/lib/freetyped.lib" "$prefix_path/lib/freetype.lib" -Force
      }
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-Harfbuzz {
  Write-Host "Building harfbuzz" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "harfbuzz"
    ExtractPackage "harfbuzz-$harfbuzz_version.tar.xz"
    Push-Location "harfbuzz-$harfbuzz_version"
    try {
      MesonBuild `
        -additional_args @(
          "-Dcpp_std=c++17",
          "-Dtests=disabled",
          "-Ddocs=disabled",
          "-Dfreetype=enabled",
          "-Dicu=enabled",
          "-Dcairo=disabled",
          "-Dutilities=disabled"
        )
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
  Build-Freetype -with_harfbuzz $true
}

function Build-Jasper {
  Write-Host "Building jasper" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "jasper"
    ExtractPackage "jasper-$jasper_version.tar.gz" -ignore_errors $true
    & sed -i '/include(InstallRequiredSystemLibraries)/d' "jasper-$jasper_version/CMakeLists.txt"
    CMakeBuild -source_path "jasper-$jasper_version" -build_path "jasper-$jasper_version-build" -additional_args @(
      "-DJAS_ENABLE_JP2_CODEC=ON",
      "-DJAS_ENABLE_JPC_CODEC=ON",
      "-DJAS_ENABLE_JPG_CODEC=ON",
      "-DJAS_ENABLE_LIBJPEG=ON",
      "-DJAS_ENABLE_OPENGL=ON",
      "-DJAS_INCLUDE_BMP_CODEC=ON",
      "-DJAS_INCLUDE_JP2_CODEC=ON",
      "-DJAS_INCLUDE_JPC_CODEC=ON",
      "-DJAS_INCLUDE_JPG_CODEC=ON"
    )
  }
  finally {
    Pop-Location
  }
}

function Build-Tiff {
  Write-Host "Building tiff" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "tiff"
    ExtractPackage "tiff-$tiff_version.tar.gz"
    Push-Location "tiff-$tiff_version"
    try {
      CMakeBuild -additional_args @(
        "-Djpeg=ON",
        "-Dtiff-static=OFF",
        "-Dtiff-docs=OFF",
        "-Dtiff-tests=OFF"
      )
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-LibWebP {
  Write-Host "Building libwebp" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "libwebp"
    ExtractPackage "libwebp-$libwebp_version.tar.gz"
    Push-Location "libwebp-$libwebp_version"
    try {
      CMakeBuild -additional_args @(
        "-DWEBP_LINK_STATIC=OFF",
        "-DWEBP_UNICODE=ON",
        "-DWEBP_USE_THREAD=ON"
      )
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-Ogg {
  Write-Host "Building libogg" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "libogg"
    ExtractPackage "libogg-$libogg_version.tar.gz"
    Push-Location "libogg-$libogg_version"
    try {
      CMakeBuild -additional_args @(
          "-DINSTALL_DOCS=OFF",
          "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
        )
      Write-Host "libogg built successfully!" -ForegroundColor Green
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-Vorbis {
  Write-Host "Building libvorbis" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "libvorbis"
    ExtractPackage "libvorbis-$libvorbis_version.tar.gz"
    Push-Location "libvorbis-$libvorbis_version"
    try {
      CMakeBuild -additional_args @(
          "-DINSTALL_DOCS=OFF",
          "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
        )
      Write-Host "libvorbis built successfully!" -ForegroundColor Green
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-Flac {
  Write-Host "Building flac" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "flac"
    ExtractPackage "flac-$flac_version.tar.xz"
    Push-Location "flac-$flac_version"
    try {
      CMakeBuild -build_path "build2" -additional_args @(
          "-DBUILD_DOCS=OFF",
          "-DBUILD_EXAMPLES=OFF",
          "-DINSTALL_MANPAGES=OFF",
          "-DBUILD_TESTING=OFF",
          "-DBUILD_PROGRAMS=OFF"
        )
      Write-Host "flac built successfully!" -ForegroundColor Green
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-WavPack {
  Write-Host "Building wavpack" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "wavpack"
    ExtractPackage "wavpack-$wavpack_version.tar.bz2"
    Push-Location "wavpack-$wavpack_version"
    try {
      CMakeBuild -additional_args @(
            "-DBUILD_TESTING=OFF",
            "-DWAVPACK_BUILD_DOCS=OFF",
            "-DWAVPACK_BUILD_PROGRAMS=OFF",
            "-DWAVPACK_ENABLE_ASM=OFF",
            "-DWAVPACK_ENABLE_LEGACY=OFF",
            "-DWAVPACK_BUILD_WINAMP_PLUGIN=OFF",
            "-DWAVPACK_BUILD_COOLEDIT_PLUGIN=OFF"
          )
      Copy-Item "$prefix_path/lib/wavpackdll.lib" "$prefix_path/lib/wavpack.lib" -Force
      Write-Host "wavpack built successfully!" -ForegroundColor Green
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-Opus {
  Write-Host "Building opus" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "opus"
    ExtractPackage "opus-$opus_version.tar.gz"
    Push-Location "opus-$opus_version"
    try {
      # Remove problematic line from CMakeLists.txt
      & sed -i '/include(opus_buildtype.cmake)/d' CMakeLists.txt
      CMakeBuild
      Write-Host "opus built successfully!" -ForegroundColor Green
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-Opusfile {
  Write-Host "Building opusfile" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "opusfile"
    ExtractPackage "opusfile-$opusfile_version.tar.gz"
    Push-Location "opusfile-$opusfile_version"
    try {
      & patch -p1 -N -i $patch_path/opusfile-cmake.patch
      CMakeBuild -additional_args @("-DCMAKE_POLICY_VERSION_MINIMUM=3.5")
      Write-Host "opusfile built successfully!" -ForegroundColor Green
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-Speex {
  Write-Host "Building speex" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "speex"
    ExtractPackage "speex-Speex-$speex_version.tar.gz"
    Push-Location "speex-Speex-$speex_version"
    try {
      & patch -p1 -N -i "$patch_path/speex-cmake.patch"
      CMakeBuild
      if ($build_type -eq "debug") {
        Copy-Item "$prefix_path/lib/libspeexd.lib" "$prefix_path/lib/libspeex.lib" -Force
        Copy-Item "$prefix_path/bin/libspeexd.dll" "$prefix_path/bin/libspeex.dll" -Force
      }
      Write-Host "speex built successfully!" -ForegroundColor Green
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-MPG123 {
  Write-Host "Building mpg123" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "mpg123"
    ExtractPackage "mpg123-$mpg123_version.tar.bz2"
    Push-Location "mpg123-$mpg123_version"
    try {
      CMakeBuild -source_path "ports/cmake" -build_path "build2" -additional_args @(
          "-DBUILD_PROGRAMS=OFF",
          "-DBUILD_LIBOUT123=OFF",
          "-DYASM_ASSEMBLER=$prefix_path/bin/vsyasm.exe"
        )
      Write-Host "mpg123 built successfully!" -ForegroundColor Green
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }

}

function Build-Lame {
  Write-Host "Building lame" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "lame"
    ExtractPackage "lame-$lame_version.tar.gz"
    Push-Location "lame-$lame_version"
    try {
      & patch -p1 -N -i "$patch_path/lame-msvc.patch"
      & nmake -f Makefile.MSVC MSVCVER=${lame_msvcver} libmp3lame.dll
      if ($LASTEXITCODE -ne 0) { throw "nmake build failed" }
      New-Item -Path "$prefix_path/include/lame" -ItemType Directory -Force
      Copy-Item "include/lame.h" "$prefix_path/include/lame/" -Force
      Copy-Item "output/libmp3lame.lib" "$prefix_path/lib/" -Force
      Copy-Item "output/libmp3lame.dll" "$prefix_path/bin/" -Force
      Copy-Item "$prefix_path/lib/libmp3lame.lib" "$prefix_path/lib/mp3lame.lib" -Force
      CreatePkgConfigFile -prefix $prefix_path -name "lame" -description "encoder that converts audio to the MP3 file format." -url "https://lame.sourceforge.io/" -version $lame_version -libs "-L`${libdir} -lmp3lame" -cflags "-I`${includedir}" -output_file "$prefix_path/lib/pkgconfig/lame.pc"
      Copy-Item "$prefix_path/lib/pkgconfig/lame.pc" "$prefix_path/lib/pkgconfig/libmp3lame.pc" -Force
      Write-Host "lame built successfully!" -ForegroundColor Green
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-FFTW3 {
  Write-Host "Building fftw3" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    # It's recommended to build FFTW3 with MinGW-W64 so we use a binary package built on GitHub
    DownloadPackage -package_name "fftw"
    ExtractPackage "fftw-${arch}-w64-mingw32-${build_type}-${fftw_version}.tar.xz"
    Push-Location "fftw-${arch}-w64-mingw32-${build_type}-${fftw_version}/lib"
    try {
      # Generate .lib file from .def
      if ((-not (Test-Path "fftw3.def")) && Test-Path "libfftw3-3.def") {
        Copy-Item "libfftw3-3.def" "fftw3.def" -Force
      }
      & lib /machine:$lib_machine /def:fftw3.def
      if ($LASTEXITCODE -ne 0) { throw "lib.exe failed to create import library" }
    }
    finally {
      Pop-Location
    }
    RecursiveCopy "fftw-${arch}-w64-mingw32-${build_type}-${fftw_version}" "$prefix_path"
    & sed -i "s,^prefix=.*,prefix=${prefix_path},g" "$prefix_path/lib/pkgconfig/fftw3.pc"
    & sed -i "s,^exec_prefix=.*,exec_prefix=${prefix_path},g" "$prefix_path/lib/pkgconfig/fftw3.pc"
    & sed -i "s,^libdir=.*,libdir=${prefix_path}/lib,g" "$prefix_path/lib/pkgconfig/fftw3.pc"
    & sed -i "s,^includedir=.*,includedir=${prefix_path}/include,g" "$prefix_path/lib/pkgconfig/fftw3.pc"
  }
  finally {
    Pop-Location
  }
}

function Build-Musepack {
  Write-Host "Building musepack" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "musepack"
    ExtractPackage "musepack_src_r$musepack_version.tar.gz"
    Push-Location "musepack_src_r$musepack_version"
    try {
      & patch -p1 -N -i $patch_path/musepack-fixes.patch
      CMakeBuild -additional_args @(
          "-DSHARED=ON",
          "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
        )
      Copy-Item "build/libmpcdec/*.lib" "$prefix_path/lib/" -Force -ErrorAction SilentlyContinue
      Copy-Item "build/libmpcdec/*.dll" "$prefix_path/bin/" -Force -ErrorAction SilentlyContinue
      CreatePkgConfigFile -prefix $prefix_path -name "MusePack" -description "MusePack" -url "https://www.musepack.net/" -version $musepack_version -libs "-L`${libdir} -lmpcdec" -cflags "-I`${includedir}" -output_file "$prefix_path/lib/pkgconfig/mpcdec.pc"
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-LibOpenMPT {
  Write-Host "Building libopenmpt" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "libopenmpt"
    if (-not (Test-Path "libopenmpt")) {
      $zip_file = "$downloads_path/libopenmpt-$libopenmpt_version+release.msvc.zip"
      Write-Host "Extracting $zip_file" -ForegroundColor Cyan
      New-Item -ItemType Directory -Path "libopenmpt" -Force | Out-Null
      Push-Location "libopenmpt"
      try {
        & 7z x $zip_file
        if ($LASTEXITCODE -ne 0) { throw "Failed to extract libopenmpt archive" }
      }
      finally {
        Pop-Location
      }
    }
    Push-Location "libopenmpt"
    try {
      & patch -p1 -N -i $patch_path/libopenmpt-cmake.patch
      CMakeBuild -build_path "build2"
      Write-Host "libopenmpt built successfully!" -ForegroundColor Green
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-LibGME {
  Write-Host "Building libgme" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "libgme"
    ExtractPackage "libgme-$libgme_version-src.tar.gz"
    Push-Location "libgme-$libgme_version"
    try {
      & patch -p1 -N -i $patch_path/libgme-pkgconf.patch
      CMakeBuild
      Remove-Item "$prefix_path/lib/gme-static.lib" -Force -ErrorAction SilentlyContinue
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-FdkAac {
  Write-Host "Building fdk-aac" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "fdk-aac"
    ExtractPackage "fdk-aac-$fdk_aac_version.tar.gz"
    Push-Location "fdk-aac-$fdk_aac_version"
    try {
      CMakeBuild
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-Faad2 {
  Write-Host "Building faad2" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "faad2"
    Get-ChildItem -Directory -Filter "knik0-faad2-*" | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    ExtractPackage "faad2-$faad2_version.tar.gz"
    $package_dir = (Get-ChildItem -Directory -Filter "knik0-faad2-*" | Select-Object -First 1).Name
    Push-Location $package_dir
    try {
      CMakeBuild
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-Faac {
  Write-Host "Building faac" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "faac"
    ExtractPackage "faac-$faac_version.tar.gz" -package_dir "faac-faac-$faac_version"
    Push-Location "faac-faac-$faac_version"
    try {
      MesonBuild -additional_args @("-Dfrontend=false")
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-UtfCpp {
  Write-Host "Building utfcpp (header-only)" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "utfcpp"
    ExtractPackage "utfcpp-$utfcpp_version.tar.gz"
    Push-Location "utfcpp-$utfcpp_version"
    try {
      CMakeBuild
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-TagLib {
  Write-Host "Building TagLib" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "taglib"
    ExtractPackage "taglib-$taglib_version.tar.gz"
    Push-Location "taglib-$taglib_version"
    try {
      CMakeBuild
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-LibBS2B {
  Write-Host "Building libbs2b" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "libbs2b"
    ExtractPackage "libbs2b-$libbs2b_version.tar.bz2"
    Push-Location "libbs2b-$libbs2b_version"
    try {
      & patch -p1 -N -i $patch_path/libbs2b-msvc.patch
      CMakeBuild
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-LibEBUR128 {
  Write-Host "Building libebur128" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "libebur128"
    ExtractPackage "libebur128-$libebur128_version.tar.gz"
    Push-Location "libebur128-$libebur128_version"
    try {
      CMakeBuild -additional_args @(
          "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
        )
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-FFMpeg {
  Write-Host "Building ffmpeg" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    CloneGitRepo -git_repo_name "ffmpeg"
    if (-not (Test-Path "ffmpeg")) {
      RecursiveCopy "$downloads_path/ffmpeg" "ffmpeg"
      Push-Location "ffmpeg"
      try {
        & git checkout "meson-$ffmpeg_version"
        & git checkout .
        & git pull --rebase
      }
      finally {
        Pop-Location
      }
    }
    Push-Location "ffmpeg"
    try {
      MesonBuild `
        -additional_args @(
          "-Dtests=disabled",
          "-Dgpl=enabled",
          "-Diconv=disabled",
          "-Dcheckasm=disabled"
        )
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-Chromaprint {
  Write-Host "Building chromaprint" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "chromaprint"
    ExtractPackage "chromaprint-$chromaprint_version.tar.gz" -ignore_errors $true
    Push-Location "chromaprint-$chromaprint_version"
    try {
      CMakeBuild -additional_args @(
          "-DFFMPEG_ROOT=$prefix_path",
          "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
        )
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-GStreamer {
  Write-Host "Building GStreamer" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    if ($gst_dev -eq "ON") {
      CloneGitRepo -git_repo_name "gstreamer"
      if (-not (Test-Path "gstreamer")) {
        RecursiveCopy "$downloads_path/gstreamer/subprojects/gstreamer" "gstreamer"
      }
      Push-Location "gstreamer"
    }
    else {
      DownloadPackage -package_name "gstreamer"
      ExtractPackage "gstreamer-$gstreamer_version.tar.xz"
      Push-Location "gstreamer-$gstreamer_version"
    }
    try {
      MesonBuild `
        -additional_args @(
          "-Dexamples=disabled",
          "-Dtests=disabled",
          "-Dbenchmarks=disabled",
          "-Dtools=enabled",
          "-Dintrospection=disabled",
          "-Dnls=disabled",
          "-Ddoc=disabled",
          "-Dgst_debug=true",
          "-Dgst_parse=true",
          "-Dregistry=true"
        )
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-GstPluginsBase {
  Write-Host "Building gst-plugins-base" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    if ($gst_dev -eq "ON") {
      CloneGitRepo -git_repo_name "gst-plugins-base"
      if (-not (Test-Path "gst-plugins-base")) {
        RecursiveCopy "$downloads_path/gstreamer/subprojects/gst-plugins-base" "gst-plugins-base"
      }
      Push-Location "gst-plugins-base"
    }
    else {
      DownloadPackage -package_name "gst-plugins-base"
      ExtractPackage "gst-plugins-base-$gstreamer_version.tar.xz"
      Push-Location "gst-plugins-base-$gstreamer_version"
    }
    try {
      MesonBuild `
        -additional_args @(
          "-Dexamples=disabled",
          "-Dtests=disabled",
          "-Dtools=enabled",
          "-Dintrospection=disabled",
          "-Dnls=disabled",
          "-Dorc=enabled",
          "-Ddoc=disabled",
          "-Dadder=enabled",
          "-Dapp=enabled",
          "-Daudioconvert=enabled",
          "-Daudiomixer=enabled",
          "-Daudiorate=enabled",
          "-Daudioresample=enabled",
          "-Daudiotestsrc=enabled",
          "-Ddsd=enabled",
          "-Dencoding=enabled",
          "-Dpbtypes=enabled",
          "-Dplayback=enabled",
          "-Dtypefind=enabled",
          "-Dvolume=enabled",
          "-Dogg=enabled",
          "-Dopus=enabled",
          "-Dvorbis=enabled"
        )
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-GstPluginsGood {
  Write-Host "Building gst-plugins-good" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    if ($gst_dev -eq "ON") {
      if (-not (Test-Path "gst-plugins-good")) {
        RecursiveCopy "$downloads_path/gstreamer/subprojects/gst-plugins-good" "gst-plugins-good"
      }
      Push-Location "gst-plugins-good"
    }
    else {
      DownloadPackage -package_name "gst-plugins-good"
      ExtractPackage "gst-plugins-good-$gstreamer_version.tar.xz"
      Push-Location "gst-plugins-good-$gstreamer_version"
    }
    try {
      MesonBuild `
        -additional_args @(
          "--auto-features=disabled",
          "-Dexamples=disabled",
          "-Dtests=disabled",
          "-Dnls=disabled",
          "-Dorc=enabled",
          "-Dasm=enabled",
          "-Ddoc=disabled",
          "-Dapetag=enabled",
          "-Daudiofx=enabled",
          "-Daudioparsers=enabled",
          "-Dautodetect=enabled",
          "-Dequalizer=enabled",
          "-Dicydemux=enabled",
          "-Did3demux=enabled",
          "-Disomp4=enabled",
          "-Dreplaygain=enabled",
          "-Drtp=enabled",
          "-Drtpmanager=enabled",
          "-Drtsp=enabled",
          "-Dspectrum=enabled",
          "-Dudp=enabled",
          "-Dwavenc=enabled",
          "-Dwavparse=enabled",
          "-Dxingmux=enabled",
          "-Dadaptivedemux2=enabled",
          "-Ddirectsound=enabled",
          "-Dflac=enabled",
          "-Dlame=enabled",
          "-Dmpg123=enabled",
          "-Dspeex=enabled",
          "-Dtaglib=enabled",
          "-Dwaveform=enabled",
          "-Dwavpack=enabled",
          "-Dsoup=enabled",
          "-Dmatroska=enabled",
          "-Dhls-crypto=openssl"
        )
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-GstPluginsBad {
  Write-Host "Building gst-plugins-bad" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    if ($gst_dev -eq "ON") {
      if (-not (Test-Path "gst-plugins-bad")) {
        RecursiveCopy "$downloads_path/gstreamer/subprojects/gst-plugins-bad" "gst-plugins-bad"
      }
      Push-Location "gst-plugins-bad"
    }
    else {
      DownloadPackage -package_name "gst-plugins-bad"
      ExtractPackage "gst-plugins-bad-$gstreamer_version.tar.xz"
      Push-Location "gst-plugins-bad-$gstreamer_version"
    }
    & patch -p3 -N -i "$patch_path/gstreamer-faac2.patch"
    & patch -p1 -N -i "$patch_path/gstreamer-asio.patch"
    try {
      MesonBuild `
        -additional_args @(
          "--auto-features=disabled",
          "-Dexamples=disabled",
          "-Dtools=enabled",
          "-Dtests=disabled",
          "-Dintrospection=disabled",
          "-Dnls=disabled",
          "-Dorc=enabled",
          "-Dgpl=enabled",
          "-Daiff=enabled",
          "-Dasfmux=enabled",
          "-Dmpegtsdemux=enabled",
          "-Dasio=enabled",
          "-Dbs2b=enabled",
          "-Ddash=enabled",
          "-Ddirectsound=enabled",
          "-Dfaac=enabled",
          "-Dfaad=enabled",
          "-Dfdkaac=enabled",
          "-Dgme=enabled",
          "-Dmusepack=enabled",
          "-Dopenmpt=enabled",
          "-Dopus=enabled",
          "-Dwasapi=enabled",
          "-Dwasapi2=enabled",
          "-Dhls=enabled"
        )
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-GstPluginsUgly {
  Write-Host "Building gst-plugins-ugly" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    if ($gst_dev -eq "ON") {
      if (-not (Test-Path "gst-plugins-ugly")) {
        RecursiveCopy "$downloads_path/gstreamer/subprojects/gst-plugins-ugly" "gst-plugins-ugly"
      }
      Push-Location "gst-plugins-ugly"
    }
    else {
      DownloadPackage -package_name "gst-plugins-ugly"
      ExtractPackage "gst-plugins-ugly-$gstreamer_version.tar.xz"
      Push-Location "gst-plugins-ugly-$gstreamer_version"
    }
    try {
      MesonBuild `
        -additional_args @(
          "--auto-features=disabled",
          "-Dnls=disabled",
          "-Dorc=enabled",
          "-Dtests=disabled",
          "-Ddoc=disabled",
          "-Dgpl=enabled",
          "-Dasfdemux=enabled"
        )
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-GstLibav {
  Write-Host "Building gst-libav" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    if ($gst_dev -eq "ON") {
      if (-not (Test-Path "gst-libav")) {
        RecursiveCopy "$downloads_path/gstreamer/subprojects/gst-libav" "gst-libav"
      }
      Push-Location "gst-libav"
    }
    else {
      DownloadPackage -package_name "gst-libav"
      ExtractPackage "gst-libav-$gstreamer_version.tar.xz"
      Push-Location "gst-libav-$gstreamer_version"
    }
    try {
      MesonBuild `
        -additional_args @(
          "-Dtests=disabled",
          "-Ddoc=disabled"
        )
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-GstPluginsRs {
  Write-Host "Building gst-plugins-rs (Rust GStreamer plugins)" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    CloneGitRepo -git_repo_name "gst-plugins-rs"
    if (-not (Test-Path "gst-plugins-rs")) {
      RecursiveCopy "$downloads_path/gst-plugins-rs" "gst-plugins-rs"
    }
    Push-Location "gst-plugins-rs"
    try {
      MesonBuild `
        -pkg_config_path "" `
        -additional_args @(
          "--auto-features=disabled",
          "-Dexamples=disabled",
          "-Dtests=disabled",
          "-Dspotify=enabled"
        )
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-SparseHash {
  Write-Host "Copying sparsehash" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "sparsehash"
    ExtractPackage "sparsehash-$sparsehash_version.tar.gz"
    Push-Location "sparsehash-sparsehash-$sparsehash_version"
    try {
      & patch -p1 -N -i "$patch_path/sparsehash-msvc.patch"
      Copy-Item "src/google" "$prefix_path/include/" -Recurse -Force
      Copy-Item "src/sparsehash" "$prefix_path/include/" -Recurse -Force
      Copy-Item "src/windows/sparsehash/internal/sparseconfig.h" "$prefix_path/include/sparsehash/internal/" -Force
      Copy-Item "src/windows/google/sparsehash/sparseconfig.h" "$prefix_path/include/google/sparsehash/" -Force
      CreatePkgConfigFile -prefix $prefix_path -name "sparsehash" -description "C++ associative containers" -url "https://github.com/sparsehash/sparsehash" -version $sparsehash_version -cflags "-I`${includedir}" -output_file "$prefix_path/lib/pkgconfig/libsparsehash.pc"
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-AbseilCpp {
  Write-Host "Building abseil-cpp" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "abseil-cpp"
    ExtractPackage "abseil-cpp-$abseil_version.tar.gz"
    Push-Location "abseil-cpp-$abseil_version"
    try {
      CMakeBuild -additional_args @(
          "-DCMAKE_CXX_STANDARD=17",
          "-DCMAKE_CXX_STANDARD_REQUIRED=ON",
          "-DABSL_INTERNAL_AT_LEAST_CXX17=ON",
          "-DABSL_BUILD_TESTING=OFF",
          "-DABSL_USE_EXTERNAL_GOOGLETEST=OFF"
        )
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-Protobuf {
  Write-Host "Building protobuf" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "protobuf"
    ExtractPackage "protobuf-$protobuf_version.tar.gz"
    Push-Location "protobuf-$protobuf_version"
    try {
      CMakeBuild -additional_args @(
          "-Dprotobuf_BUILD_TESTS=OFF",
          "-Dprotobuf_ABSL_PROVIDER=package"
        )
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-QtBase {
  Write-Host "Building qtbase" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    if ($qt_dev -eq "ON") {
      if (-not (Test-Path "qtbase")) {
        RecursiveCopy "$downloads_path/qtbase" "qtbase"
      }
      Push-Location "qtbase"
    }
    else {
      DownloadPackage -package_name "qtbase"
      ExtractPackage "qtbase-everywhere-src-$qt_version.tar.xz"
      Push-Location "qtbase-everywhere-src-$qt_version"
    }
    try {
      CMakeBuild -additional_args @(
          "-DQT_BUILD_EXAMPLES=OFF",
          "-DQT_BUILD_TESTS=OFF",
          "-DFEATURE_openssl=ON",
          "-DFEATURE_openssl_linked=ON",
          "-DFEATURE_system_zlib=ON",
          "-DFEATURE_system_png=ON",
          "-DFEATURE_system_jpeg=ON",
          "-DFEATURE_system_pcre2=ON",
          "-DFEATURE_system_freetype=ON",
          "-DFEATURE_system_harfbuzz=ON",
          "-DFEATURE_system_sqlite=ON",
          "-DICU_ROOT=$prefix_path"
        )
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-QtTools {
  Write-Host "Building qttools" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    if ($qt_dev -eq "ON") {
      if (-not (Test-Path "qttools")) {
        RecursiveCopy "$downloads_path/qttools" "qttools"
      }
      Push-Location "qttools"
    }
    else {
      DownloadPackage -package_name "qttools"
      ExtractPackage "qttools-everywhere-src-$qt_version.tar.xz"
      Push-Location "qttools-everywhere-src-$qt_version"
    }
    try {
      CMakeBuild `
        -additional_args @(
          "-DQT_BUILD_EXAMPLES=OFF",
          "-DQT_BUILD_EXAMPLES_BY_DEFAULT=OFF",
          "-DQT_BUILD_TOOLS_WHEN_CROSSCOMPILING=ON",
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
          "-DFEATURE_linguist=ON"
        )
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-QtImageFormats {
  Write-Host "Building qtimageformats" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    if ($qt_dev -eq "ON") {
      if (-not (Test-Path "qtimageformats")) {
        RecursiveCopy "$downloads_path/qtimageformats" "qtimageformats"
      }
      Push-Location "qtimageformats"
    }
    else {
      DownloadPackage -package_name "qtimageformats"
      ExtractPackage "qtimageformats-everywhere-src-$qt_version.tar.xz"
      Push-Location "qtimageformats-everywhere-src-$qt_version"
    }
    try {
      CMakeBuild -additional_args @(
        "-DFEATURE_jasper=ON",
        "-DFEATURE_tiff=ON",
        "-DFEATURE_webp=ON",
        "-DFEATURE_system_tiff=ON",
        "-DFEATURE_system_webp=ON"
      )
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-QtGrpc {
  Write-Host "Building qtgrpc" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    if ($qt_dev -eq "ON") {
      if (-not (Test-Path "qtgrpc")) {
        RecursiveCopy "$downloads_path/qtgrpc" "qtgrpc"
      }
      Push-Location "qtgrpc"
    }
    else {
      DownloadPackage -package_name "qtgrpc"
      ExtractPackage "qtgrpc-everywhere-src-$qt_version.tar.xz"
      Push-Location "qtgrpc-everywhere-src-$qt_version"
    }
    try {
      CMakeBuild -additional_args @(
          "-DQT_BUILD_EXAMPLES=OFF",
          "-DQT_BUILD_TESTS=OFF"
        )
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-QtSparkle {
  Write-Host "Building qtsparkle" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    CloneGitRepo -git_repo_name "qtsparkle"
    if (-not (Test-Path "qtsparkle")) {
      RecursiveCopy "$downloads_path/qtsparkle" "qtsparkle"
    }
    Push-Location "qtsparkle"
    try {
      CMakeBuild -additional_args @(
        "-DBUILD_WITH_QT6=ON"
      )
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-KDSingleApplication {
  Write-Host "Building KDSingleApplication" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "kdsingleapplication"
    ExtractPackage "kdsingleapplication-$kdsingleapplication_version.tar.gz"
    Push-Location "kdsingleapplication-$kdsingleapplication_version"
    try {
      CMakeBuild -additional_args @("-DKDSingleApplication_QT6=ON")
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-Glew {
  Write-Host "Building glew" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "glew"
    ExtractPackage "glew-$glew_version.tgz"
    Push-Location "glew-$glew_version"
    try {
      CMakeBuild -source_path "build/cmake" -additional_args @("-DCMAKE_POLICY_VERSION_MINIMUM=3.5")
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-LibProjectm {
  Write-Host "Building libprojectm" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "libprojectm"
    ExtractPackage "libprojectm-$libprojectm_version.tar.gz"
    Push-Location "libprojectm-$libprojectm_version"
    try {
      CMakeBuild
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-TinySvcmdns {
  Write-Host "Building tinysvcmdns" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    CloneGitRepo -git_repo_name "tinysvcmdns"
    if (-not (Test-Path "tinysvcmdns")) {
      RecursiveCopy "$downloads_path/tinysvcmdns" "tinysvcmdns"
    }
    Push-Location "tinysvcmdns"
    try {
      CMakeBuild -additional_args @("-DCMAKE_POLICY_VERSION_MINIMUM=3.5")
      Copy-Item "*.lib" "$prefix_path/lib/" -Force
      Copy-Item "*.dll" "$prefix_path/bin/" -Force
      Copy-Item "*.exe" "$prefix_path/bin/" -Force
      Copy-Item "*.h" "$prefix_path/include/" -Force
      Copy-Item "../*.h" "$prefix_path/include/" -Force
      CreatePkgConfigFile -prefix $prefix_path -name "tinysvcmdns" -description "tinysvcmdns" -version "0.1" -cflags "-I`${includedir}" -libs "-L`${libdir} -ltinysvcmdns" -output_file "$prefix_path/lib/pkgconfig/tinysvcmdns.pc"
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-PeParse {
  Write-Host "Building pe-parse" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    DownloadPackage -package_name "pe-parse"
    ExtractPackage "pe-parse-$peparse_version.tar.gz"
    Push-Location "pe-parse-$peparse_version"
    try {
      CMakeBuild -additional_args @("-DBUILD_COMMAND_LINE_TOOLS=OFF")
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-PeUtil {
  Write-Host "Building pe-util" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    CloneGitRepo -git_repo_name "pe-util"
    if (-not (Test-Path "pe-util")) {
      RecursiveCopy "$downloads_path/pe-util" "pe-util"
    }
    Push-Location "pe-util"
    try {
      CMakeBuild -additional_args @("-DBUILD_COMMAND_LINE_TOOLS=OFF")
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-Strawberry {
  Write-Host "Building strawberry" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    CloneGitRepo -git_repo_name "strawberry"
    if (-not (Test-Path "strawberry")) {
      RecursiveCopy "$downloads_path/strawberry" "strawberry"
    }
    Push-Location "strawberry"
    try {
      $enable_win32_console = if ($build_type -eq "debug") { "ON" } else { "OFF" }
      CMakeBuild -additional_args @(
          "-DARCH=$arch",
          "-DENABLE_TRANSLATIONS=ON",
          "-DBUILD_WERROR=ON",
          "-DENABLE_WIN32_CONSOLE=$enable_win32_console",
          "-DICU_ROOT=$prefix_path",
          "-DENABLE_AUDIOCD=OFF",
          "-DENABLE_MTP=OFF",
          "-DENABLE_GPOD=OFF"
        )
      Write-Host "Strawberry built successfully!" -ForegroundColor Green
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

function Build-StrawberrySetup {
  Write-Host "Creating StrawberrySetup" -ForegroundColor Yellow
  Push-Location $build_path
  try {
    New-Item -Path "StrawberrySetup" -ItemType Directory -Force | Out-Null
    Push-Location "StrawberrySetup"
    try {
      New-Item -Path @('platforms', 'styles', 'imageformats', 'tls', 'sqldrivers', 'gio-modules', 'gstreamer-plugins') -ItemType Directory -Force
      Copy-Item -Path "$build_path/strawberry/build/strawberry.exe", `
                      "$build_path/strawberry/build/strawberry.nsi", `
                      "$build_path/strawberry/COPYING", `
                      "$build_path/strawberry/dist/windows/*.ico", `
                      "$build_path/strawberry/dist/windows/*.nsh" `
                      "." -Force
      Copy-Item "$prefix_path/plugins/platforms/*.dll" "./platforms/" -Force
      Copy-Item "$prefix_path/plugins/styles/*.dll" "./styles/" -Force
      Copy-Item "$prefix_path/plugins/imageformats/*.dll" "./imageformats/" -Force
      Copy-Item "$prefix_path/plugins/tls/*.dll" "./tls/" -Force
      Copy-Item "$prefix_path/plugins/sqldrivers/*.dll" "./sqldrivers/" -Force
      Copy-Item "$prefix_path/lib/gio/modules/*.dll" "./gio-modules/" -Force
      Copy-Item "$prefix_path/lib/gstreamer-1.0/*.dll" "./gstreamer-plugins/" -Force
      Copy-Item -Path "$prefix_path/bin/sqlite3.exe", "$prefix_path/bin/gst-*.exe" -Destination "." -Force
      & "$PSScriptRoot/CopyDLLDependencies.ps1" -Copy -DestDir "./" -InDir "./" -InDir "./platforms" -InDir "./styles" -InDir "./imageformats" -InDir "./tls" -InDir "./sqldrivers" -InDir "./gio-modules" -InDir "./gstreamer-plugins" -RecursiveSrcDir "$prefix_path/bin"
      DownloadPackage -package_name "vc-redist-${arch_short}"
      Copy-Item "$downloads_path/vc_redist.${arch_short}.exe" "." -Force
      & makensis strawberry.nsi
      Write-Host "Strawberry setup built successfully!" -ForegroundColor Green
    }
    finally {
      Pop-Location
    }
  }
  finally {
    Pop-Location
  }
}

#endregion

#region Main Build Logic

Write-Host "Starting build process..." -ForegroundColor Cyan
Write-Host ""

try {
  $build_queue = @()

  if (-not (Test-Path "$prefix_path/bin/pkgconf.exe")) { $build_queue += "pkgconf" }
  if (-not (Test-Path "$prefix_path/bin/yasm.exe")) { $build_queue += "yasm" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/intl.pc")) { $build_queue += "proxy-libintl" }
  if (-not (Test-Path "$prefix_path/lib/getopt.lib")) { $build_queue += "getopt-win" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/zlib.pc")) { $build_queue += "zlib" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/openssl.pc")) { $build_queue += "openssl" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/libpng.pc")) { $build_queue += "libpng" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/libjpeg.pc")) { $build_queue += "libjpeg-turbo" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/libpcre2-16.pc")) { $build_queue += "pcre2" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/bzip2.pc")) { $build_queue += "bzip2" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/liblzma.pc")) { $build_queue += "xz" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/libbrotlicommon.pc")) { $build_queue += "brotli" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/icu-uc.pc")) { $build_queue += "icu4c" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/pixman-1.pc")) { $build_queue += "pixman" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/expat.pc")) { $build_queue += "expat" }
  if (-not (Test-Path "$prefix_path/include/boost/config.hpp")) { $build_queue += "boost" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/libxml-2.0.pc")) { $build_queue += "libxml2" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/libnghttp2.pc")) { $build_queue += "nghttp2" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/libffi.pc")) { $build_queue += "libffi" }
  if (-not (Test-Path "$prefix_path/include/dlfcn.h")) { $build_queue += "dlfcn-win32" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/libpsl.pc")) { $build_queue += "libpsl" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/orc-0.4.pc")) { $build_queue += "orc" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/sqlite3.pc")) { $build_queue += "sqlite" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/glib-2.0.pc")) { $build_queue += "glib" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/libsoup-3.0.pc")) { $build_queue += "libsoup" }
  if (-not (Test-Path "$prefix_path/lib/gio/modules/gioopenssl.lib")) { $build_queue += "glib-networking" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/freetype2.pc")) { $build_queue += "freetype" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/harfbuzz.pc")) { $build_queue += "harfbuzz" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/jasper.pc")) { $build_queue += "jasper" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/libtiff-4.pc")) { $build_queue += "tiff" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/libwebp.pc")) { $build_queue += "libwebp" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/ogg.pc")) { $build_queue += "ogg" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/vorbis.pc")) { $build_queue += "vorbis" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/flac.pc")) { $build_queue += "flac" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/wavpack.pc")) { $build_queue += "wavpack" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/opus.pc")) { $build_queue += "opus" }
  if (-not (Test-Path "$prefix_path/bin/opusfile.dll")) { $build_queue += "opusfile" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/speex.pc")) { $build_queue += "speex" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/libmpg123.pc")) { $build_queue += "mpg123" }
  if (-not (Test-Path "$prefix_path/lib/mp3lame.lib")) { $build_queue += "lame" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/fftw3.pc")) { $build_queue += "fftw3" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/mpcdec.pc")) { $build_queue += "musepack" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/libopenmpt.pc")) { $build_queue += "libopenmpt" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/libgme.pc")) { $build_queue += "libgme" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/fdk-aac.pc")) { $build_queue += "fdk-aac" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/faad2.pc")) { $build_queue += "faad2" }
  if (-not (Test-Path "$prefix_path/lib/faac.lib")) { $build_queue += "faac" }
  if (-not (Test-Path "$prefix_path/include/utf8cpp/utf8.h")) { $build_queue += "utfcpp" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/taglib.pc")) { $build_queue += "taglib" }
  if (-not (Test-Path "$prefix_path/lib/libbs2b.lib")) { $build_queue += "libbs2b" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/libebur128.pc")) { $build_queue += "libebur128" }
  if (-not (Test-Path "$prefix_path/lib/avutil.lib")) { $build_queue += "ffmpeg" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/libchromaprint.pc")) { $build_queue += "chromaprint" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/gstreamer-1.0.pc")) { $build_queue += "gstreamer" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/gstreamer-base-1.0.pc")) { $build_queue += "gst-plugins-base" }
  if (-not (Test-Path "$prefix_path/lib/gstreamer-1.0/gstflac.dll")) { $build_queue += "gst-plugins-good" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/gstreamer-plugins-bad-1.0.pc")) { $build_queue += "gst-plugins-bad" }
  if (-not (Test-Path "$prefix_path/lib/gstreamer-1.0/gstasf.dll")) { $build_queue += "gst-plugins-ugly" }
  if (-not (Test-Path "$prefix_path/lib/gstreamer-1.0/gstlibav.dll")) { $build_queue += "gst-libav" }
  if (-not (Test-Path "$prefix_path/lib/gstreamer-1.0/gstspotify.dll")) { $build_queue += "gst-plugins-rs" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/absl_any.pc")) { $build_queue += "abseil-cpp" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/protobuf.pc")) { $build_queue += "protobuf" }
  if (-not (Test-Path "$prefix_path/bin/qt-configure-module.bat")) { $build_queue += "qtbase" }
  if (-not (Test-Path "$prefix_path/bin/lconvert.exe")) { $build_queue += "qttools" }
  if (-not (Test-Path "$prefix_path/plugins/imageformats/qwebp${lib_postfix}.dll")) { $build_queue += "qtimageformats" }
  if (-not (Test-Path "$prefix_path/lib/cmake/Qt6Protobuf/Qt6ProtobufConfig.cmake")) { $build_queue += "qtgrpc" }
  if (-not (Test-Path "$prefix_path/lib/cmake/KDSingleApplication-qt6/KDSingleApplication-qt6Config.cmake")) { $build_queue += "kdsingleapplication" }
  if (-not (Test-Path "$prefix_path/lib/cmake/qtsparkle-qt6/qtsparkle-qt6Config.cmake")) { $build_queue += "qtsparkle" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/libsparsehash.pc")) { $build_queue += "sparsehash" }
  if (-not (Test-Path "$prefix_path/lib/cmake/glew/glew-config.cmake")) { $build_queue += "glew" }
  if (-not (Test-Path "$prefix_path/lib/cmake/projectM4/projectM4Config.cmake")) { $build_queue += "libprojectm" }
  if (-not (Test-Path "$prefix_path/lib/pkgconfig/tinysvcmdns.pc")) { $build_queue += "tinysvcmdns" }
  if (-not (Test-Path "$prefix_path/lib/cmake/pe-parse/pe-parse-config.cmake")) { $build_queue += "pe-parse" }
  if (-not (Test-Path "$prefix_path/bin/peldd.exe")) { $build_queue += "pe-util" }
  if (-not (Test-Path "$build_path/strawberry/build/strawberry.exe")) { $build_queue += "strawberry" }
  if (-not (Test-Path "$build_path/StrawberrySetup/StrawberrySetup*.exe")) { $build_queue += "strawberry-setup" }

  if ($build_queue.Count -eq 0) {
    Write-Host "All dependencies already built!" -ForegroundColor Green
    exit 0
  }

  Write-Host "Build queue: $($build_queue -join ', ')" -ForegroundColor Cyan
  Write-Host ""

  # Build each component
  foreach ($component in $build_queue) {
    Write-Host "========================================" -ForegroundColor Magenta
    Write-Host "Building: $component" -ForegroundColor Magenta
    Write-Host "========================================" -ForegroundColor Magenta

    switch ($component) {
      "pkgconf" { Build-PkgConf }
      "yasm" { Build-Yasm }
      "proxy-libintl" { Build-ProxyIntl }
      "getopt-win" { Build-GetOptWin }
      "zlib" { Build-Zlib }
      "openssl" { Build-OpenSSL }
      "libpng" { Build-LibPNG }
      "libjpeg-turbo" { Build-LibJPEGTurbo }
      "pcre2" { Build-PCRE2 }
      "bzip2" { Build-BZip2 }
      "xz" { Build-XZ }
      "brotli" { Build-Brotli }
      "icu4c" { Build-ICU4C }
      "pixman" { Build-Pixman }
      "expat" { Build-Expat }
      "boost" { Build-Boost }
      "libxml2" { Build-LibXML2 }
      "nghttp2" { Build-NgHttp2 }
      "libffi" { Build-LibFFI }
      "dlfcn-win32" { Build-DlfcnWin32 }
      "libpsl" { Build-LibPSL }
      "orc" { Build-Orc }
      "sqlite" { Build-SQLite }
      "glib" { Build-Glib }
      "libsoup" { Build-LibSoup }
      "glib-networking" { Build-GlibNetworking }
      "freetype" { Build-Freetype -with_harfbuzz $false }
      "harfbuzz" { Build-Harfbuzz }
      "jasper" { Build-Jasper }
      "tiff" { Build-Tiff }
      "libwebp" { Build-LibWebP }
      "ogg" { Build-Ogg }
      "vorbis" { Build-Vorbis }
      "flac" { Build-Flac }
      "wavpack" { Build-WavPack }
      "opus" { Build-Opus }
      "opusfile" { Build-Opusfile }
      "speex" { Build-Speex }
      "mpg123" { Build-MPG123 }
      "lame" { Build-Lame }
      "fftw3" { Build-FFTW3 }
      "musepack" { Build-Musepack }
      "libopenmpt" { Build-LibOpenMPT }
      "libgme" { Build-LibGME }
      "fdk-aac" { Build-FdkAac }
      "faad2" { Build-Faad2 }
      "faac" { Build-Faac }
      "utfcpp" { Build-UtfCpp }
      "taglib" { Build-TagLib }
      "libbs2b" { Build-LibBS2B }
      "libebur128" { Build-LibEBUR128 }
      "ffmpeg" { Build-FFMpeg }
      "chromaprint" { Build-Chromaprint }
      "gstreamer" { Build-GStreamer }
      "gst-plugins-base" { Build-GstPluginsBase }
      "gst-plugins-good" { Build-GstPluginsGood }
      "gst-plugins-bad" { Build-GstPluginsBad }
      "gst-plugins-ugly" { Build-GstPluginsUgly }
      "gst-libav" { Build-GstLibAv }
      "gst-plugins-rs" { Build-GstPluginsRs }
      "abseil-cpp" { Build-AbseilCpp }
      "protobuf" { Build-Protobuf }
      "qtbase" { Build-QtBase }
      "qttools" { Build-QtTools }
      "qtimageformats" { Build-QtImageFormats }
      "qtgrpc" { Build-QtGrpc }
      "kdsingleapplication" { Build-KDSingleApplication }
      "qtsparkle" { Build-QtSparkle }
      "sparsehash" { Build-SparseHash }
      "glew" { Build-Glew }
      "libprojectm" { Build-LibProjectm }
      "tinysvcmdns" { Build-TinySvcmdns }
      "pe-parse" { Build-PeParse }
      "pe-util" { Build-PeUtil }
      "strawberry" { Build-Strawberry }
      "strawberry-setup" { Build-StrawberrySetup }
      default {
        Write-Warning "Unknown component: $component (skipping)"
      }
    }

    Write-Host "Completed: $component" -ForegroundColor Green
    Write-Host ""
  }

  Write-Host "========================================" -ForegroundColor Green
  Write-Host "Build completed successfully!" -ForegroundColor Green
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

#endregion
