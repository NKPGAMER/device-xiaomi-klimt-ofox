#!/usr/bin/env bash
set -euo pipefail

TOOLS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DEVICE_TREE="$(cd -- "${TOOLS_DIR}/.." && pwd -P)"
FOX_TOP="$(cd -- "${TOOLS_DIR}/../../../.." && pwd -P)"

LUNCH_TARGET="${LUNCH_TARGET:-twrp_klimt-ap2a-eng}"
BUILD_TARGET="${BUILD_TARGET:-vendorbootimage}"
SECURITY_PATCH="${SECURITY_PATCH:-$(date +%Y-%m-01)}"
SKIP_BUILD=0
CLEAN_WORK=0

usage() {
    cat <<'EOF'
Usage: build.sh [OPTIONS]

Automatically load OrangeFox environment, build recovery/vendor_boot,
unpack stock vendor_boot.img (if needed), and repack the final image.

Options:
  --security-patch YYYY-MM-DD   Security patch date for prop.default (default: current YYYY-MM-01)
  --lunch TARGET                Lunch target (default: twrp_klimt-ap2a-eng)
  --skip-build                  Skip OrangeFox mka build and only run unpack/repack
  --clean-work                  Remove tools/.work before unpacking vendor_boot.img
  -h, --help                    Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --security-patch)
            SECURITY_PATCH="$2"
            shift 2
            ;;
        --lunch)
            LUNCH_TARGET="$2"
            shift 2
            ;;
        --skip-build)
            SKIP_BUILD=1
            shift
            ;;
        --clean-work)
            CLEAN_WORK=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: Unexpected argument: $1" >&2
            exit 1
            ;;
    esac
done

if [[ ! -f "${FOX_TOP}/build/envsetup.sh" ]]; then
    echo "ERROR: OrangeFox source not found at ${FOX_TOP}" >&2
    exit 1
fi

if [[ ! -f "${DEVICE_TREE}/local-inputs/vendor_boot.img" ]]; then
    echo "ERROR: Missing stock vendor_boot.img at ${DEVICE_TREE}/local-inputs/vendor_boot.img" >&2
    exit 1
fi

if [[ "${SKIP_BUILD}" -eq 0 ]]; then
    echo "==> Building OrangeFox (${LUNCH_TARGET} -> ${BUILD_TARGET}) in ${FOX_TOP}"
    pushd "${FOX_TOP}" >/dev/null
    set +u
    # shellcheck disable=SC1091
    source build/envsetup.sh
    lunch "${LUNCH_TARGET}"
    mka "${BUILD_TARGET}"
    set -u
    popd >/dev/null
fi

if [[ "${CLEAN_WORK}" -eq 1 ]] && [[ -d "${TOOLS_DIR}/.work" ]]; then
    echo "==> Cleaning ${TOOLS_DIR}/.work"
    rm -rf "${TOOLS_DIR}/.work"
fi

if [[ ! -f "${TOOLS_DIR}/.work/state.json" ]]; then
    echo "==> Unpacking stock vendor_boot.img from ${DEVICE_TREE}/local-inputs"
    python3 "${TOOLS_DIR}/unpack_stock.py"
fi

echo "==> Repacking OrangeFox vendor_boot.img (security patch: ${SECURITY_PATCH})"
python3 "${TOOLS_DIR}/repack_twrp.py" --security-patch "${SECURITY_PATCH}"
