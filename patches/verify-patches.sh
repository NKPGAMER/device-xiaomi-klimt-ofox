#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
AUTO_TOP="$(cd -- "${SCRIPT_DIR}/../../../.." && pwd -P)"
FOX_TOP="${1:-${ORANGEFOX_TOP:-${AUTO_TOP}}}"

if [[ ! -d "${FOX_TOP}" ]]; then
    echo "ERROR: FOX_14_1_DIR not found: ${FOX_TOP}" >&2
    exit 1
fi
FOX_TOP="$(cd -- "${FOX_TOP}" && pwd -P)"

echo "==> Checking patch SHA256SUMS"
(cd "${SCRIPT_DIR}" && sha256sum -c "${SCRIPT_DIR}/SHA256SUMS")

python3 - "${SCRIPT_DIR}" "${FOX_TOP}" <<'PY'
import os, subprocess, sys, tempfile

script_dir, fox_top = sys.argv[1:3]
reused = os.path.join(script_dir, "reused")
new = os.path.join(script_dir, "new")

PLAN = [
    ("bootable/recovery", os.path.join(fox_top, "bootable/recovery"), "1d941746141f319e931c7b291fbb0f789f6f5a55", [
        os.path.join(reused, "bootable-recovery/rodin-complete.patch"),
        os.path.join(reused, "bootable-recovery/0008-recovery-reliably-reflash-OrangeFox-after-AB-ROM.patch"),
        os.path.join(new, "bootable-recovery/0009-klimt-thp-haptics-drm-fastbootd-unmap-usb.patch"),
        os.path.join(new, "bootable-recovery/0010-klimt-fix-res-get-pixel-format-rgba.patch"),
        os.path.join(new, "bootable-recovery/0011-klimt-settings-flush-and-vendor-boot-reflash.patch"),
    ], ["updater/include/updater/legacy_compat.h", "updater/legacy_compat.cpp"]),
    ("build/make", os.path.join(fox_top, "build/make"), "506df226dd003a364916b6b3ee1eb3bf9064f97f", [
        os.path.join(reused, "build-make/rodin-complete.patch"),
        os.path.join(new, "build-make/0002-klimt-align-makefile-prepare-order.patch"),
    ], []),
    ("hardware/interfaces", os.path.join(fox_top, "hardware/interfaces"), "a155fffda456a650c3b89c5d13092172446782a8", [
        os.path.join(reused, "hardware-interfaces/rodin-fastbootd-bootcontrol-nonblocking.patch"),
    ], []),
    ("system/core", os.path.join(fox_top, "system/core"), "e0d64d1f938a62371189d65663bf59708538ee7d", [
        os.path.join(reused, "system-core/0001-fs_mgr-fix-virtual-ab-image-cleanup-in-recovery.patch"),
        os.path.join(reused, "system-core/0002-fs_mgr-support-file-backed-virtual-ab-cows-in-recovery.patch"),
        os.path.join(reused, "system-core/rodin-fastbootd-optional-hals-nonblocking.patch"),
        os.path.join(new, "system-core/0004-fs_mgr-liblp-grow-block-devices-to-live-size.patch"),
    ], []),
    ("system/libhidl", os.path.join(fox_top, "system/libhidl"), "ec0019a962dee742a63d3d276ba511af6b12c62f", [
        os.path.join(new, "system-libhidl/0001-libhidl-guard-null-servicemanager-in-getAllHalInstanceNames.patch"),
    ], []),
    ("system/security", os.path.join(fox_top, "system/security"), "f231a6d15a637b8599e283cc12be4f4da02be531", [
        os.path.join(new, "system-security/0001-keystore2-filter-upgrade-params-to-app-id-data.patch"),
    ], []),
    ("system/update_engine", os.path.join(fox_top, "system/update_engine"), "14f6fac900fb4b242be7bb68ff778e0d97c33829", [
        os.path.join(reused, "system-update-engine/0001-update-engine-fix-rodin-ab-recovery-installation.patch"),
        os.path.join(new, "system-update-engine/0002-update-engine-grow-super-to-live-size-in-recovery.patch"),
    ], []),
    ("system/vold", os.path.join(fox_top, "system/vold"), "b865130d263a84d86440f6b8b9e1f08c6938d6a5", [
        os.path.join(reused, "system-vold/0001-vold-restore-orangefox-decryption-support.patch"),
        os.path.join(new, "system-vold/0002-vold-coloros17-a17-fbe-weaver-keystore2-bridge.patch"),
    ], []),
    ("vendor/twrp", os.path.join(fox_top, "vendor/twrp"), "c699fc6adfdeea786fd63626d8232a0f63dcc039", [
        os.path.join(reused, "vendor-twrp/0001-twrp-fix-rodin-orangefox-build-configuration.patch"),
        os.path.join(new, "vendor-twrp/0002-twrp-add-tw-no-haptics-soong-flag.patch"),
    ], []),
]

def run(cmd, cwd):
    return subprocess.run(cmd, cwd=cwd, text=True, capture_output=True, check=True)

print("\n==> Verifying 100% git diff & git status parity against clean HEAD + patches")
failed = False
for name, live_repo, expected_head_prefix, patches, untracked in PLAN:
    head = run(["git", "rev-parse", "HEAD"], cwd=live_repo).stdout.strip()
    head_ok = head.startswith(expected_head_prefix)
    with tempfile.TemporaryDirectory() as tmp:
        p1 = subprocess.Popen(["git", "archive", "HEAD"], cwd=live_repo, stdout=subprocess.PIPE)
        subprocess.run(["tar", "-x", "-C", tmp], stdin=p1.stdout, check=True)
        p1.wait()
        run(["git", "init", "-q"], cwd=tmp)
        run(["git", "add", "-A"], cwd=tmp)
        run(["git", "commit", "-q", "-m", "HEAD"], cwd=tmp)
        for pf in patches:
            run(["git", "apply", "--whitespace=nowarn", pf], cwd=tmp)

        live_diff = run(["git", "diff", "--full-index"], cwd=live_repo).stdout
        tmp_diff = run(["git", "diff", "--full-index"], cwd=tmp).stdout
        diff_ok = (live_diff == tmp_diff)

        live_status = sorted(
            line for line in run(["git", "status", "--porcelain"], cwd=live_repo).stdout.splitlines()
            if not any(ig in line for ig in [".work/", "__pycache__/"])
        )
        tmp_status = sorted(run(["git", "status", "--porcelain"], cwd=tmp).stdout.splitlines())
        status_ok = (live_status == tmp_status)

        untracked_ok = True
        for uf in untracked:
            if open(os.path.join(live_repo, uf), "rb").read() != open(os.path.join(tmp, uf), "rb").read():
                untracked_ok = False

    ok = head_ok and diff_ok and status_ok and untracked_ok
    if not ok:
        failed = True
    print(f"  [{'PASS' if ok else 'FAIL'}] {name:24s} head={head[:10]} (ok={head_ok}) diff={diff_ok} status={status_ok} untracked={untracked_ok}")
    if not head_ok:
        print(f"         expected={expected_head_prefix}, got={head}")

if failed:
    sys.exit(1)
print("\nALL 9 ORANGEFOX REPOS PASSED 100% VERIFICATION.")
PY
