#!/bin/bash

set -e

ramdisk="$1"
phase="$2"
terminfo="$ramdisk/system/etc/terminfo"

if [ "$phase" != "--first-call" ]; then
    exit 0
fi

# relink_libraries is a phony Make target and may leave an older library in
# recovery/root after libminuitwrp is rebuilt. Refresh it immediately before
# OrangeFox packs the recovery fragment.
product_out="$(dirname "$(dirname "$ramdisk")")"
minuitwrp_src="$product_out/system/lib64/libminuitwrp.so"
minuitwrp_dst="$ramdisk/system/lib64/libminuitwrp.so"
if [ -f "$minuitwrp_src" ]; then
    echo "-- Refreshing recovery libminuitwrp.so from the current build output"
    cp -fp "$minuitwrp_src" "$minuitwrp_dst"
fi

# Mini debug sections are not used on-device and are already compressed data,
# so LZ4 cannot reduce them further.
top="${ANDROID_BUILD_TOP:-$(cd "$(dirname "$0")/../../.." && pwd)}"
objcopy_bin="$(find -L "$top/prebuilts/clang/host/linux-x86" -type f -name llvm-objcopy 2>/dev/null | sort -V | tail -n 1)"
readelf_bin="$(find -L "$top/prebuilts/clang/host/linux-x86" -type f -name llvm-readelf 2>/dev/null | sort -V | tail -n 1)"
strip_bin="$(find -L "$top/prebuilts/clang/host/linux-x86" -type f -name llvm-strip 2>/dev/null | sort -V | tail -n 1)"

if [ -x "$objcopy_bin" ] && [ -x "$readelf_bin" ]; then
    while IFS= read -r -d '' binary; do
        if file "$binary" | grep -q ELF && \
                "$readelf_bin" -SW "$binary" 2>/dev/null | grep -q '\.gnu_debugdata'; then
            "$objcopy_bin" --remove-section=.gnu_debugdata "$binary" || true
        fi
    done < <(find "$ramdisk/system" -type f -print0)
fi

# Trim terminfo to common terminals to save ramdisk space.
if [ -d "$terminfo" ]; then
    keep_dir=$(mktemp -d)
    trap 'rm -rf "$keep_dir"' EXIT

    for entry in a/ansi l/linux v/vt100 x/xterm x/xterm-256color; do
        if [ -f "$terminfo/$entry" ]; then
            mkdir -p "$keep_dir/$(dirname "$entry")"
            cp -p "$terminfo/$entry" "$keep_dir/$entry"
        fi
    done

    rm -rf "$terminfo"
    mv "$keep_dir" "$terminfo"
    trap - EXIT
fi

# Safe ELF slimming pass (preserve dynamic tables/symbols/entry points;
# do NOT UPX-pack here so klimt_twrp_repack can inspect ELF NEEDED deps).
if [ -x "$strip_bin" ] && [ -x "$readelf_bin" ]; then
    backup_dir="$(mktemp -d)"

    find \
        "$ramdisk/system/bin" \
        "$ramdisk/system/lib64" \
        -type f -print0 2>/dev/null |
    while IFS= read -r -d '' file; do
        relative="${file#"$ramdisk"/}"

        case "$relative" in
            system/bin/init|\
            system/bin/linker64|\
            system/bin/recovery|\
            system/bin/twrp|\
            system/bin/adbd|\
            system/bin/fastbootd|\
            system/bin/magiskboot)
                continue
                ;;
        esac

        "$readelf_bin" -h "$file" >/dev/null 2>&1 || continue

        backup="$backup_dir/$(printf '%s' "$relative" | sha256sum | awk '{print $1}')"
        cp -a "$file" "$backup" || continue

        before="$(
            {
                "$readelf_bin" -d --wide "$file" 2>/dev/null
                "$readelf_bin" --dyn-syms --wide "$file" 2>/dev/null
                "$readelf_bin" -h "$file" 2>/dev/null | grep -E 'Class:|Machine:|Entry point address:'
            } | sha256sum | awk '{print $1}'
        )"

        if ! "$strip_bin" --strip-unneeded "$file" >/dev/null 2>&1; then
            cp -a "$backup" "$file"
            continue
        fi

        after="$(
            {
                "$readelf_bin" -d --wide "$file" 2>/dev/null
                "$readelf_bin" --dyn-syms --wide "$file" 2>/dev/null
                "$readelf_bin" -h "$file" 2>/dev/null | grep -E 'Class:|Machine:|Entry point address:'
            } | sha256sum | awk '{print $1}'
        )"

        if [ "$before" != "$after" ]; then
            cp -a "$backup" "$file"
        fi
    done

    rm -rf "$backup_dir"
    echo "-- Klimt safe ELF slimming pass completed"
fi
