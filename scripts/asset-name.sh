#!/usr/bin/env bash
# Single source of truth for geode release asset naming.
#
#   geode-<version>-<family>-<arch>.<ext>
#
#   <version> = tag stripped of leading 'v' (e.g. "1.20.0")
#   <family>  = macos | windows | linux
#   <arch>    = x64 | arm64
#   <ext>     = zip | deb | rpm | tar.gz
#
# Consumed by: .github/workflows/create-release.yml and
#              .github/workflows/bump-homebrew-geode-formula.yml.
#
# Usage:
#   source scripts/asset-name.sh
#   collect_geode_assets <family> <arch> <version> <dest_dir>
#
# Expected examples:
#   geode-1.20.0-macos-arm64.tar.gz
#   geode-1.20.0-linux-x64.tar.gz
#   geode-1.20.0-linux-x64.deb
#   geode-1.20.0-linux-x64.rpm
#   geode-1.20.0-linux-arm64.tar.gz
#   geode-1.20.0-linux-arm64.deb
#   geode-1.20.0-linux-arm64.rpm
#   geode-1.20.0-windows-x64.zip
#   geode-1.20.0-windows-arm64.zip
#
# One more asset breaks the family/arch shape on purpose: the no-JRE jar bundle
# for Homebrew-core is pure JVM bytecode (no bundled runtime), so a single
# platform-independent artifact serves every OS:
#   geode-1.20.0-jvm.tar.gz
# It is packaged inline in create-release.yml (linux leg), not via the helper
# below, since it has no <family>/<arch> dimension.

set -euo pipefail

# Print the canonical asset filename for a given family/arch/version/extension.
# Usage: geode_asset_name <family> <arch> <version> <ext>
geode_asset_name() {
    local family="$1" arch="$2" version="$3" ext="$4"
    printf 'geode-%s-%s-%s.%s' "$version" "$family" "$arch" "$ext"
}

# Copy + rename geode relay build outputs into <dest_dir> using the canonical
# geode-<version>-<family>-<arch>.<ext> scheme.
#
# Expected inputs:
#   geode/build/geode-image/geode/  flat app-image built by :geode:geodeImage
#                                   (bin/geode + bin/geode.bat + lib/*.jar
#                                    + runtime/ + share/)
#   geode/build/jpackage/*.deb      from :geode:jpackageDeb (Linux only)
#   geode/build/jpackage/*.rpm      from :geode:jpackageRpm (Linux only)
#
# On Windows the flat image is packaged as .zip; every other OS uses tar.gz.
# Tool order for the zip: 7z, then zip, then a python3 zipfile fallback (Windows
# runners ship 7z; git-bash has no zip).
#
# Usage: collect_geode_assets <family> <arch> <version> <dest_dir>
collect_geode_assets() {
    local family="$1" arch="$2" version="$3" dest="$4"
    mkdir -p "$dest"
    local abs_dest
    abs_dest="$(cd "$dest" && pwd)"
    shopt -s nullglob

    # 1. Archive the flat app-image into geode-<version>-<family>-<arch>.<ext>.
    #    macOS runners produce only this one. Windows uses .zip; every other
    #    OS uses tar.gz.
    local app_image="geode/build/geode-image/geode"
    if [ -d "$app_image" ]; then
        if [ "$family" = "windows" ]; then
            local zipfile="$abs_dest/$(geode_asset_name "$family" "$arch" "$version" zip)"
            if command -v 7z >/dev/null 2>&1; then
                ( cd "$(dirname "$app_image")" && 7z a -tzip "$zipfile" "$(basename "$app_image")/" >/dev/null )
            elif command -v zip >/dev/null 2>&1; then
                ( cd "$(dirname "$app_image")" && zip -qr "$zipfile" "$(basename "$app_image")" )
            else
                python3 - "$app_image" "$zipfile" <<'PY'
import os, sys, zipfile
src, dst = sys.argv[1], sys.argv[2]
root = os.path.dirname(src)
base = os.path.basename(src)
with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as zf:
    for dirpath, _dirs, files in os.walk(src):
        for f in files:
            p = os.path.join(dirpath, f)
            zf.write(p, os.path.relpath(p, root))
PY
            fi
            echo "Collected: $zipfile"
        else
            local tarball="$abs_dest/$(geode_asset_name "$family" "$arch" "$version" tar.gz)"
            ( cd "$(dirname "$app_image")" && tar czf "$tarball" "$(basename "$app_image")" )
            echo "Collected: $tarball"
        fi
    fi

    # 2. Linux native installers (.deb, .rpm). jpackage writes them directly
    #    to geode/build/jpackage/ with its own naming, so we re-copy under the
    #    canonical scheme.
    local src base ext dst
    for src in \
        geode/build/jpackage/*.deb \
        geode/build/jpackage/*.rpm \
    ; do
        [ -f "$src" ] || continue
        base="$(basename "$src")"
        ext="${base##*.}"
        dst="$abs_dest/$(geode_asset_name "$family" "$arch" "$version" "$ext")"
        cp "$src" "$dst"
        echo "Collected: $dst"
    done
    shopt -u nullglob
}
