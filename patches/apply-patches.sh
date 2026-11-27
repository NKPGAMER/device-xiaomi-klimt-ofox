#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

FOX_TOP="${ORANGEFOX_TOP:-}"

usage() {
    cat <<'EOF'
Usage: apply-patches.sh [OPTIONS] [FOX_14_1_DIR]

Apply the exact reused (OrangeFox-rodin-source) and new (klimt / ColorOS 17)
patch stack onto a clean OrangeFox 14.1 tree so git status/diff matches 100%.

Options:
  -h, --help           Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        *)
            if [[ -z "${FOX_TOP}" ]]; then
                FOX_TOP="$1"
                shift
            else
                echo "ERROR: Unexpected argument: $1" >&2
                exit 1
            fi
            ;;
    esac
done

if [[ -z "${FOX_TOP}" ]]; then
    AUTO_TOP="$(cd -- "${SCRIPT_DIR}/../../../.." && pwd -P)"
    if [[ -f "${AUTO_TOP}/build/envsetup.sh" ]]; then
        FOX_TOP="${AUTO_TOP}"
    elif [[ -f "${PWD}/build/envsetup.sh" ]]; then
        FOX_TOP="${PWD}"
    else
        echo "ERROR: Specify FOX_14_1_DIR or set ORANGEFOX_TOP." >&2
        exit 1
    fi
fi

FOX_TOP="$(cd -- "${FOX_TOP}" && pwd -P)"

echo "==> Verifying patch SHA-256 checksums"
(cd "${SCRIPT_DIR}" && sha256sum -c "${SCRIPT_DIR}/SHA256SUMS")

apply_series() {
    local repo_dir="$1"
    local repo_label="$2"
    shift 2
    local patches=("$@")

    if ! git -C "${repo_dir}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "ERROR: ${repo_label} is not a git repo: ${repo_dir}" >&2
        exit 1
    fi

    # Check if the repo already matches HEAD + entire patch series (supports stacked patches).
    local match_status
    match_status=$(python3 - "${repo_dir}" "${patches[@]}" <<'PY'
import os, subprocess, sys, tempfile
repo = sys.argv[1]
patches = sys.argv[2:]
def run(cmd, cwd):
    return subprocess.run(cmd, cwd=cwd, text=True, capture_output=True, check=True)
live_status = run(["git", "status", "--porcelain"], cwd=repo).stdout.strip()
if not live_status:
    print("CLEAN")
    sys.exit(0)
with tempfile.TemporaryDirectory() as tmp:
    p1 = subprocess.Popen(["git", "archive", "HEAD"], cwd=repo, stdout=subprocess.PIPE)
    subprocess.run(["tar", "-x", "-C", tmp], stdin=p1.stdout, check=True)
    p1.wait()
    run(["git", "init", "-q"], cwd=tmp)
    run(["git", "add", "-A"], cwd=tmp)
    run(["git", "commit", "-q", "-m", "HEAD"], cwd=tmp)
    for pf in patches:
        run(["git", "apply", "--whitespace=nowarn", pf], cwd=tmp)
    live_diff = run(["git", "diff", "--full-index"], cwd=repo).stdout
    tmp_diff = run(["git", "diff", "--full-index"], cwd=tmp).stdout
    if live_diff != tmp_diff:
        print("DIRTY_MISMATCH")
        sys.exit(0)
    tmp_untracked = run(["git", "ls-files", "--others", "--exclude-standard"], cwd=tmp).stdout.splitlines()
    for uf in tmp_untracked:
        p_live = os.path.join(repo, uf)
        p_tmp = os.path.join(tmp, uf)
        if not os.path.isfile(p_live) or open(p_live, "rb").read() != open(p_tmp, "rb").read():
            print("DIRTY_MISMATCH")
            sys.exit(0)
print("ALREADY_APPLIED")
PY
)

    if [[ "${match_status}" == "ALREADY_APPLIED" ]]; then
        echo "[already applied] ${repo_label}"
        return 0
    elif [[ "${match_status}" == "DIRTY_MISMATCH" ]]; then
        echo "ERROR: ${repo_label} (${repo_dir}) has local modifications that differ from the patch stack." >&2
        exit 1
    fi

    local patch_file
    for patch_file in "${patches[@]}"; do
        echo "[apply]           ${repo_label} :: $(basename "${patch_file}")"
        git -C "${repo_dir}" apply --whitespace=nowarn --check "${patch_file}"
        git -C "${repo_dir}" apply --whitespace=nowarn "${patch_file}"
    done
}

echo
echo "==> Applying OrangeFox 14.1 (fox_14.1) patch stack under ${FOX_TOP}"

apply_series "${FOX_TOP}/bootable/recovery" "bootable/recovery" \
    "${SCRIPT_DIR}/reused/bootable-recovery/rodin-complete.patch" \
    "${SCRIPT_DIR}/reused/bootable-recovery/0008-recovery-reliably-reflash-OrangeFox-after-AB-ROM.patch" \
    "${SCRIPT_DIR}/new/bootable-recovery/0009-klimt-thp-haptics-drm-fastbootd-unmap-usb.patch" \
    "${SCRIPT_DIR}/new/bootable-recovery/0010-klimt-fix-res-get-pixel-format-rgba.patch" \
    "${SCRIPT_DIR}/new/bootable-recovery/0011-klimt-settings-flush-and-vendor-boot-reflash.patch"

apply_series "${FOX_TOP}/build/make" "build/make" \
    "${SCRIPT_DIR}/reused/build-make/rodin-complete.patch" \
    "${SCRIPT_DIR}/new/build-make/0002-klimt-align-makefile-prepare-order.patch"

apply_series "${FOX_TOP}/hardware/interfaces" "hardware/interfaces" \
    "${SCRIPT_DIR}/reused/hardware-interfaces/rodin-fastbootd-bootcontrol-nonblocking.patch"

apply_series "${FOX_TOP}/system/core" "system/core" \
    "${SCRIPT_DIR}/reused/system-core/0001-fs_mgr-fix-virtual-ab-image-cleanup-in-recovery.patch" \
    "${SCRIPT_DIR}/reused/system-core/0002-fs_mgr-support-file-backed-virtual-ab-cows-in-recovery.patch" \
    "${SCRIPT_DIR}/reused/system-core/rodin-fastbootd-optional-hals-nonblocking.patch" \
    "${SCRIPT_DIR}/new/system-core/0004-fs_mgr-liblp-grow-block-devices-to-live-size.patch"

apply_series "${FOX_TOP}/system/libhidl" "system/libhidl" \
    "${SCRIPT_DIR}/new/system-libhidl/0001-libhidl-guard-null-servicemanager-in-getAllHalInstanceNames.patch"

apply_series "${FOX_TOP}/system/security" "system/security" \
    "${SCRIPT_DIR}/new/system-security/0001-keystore2-filter-upgrade-params-to-app-id-data.patch"

apply_series "${FOX_TOP}/system/update_engine" "system/update_engine" \
    "${SCRIPT_DIR}/reused/system-update-engine/0001-update-engine-fix-rodin-ab-recovery-installation.patch" \
    "${SCRIPT_DIR}/new/system-update-engine/0002-update-engine-grow-super-to-live-size-in-recovery.patch"

apply_series "${FOX_TOP}/system/vold" "system/vold" \
    "${SCRIPT_DIR}/reused/system-vold/0001-vold-restore-orangefox-decryption-support.patch" \
    "${SCRIPT_DIR}/new/system-vold/0002-vold-coloros17-a17-fbe-weaver-keystore2-bridge.patch"

apply_series "${FOX_TOP}/vendor/twrp" "vendor/twrp" \
    "${SCRIPT_DIR}/reused/vendor-twrp/0001-twrp-fix-rodin-orangefox-build-configuration.patch" \
    "${SCRIPT_DIR}/new/vendor-twrp/0002-twrp-add-tw-no-haptics-soong-flag.patch"

echo
echo "Done. Run '${SCRIPT_DIR}/verify-patches.sh \"${FOX_TOP}\"' to verify 100% git match."
