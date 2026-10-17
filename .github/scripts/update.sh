#!/bin/bash
#
#  STRAWBERRY MSVC BUILD TOOLS UPDATE SCRIPT
#  Copyright (C) 2022-2026 Jonas Kvinge
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

versions_file="StrawberryPackageVersions.txt"
curl_options="-s -f -L"

function timestamp() { date '+%Y-%m-%d %H:%M:%S'; }
function status() { echo "[$(timestamp)] $*"; }
function error() { echo "[$(timestamp)] ERROR: $*" >&2; }

function latest_github_release() {

  curl ${curl_options} -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" -H "Authorization: Bearer ${gh_token}" "https://api.github.com/repos/$1/$2/releases/latest" | jq -r '.tag_name' | sed 's/^version-//g' | sed 's/^v//g' | sed 's/^sparsehash-//g' | sed 's/^faac-//g' | sed 's/^nettle_//g' | sort -V | head -1

}

function latest_git_commit() {

  git ls-remote "$1" HEAD | cut -f 1

}

function update_repo() {

  git fetch >/dev/null 2>&1 || exit 1
  if [ $? -ne 0 ]; then
    error "Could not fetch"
    exit 1
  fi

  git checkout . >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    error "Could not checkout ."
    exit 1
  fi

  if ! [ "$(git branch | head -1 | cut -d ' ' -f2)" = "master" ]; then
    git checkout master >/dev/null 2>&1
    if [ $? -ne 0 ]; then
      error "Could not checkout master branch."
      exit 1
    fi
  fi

  git pull origin master --rebase >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    error "Could not pull with rebase."
    exit 1
  fi

}

function merge_prs() {

  local prs
  local pr
  local pr_json
  local pr_author
  local pr_head
  local pr_branch
  local pr_title
  local pr_update
  local package
  local review_decision
  local status_check_rollup
  local status_check_ok
  local status_check_total

  # gh pr list only returns 30 pull requests by default.
  prs=$(gh pr list --limit 1000 --json number | jq '.[].number')
  if [ "${prs}" = "" ]; then
    return
  fi

  for pr in ${prs}; do
    # Get everything in one request, so the checks below are for the same head commit that is merged.
    pr_json=$(gh pr view "${pr}" --json 'author,baseRefName,headRefName,headRefOid,isDraft,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup,title')
    if [ $? -ne 0 ] || [ "${pr_json}" = "" ]; then
      error "Could not get pull request ${pr}."
      continue
    fi
    pr_head=$(echo "${pr_json}" | jq -r '.headRefOid')
    if [ "${pr_head}" = "" ] || [ "${pr_head}" = "null" ]; then
      continue
    fi
    if ! [ "$(echo "${pr_json}" | jq -r '.baseRefName')" = "master" ]; then
      continue
    fi
    # Only merge dependency updates, from dependabot or created by update_package.
    pr_author=$(echo "${pr_json}" | jq -r '.author.login')
    pr_branch=$(echo "${pr_json}" | jq -r '.headRefName')
    pr_title=$(echo "${pr_json}" | jq -r '.title')
    pr_update=0
    # gh reports dependabot as app/dependabot.
    if [ "${pr_author}" = "app/dependabot" ]; then
      if [[ "${pr_branch}" == dependabot/* ]]; then
        pr_update=1
      fi
    elif [ "${pr_author}" = "${gh_username}" ] || [ "${pr_author}" = "jonaski" ]; then
      for package in $(get_packages); do
        if [[ "${pr_branch}" == "${package}_"* ]] && [[ "${pr_title}" == "Update ${package} to "* ]]; then
          pr_update=1
          break
        fi
      done
    fi
    if ! [ "${pr_update}" = "1" ]; then
      continue
    fi
    if ! [ "$(echo "${pr_json}" | jq '.isDraft')" = "false" ]; then
      continue
    fi
    if ! [ "$(echo "${pr_json}" | jq -r '.mergeable')" = "MERGEABLE" ]; then
      continue
    fi
    if ! [ "$(echo "${pr_json}" | jq -r '.mergeStateStatus')" = "CLEAN" ]; then
      continue
    fi
    review_decision=$(echo "${pr_json}" | jq -r '.reviewDecision')
    if [ ! "${review_decision}" = "" ] && [ ! "${review_decision}" = "APPROVED" ] ; then
      continue
    fi
    status_check_rollup="${pr_json}"
    status_check_ok="1"
    status_check_total=$(echo "${status_check_rollup}" | jq '.statusCheckRollup | length')
    # A new pull request can be clean before the checks are registered, so don't merge without any checks.
    if [ "${status_check_total}" = "" ] || [ "${status_check_total}" = "0" ]; then
      continue
    fi
    for ((i = 0; i < status_check_total; i++)); do
      # Use the conclusion of completed check runs, legacy commit statuses have a state instead.
      status_check=$(echo "${status_check_rollup}" | jq -r ".statusCheckRollup[${i}] | if .__typename == \"StatusContext\" then .state elif .status == \"COMPLETED\" then .conclusion else .status end")
      if ! [ "${status_check}" = "SUCCESS" ] && ! [ "${status_check}" = "NEUTRAL" ] && ! [ "${status_check}" = "SKIPPED" ]; then
        status_check_ok=0
        break
      fi
    done
    if ! [ "${status_check_ok}" = "1" ]; then
      continue
    fi
    status "Merging pull request ${pr}."
    gh pr merge -dr --match-head-commit "${pr_head}" "${pr}"
  done

}

function get_packages() {

  sed -n "s,^\([A-Z0-9_]*\)_VERSION=.*$,\1,p" "${versions_file}" | tr '[:upper:]' '[:lower:]' | tr '\n' ' '

}

function update_packages() {

  packages=$(get_packages)
  local failed=0
  for package in ${packages}; do
    update_package "${package}" || failed=1
    update_repo
  done

  # Fail after checking all packages, so a broken version check doesn't go unnoticed.
  return ${failed}

}

function update_package() {

  local package_name
  local package_version_current
  local package_version_latest
  local package_git
  local package_variable
  local package_year
  local package_year_variable
  local package_download
  local pr_mergeable
  local branch_head

  package_name="${1}"
  package_git=0
  package_year=
  package_year_variable="$(echo "${package_name}" | tr '[:lower:]' '[:upper:]')_YEAR"
  package_variable="$(echo "${package_name}" | tr '[:lower:]' '[:upper:]')_VERSION"
  package_version_current=$(sed -n "s,^${package_variable}=\(.*\)\$,\1,p" "${versions_file}" | tr -d '[:space:]')

  if [ "${package_version_current}" = "" ]; then
    error "Could not get current version for ${package}."
    return 1
  fi

  case ${package_name} in
    "nasm")
      package_version_latest=$(curl ${curl_options} 'https://www.nasm.us/pub/nasm/releasebuilds/?C=M;O=D' | sed -n 's,.*href="\([0-9\.]*[^a-z]\)/".*,\1,p' | sort -V | tail -1)
      ;;
    "yasm")
      package_version_latest=$(latest_git_commit "https://github.com/yasm/yasm.git")
      package_git=1
      ;;
    "win_flex_bison")
      package_version_latest=$(curl ${curl_options} 'https://sourceforge.net/projects/winflexbison/files/' | sed -n 's,.*<a href=".*files\/win_flex_bison-\(.*\)\.zip\/.*,\1,p' | grep -v 'latest' | sort -V | tail -1)
      ;;
    "pkgconf")
      package_version_latest=$(curl ${curl_options} 'https://github.com/pkgconf/pkgconf/tags' | sed -n 's#.*releases/tag/\([^"]*\).*#\1#p' | sed 's/^pkgconf\-//g' | sort -V | tail -1)
      ;;
    "zlib")
      package_version_latest=$(curl ${curl_options} 'https://zlib.net/' | sed -n 's,.*zlib-\([0-9][^>]*\)\.tar.*,\1,ip' | sort -V | tail -1)
      ;;
    "openssl")
      package_version_latest=$(curl ${curl_options} 'https://www.openssl.org/source/' | sed -n 's,.*openssl-\([0-9][0-9a-z.]*\)\.tar.*,\1,p' | sort -V | tail -1)
      ;;
    "libpng")
      package_version_latest=$(curl ${curl_options} 'https://sourceforge.net/p/libpng/code/ref/master/tags/' | sed -n 's,.*<a[^>]*>v\([0-9][^<]*\)<.*,\1,p' | grep -v alpha | grep -v beta | grep -v rc | sort -V | tail -1)
      ;;
    "libjpeg_turbo")
      package_version_latest=$(latest_github_release "libjpeg-turbo" "libjpeg-turbo")
      ;;
    "pcre2")
      package_version_latest=$(latest_github_release "PCRE2Project" "pcre2" | sed 's/^pcre2\-//g' | grep -iv rc | sort -V | tail -1)
      ;;
    "bzip2")
      package_version_latest=$(curl ${curl_options} 'https://sourceware.org/pub/bzip2/' | grep 'bzip2-' | sed -n 's,.*bzip2-\([0-9][^>]*\)\.tar.*,\1,p' | sort -V | tail -1)
      ;;
    "xz")
      package_version_latest=$(latest_github_release "tukaani-project" "xz")
      ;;
    "brotli")
      package_version_latest=$(latest_github_release "google" "brotli")
      ;;
    "uchardet")
      package_version_latest=$(curl ${curl_options} 'https://www.freedesktop.org/software/uchardet/releases/' | sed -n 's,.*uchardet-\([0-9][^"]*\)\.tar\.xz.*,\1,p' | sort -V | tail -1)
      ;;
    "icu4c")
      package_version_latest=$(latest_github_release "unicode-org" "icu" | sed 's/release\-//g' | tr '\-' '\.')
      ;;
    "pixman")
      package_version_latest=$(curl ${curl_options} 'https://www.cairographics.org/releases/?C=M;O=D' | sed -n 's,.*"pixman-\([0-9][^"]*\)\.tar.*,\1,p' | head -1)
      ;;
    "expat")
      package_version_latest=$(latest_github_release "libexpat" "libexpat" | sed 's/R_//g' | tr '_' '.')
      ;;
    "libxml2")
      package_version_latest=$(curl ${curl_options} 'https://gitlab.gnome.org/GNOME/libxml2/tags' | sed -n "s,.*<a [^>]\+>v\([0-9,\.]\+\)<.*,\\1,p" | head -1)
      ;;
    "nghttp2")
      package_version_latest=$(latest_github_release "nghttp2" "nghttp2")
      ;;
    "dlfcn")
      package_version_latest=$(latest_github_release "dlfcn-win32" "dlfcn-win32")
      ;;
    "libffi")
      package_version_latest=$(latest_git_commit "https://gitlab.freedesktop.org/gstreamer/meson-ports/libffi.git")
      package_git=1
      ;;
    "libpsl")
      package_version_latest=$(latest_github_release "rockdaboot" "libpsl")
      ;;
    "orc")
      package_version_latest=$(curl ${curl_options} 'https://gstreamer.freedesktop.org/src/orc' | sed -n "s,.*orc-\([0-9]*\.[0-9]*\.[0-9]*\)\.tar\.xz.*,\\1,p" | sort -V | tail -1)
      ;;
    "sqlite")
      # The download is in a directory for the release year, so get the year too.
      package_download=$(curl ${curl_options} 'https://www.sqlite.org/download.html' | sed -n 's,.*\([0-9]\{4\}\)/sqlite-autoconf-\([0-9][^>]*\)\.tar.*,\2 \1,p' | sort -V | tail -1)
      package_version_latest=$(echo "${package_download}" | cut -d ' ' -f 1)
      package_year=$(echo "${package_download}" | cut -d ' ' -f 2)
      ;;
    "glib")
      package_version_latest=$(curl ${curl_options} 'https://gitlab.gnome.org/GNOME/glib/tags' | sed -n "s,.*<a [^>]\+>v\?\([0-9]\+\.[0-9.]\+\)<.*,\1,p" | sort -V | tail -1)
      ;;
    "libsoup")
      package_version_latest=$(curl ${curl_options} 'https://gitlab.gnome.org/GNOME/libsoup/tags' | sed -n "s,.*<a [^>]\+>v\?\([0-9]\+\.[0-9]*[02468]\.[0-9]\+\)<.*,\1,p" | sort -V | tail -1)
      ;;
    "libproxy")
      package_version_latest=$(latest_github_release "libproxy" "libproxy")
      ;;
    "glib_networking")
      package_version_latest=$(latest_git_commit "https://gitlab.gnome.org/GNOME/glib-networking.git")
      package_git=1
      ;;
    "freetype")
      package_version_latest=$(curl ${curl_options} 'https://sourceforge.net/projects/freetype/files/freetype2/' | sed -n 's,.*/projects/.*/\([0-9][^"]*\)/".*,\1,p' | sort -V | tail -1)
      ;;
    "cairo")
      package_version_latest=$(curl ${curl_options} 'https://www.cairographics.org/releases/?C=M;O=D' | sed -n 's,.*"cairo-\([0-9]\+\.[0-9]*[02468]\.[0-9]\+\)\.tar.*,\1,p' | sort -V | tail -1)
      ;;
    "harfbuzz")
      package_version_latest=$(latest_github_release "harfbuzz" "harfbuzz")
      ;;
    "libogg")
      package_version_latest=$(curl ${curl_options} 'https://www.xiph.org/downloads/' | sed -n 's,.*libogg-\([0-9][^>]*\)\.tar.*,\1,p' | sort -V | tail -1)
      ;;
    "libvorbis")
      package_version_latest=$(curl ${curl_options} 'https://www.xiph.org/downloads/' | sed -n 's,.*libvorbis-\([0-9][^>]*\)\.tar.*,\1,p' | sort -V | tail -1)
      ;;
    "flac")
      package_version_latest=$(latest_github_release "xiph" "flac")
      ;;
    "wavpack")
      package_version_latest=$(curl ${curl_options} 'https://www.wavpack.com/downloads.html' | sed -n "s,.*\"wavpack-\(.*\)\.tar.*,\1,p" | sort -V | tail -1)
      ;;
    "opus")
      package_version_latest=$(curl ${curl_options} 'https://downloads.xiph.org/releases/opus/?C=M;O=D' | sed -n 's,.*opus-\([0-9][^>]*\)\.tar.*,\1,p' | grep -v 'alpha' | grep -v 'beta' | grep -v 'rc' | sort -V | tail -1)
      ;;
    "opusfile")
      package_version_latest=$(curl ${curl_options} 'https://downloads.xiph.org/releases/opus/?C=M;O=D' | sed -n 's,.*opusfile-\([0-9][^>]*\)\.tar.*,\1,p' | grep -v 'alpha' | grep -v 'beta' | sort -V | tail -1)
      ;;
    "speex")
      package_version_latest=$(curl ${curl_options} 'https://downloads.xiph.org/releases/speex/' | sed -n 's,.*<a href="speex-\([0-9][0-9.]*\)\.tar\.[gx]z">.*,\1,p' | sort -V | tail -1)
      ;;
    "mpg123")
      package_version_latest=$(curl ${curl_options} 'https://sourceforge.net/projects/mpg123/files/mpg123/' | sed -n 's,.*/projects/.*/\([0-9][^"]*\)/".*,\1,p' | grep -v 'beta' | grep -v 'svn' | sort -V | tail -1)
      ;;
    "lame")
      package_version_latest=$(curl ${curl_options} 'https://sourceforge.net/p/lame/svn/HEAD/tree/tags' | grep RELEASE_ | sed -n 's,.*RELEASE__\([0-9_][^<]*\)<.*,\1,p' | tr '_' '.' | sort -V | tail -1)
      ;;
    "musepack")
      package_version_latest=$(curl ${curl_options} 'https://www.musepack.net/index.php?pg=src' | sed -n 's,.*musepack_src_r\([^>]*\)\.tar.*,\1,p' | sort -V | tail -1)
      ;;
    "libopenmpt")
      package_version_latest=$(curl ${curl_options} 'https://lib.openmpt.org/files/libopenmpt/src/' | sed -n 's,.*libopenmpt-\([0-9][^>]*\)+release\.autotools\.tar.*,\1,p' | sort -V | tail -1)
      ;;
    "libgme")
      package_version_latest=$(latest_github_release "libgme" "game-music-emu")
      ;;
    "faad2")
      package_version_latest=$(latest_github_release "knik0" "faad2")
      ;;
    "faac")
      package_version_latest=$(latest_github_release "knik0" "faac")
      ;;
    "fdk_aac")
      package_version_latest=$(curl ${curl_options} 'https://sourceforge.net/projects/opencore-amr/files/fdk-aac/' | sed -n 's,.*fdk-aac-\([0-9.]*\)\.tar.*,\1,p' | sort -V | tail -1)
      ;;
    "utfcpp")
      package_version_latest=$(latest_github_release "nemtrif" "utfcpp")
      ;;
    "taglib")
      package_version_latest=$(latest_github_release "taglib" "taglib")
      ;;
    "libbs2b")
      package_version_latest=$(curl ${curl_options} 'https://sourceforge.net/projects/bs2b/files/libbs2b/' | sed -n 's,.*<a href="/projects/bs2b/files/libbs2b/\([0-9][^"]*\)/".*,\1,p' | sort -V | tail -1)
      ;;
    "libebur128")
      package_version_latest=$(latest_github_release "jiixyj" "libebur128")
      ;;
    "fftw_source")
      package_version_latest=$(curl ${curl_options} 'https://www.fftw.org/download.html' | sed -n 's,.*fftw-\([0-9][^>]*\)\.tar.*,\1,p' | head -1)
      ;;
    "fftw_mingw")
      package_version_latest=$(latest_github_release "strawberrymusicplayer" "fftw3-mingw-cross")
      ;;
    "ffmpeg")
      package_version_latest=$(git ls-remote --heads https://gitlab.freedesktop.org/gstreamer/meson-ports/ffmpeg.git | cut -d '/' -f 3 | grep '^meson-' | sed 's/^meson-//g' | sort -V | tail -1)
      ;;
    "chromaprint")
      package_version_latest=$(latest_github_release "acoustid" "chromaprint")
      ;;
    "gstreamer")
      package_version_latest=$(curl ${curl_options} 'https://gstreamer.freedesktop.org/src/gstreamer' | sed -n "s,.*gstreamer-\([0-9]\.[0-9][02468]\.[0-9]*\)\.tar\.xz.*,\\1,p" | sort -V | tail -1)
      ;;
    "gstreamer_plugins_rs")
      package_version_latest=$(git ls-remote --tags https://gitlab.freedesktop.org/gstreamer/gst-plugins-rs.git | cut -d ' ' -f 2 | grep -v 'gstreamer' | cut -d '/' -f 3 | sed '/.\^/d' | sort -V | tail -1)
      ;;
    "qt")
      qt_major_version=$(curl ${curl_options} "https://download.qt.io/official_releases/qt/" | sed -n 's,.*<a href=\"\([0-9]*\.[0-9]*\).*,\1,p' | sort -V | tail -1)
      package_version_latest=$(curl ${curl_options} "https://download.qt.io/official_releases/qt/${qt_major_version}/" | sed -n 's,.*href="\([0-9]*\.[0-9]*\.[^/]*\)/".*,\1,p' | sort -V | tail -1)
      ;;
    "kdsingleapplication")
      package_version_latest=$(latest_github_release "KDAB" "KDSingleApplication")
      ;;
    "qtsparkle")
      package_version_latest=$(latest_git_commit "https://github.com/jonaski/qtsparkle.git")
      package_git=1
      ;;
    "abseil")
      package_version_latest=$(latest_github_release "abseil" "abseil-cpp")
      ;;
    "protobuf")
      package_version_latest=$(latest_github_release "protocolbuffers" "protobuf")
      ;;
    "sparsehash")
      package_version_latest=$(latest_github_release "sparsehash" "sparsehash")
      ;;
    "getopt_win")
      package_version_latest=$(latest_github_release "ludvikjerabek" "getopt-win")
      ;;
    "proxy_libintl")
      package_version_latest=$(latest_github_release "frida" "proxy-libintl")
      ;;
    "jasper")
      package_version_latest=$(latest_github_release "jasper-software" "jasper")
      ;;
    "tiff")
      package_version_latest=$(curl ${curl_options} 'https://download.osgeo.org/libtiff/' | sed -n 's,.*tiff-\([0-9][0-9.]*[0-9]\)\.tar\.gz.*,\1,p' | sort -V | tail -1)
      ;;
    "libwebp")
      package_version_latest=$(curl ${curl_options} 'https://storage.googleapis.com/downloads.webmproject.org/releases/webp/index.html' | sed -n 's,.*libwebp-\([0-9]\+\.[0-9]\+\.[0-9]\+\)\.tar.gz.*,\1,p' | tail -1)
      ;;
    "peparse")
      package_version_latest=$(latest_github_release "trailofbits" "pe-parse")
      ;;
    "glew")
      package_version_latest=$(latest_github_release "nigels-com" "glew" | sed 's/^glew\-//g')
      ;;
    "libprojectm")
      package_version_latest=$(latest_github_release "projectM-visualizer" "projectm")
      ;;
    "pe_util")
      package_version_latest=$(latest_git_commit "https://github.com/gsauthof/pe-util.git")
      package_git=1
      ;;
    *)
      package_version_latest=
      error "No update rule for package: ${package}"
      return 1
      ;;
  esac

  if [ "${package_version_latest}" = "" ]; then
    error "Could not get latest version for ${package}."
    return 1
  fi

  # The version is used in sed, git and gh commands, so don't allow anything else than a plain version or commit.
  if ! [[ "${package_version_latest}" =~ ^[0-9A-Za-z][0-9A-Za-z._+-]*$ ]]; then
    error "Invalid latest version for ${package}: ${package_version_latest}"
    return 1
  fi

  if ! [ "${package_year}" = "" ] && ! [[ "${package_year}" =~ ^[0-9]{4}$ ]]; then
    error "Invalid release year for ${package}: ${package_year}"
    return 1
  fi

  if [ "${package_git}" = "1" ]; then
    package_version_highest="${package_version_latest}"
  else
    package_version_highest=$(echo "${package_version_current} ${package_version_latest}" | tr ' ' '\n' | sort -V | tail -1)
  fi

  if [ "${package_version_highest}" = "" ]; then
    error "Could not get highest version for ${package}."
    return 1
  fi

  if [ "${package_version_highest}" = "${package_version_current}" ]; then
    status "${package_name}: ${package_version_current} is the latest"
  else
    branch="${package_name}_$(echo ${package_version_latest} | sed 's/\./_/g')"
    # Check all pull requests first, closed ones too, so an update that was closed on purpose isn't pushed or opened again.
    pr_count=$(gh pr list --repo "${repo}" --head "${branch}" --state all --json number --jq 'length')
    if [ $? -ne 0 ] || [ "${pr_count}" = "" ]; then
      error "Could not list pull requests for ${branch}."
      return 1
    fi
    if [ "${pr_count}" = "0" ]; then
      # Check the remote, a fresh clone in GitHub Actions doesn't have the local branches from earlier runs.
      # The branch can exist without a pull request if creating the pull request failed in an earlier run.
      if ! git ls-remote --exit-code --heads origin "${branch}" >/dev/null 2>&1; then
        status "${package_name}: updating from ${package_version_current} to ${package_version_latest}..."
        push_update_branch || exit 1
      fi
      gh pr create --repo "${repo}" --head "${branch}" --base "master" --title "Update ${package_name} to ${package_version_latest}" --body "Update ${package_name} from ${package_version_current} to ${package_version_latest}" || exit 1
    else
      # An open update pull request conflicts when master changed the same line, for example when an update to an earlier version was merged.
      # Recreate the branch from master so it can still be merged.
      pr_mergeable=$(gh pr list --repo "${repo}" --head "${branch}" --state open --json mergeable --jq '.[0].mergeable // ""')
      if [ "${pr_mergeable}" = "CONFLICTING" ]; then
        # Only recreate branches with just the generated commit, so commits added by hand aren't lost.
        git fetch origin "${branch}" >/dev/null 2>&1 || exit 1
        branch_head=$(git rev-parse "origin/${branch}") || exit 1
        if [ "$(git rev-list --count "origin/master..${branch_head}")" = "1" ] && [ "$(git log -1 --format=%s "${branch_head}")" = "Update ${package_name}" ] && [ "$(git diff --name-only "origin/master...${branch_head}")" = "${versions_file}" ]; then
          status "${package_name}: recreating ${branch} from master..."
          # Only overwrite the commit that was checked.
          push_update_branch "--force-with-lease=${branch}:${branch_head}" || exit 1
        else
          error "${branch} conflicts with master and has other changes, it needs to be resolved manually."
        fi
      fi
    fi
  fi

}

# Uses the variables from update_package.
function push_update_branch() {

  git checkout -B "${branch}" || return 1
  sed -i "s,^${package_variable}=.*,${package_variable}=${package_version_latest},g" "${versions_file}" || return 1
  if ! [ "${package_year}" = "" ]; then
    sed -i "s,^${package_year_variable}=.*,${package_year_variable}=${package_year},g" "${versions_file}" || return 1
  fi
  git commit -m "Update ${package_name}" "${versions_file}" || return 1
  git push "$@" origin "${branch}" || return 1
  git checkout . >/dev/null 2>&1 || return 1
  if ! [ "$(git branch | head -1 | cut -d ' ' -f2)" = "master" ]; then
    git checkout master >/dev/null 2>&1 || return 1
  fi

}

cmds="dirname cat head tail cut sort tr grep sed curl jq git gh"
cmds_missing=
for cmd in ${cmds}; do
  which "${cmd}" >/dev/null 2>&1
  if [ $? -eq 0 ] ; then
    continue
  fi
  if [ "${cmds_missing}" = "" ]; then
    cmds_missing="${cmd}"
  else
    cmds_missing="${cmds_missing}, ${cmd}"
  fi
done

if ! [ "${cmds_missing}" = "" ]; then
  error "Missing ${cmds_missing} commands."
  exit 1
fi

dir="$(dirname "$0")"

if [ "${dir}" = "" ]; then
  error "Could not get current directory."
  exit 1
fi

if ! [ -d "${dir}" ]; then
  error "Missing ${dir}"
  exit 1
fi

if ! [ -d "${dir}/../../.git" ]; then
  error "Missing ${dir}/../../.git"
  exit 1
fi

# Resolve to an absolute path, dirname of . is still . when run from the scripts directory.
repodir="$(cd "${dir}/../.." && pwd)"

if ! [ -d "${repodir}" ]; then
  error "Missing ${repodir}."
  exit 1
fi

cd "${repodir}"
if [ $? -ne 0 ]; then
  error "Could not change directory to ${repodir}."
  exit 1
fi

repo="${GITHUB_REPOSITORY}"
if [ "${repo}" = "" ]; then
  repo=$(git config --get remote.origin.url | sed 's,^https://github\.com/,,g' | sed 's,^git@github\.com:,,g' | sed 's/\.git$//g')
fi
if [ "${repo}" = "" ]; then
  error "Could not get repo name."
  exit 1
fi

gh auth status >/dev/null || exit 1
if [ $? -ne 0 ]; then
  error "Missing GitHub login."
  exit 1
fi

gh_username=$(gh api user --jq '.login' 2>/dev/null)
if [ "${gh_username}" = "" ] && [ -f ~/.config/gh/hosts.yml ]; then
  gh_username=$(sed -n 's,^[ ]*user: \(.*\)$,\1,p' ~/.config/gh/hosts.yml | head -1)
fi
if [ "${gh_username}" = "" ]; then
  error "Missing GitHub username."
  exit 1
fi

gh_token=$(gh auth token 2>/dev/null)
if [ "${gh_token}" = "" ]; then
  error "Missing GitHub token."
  exit 1
fi

update_repo
merge_prs

update_repo
update_packages
