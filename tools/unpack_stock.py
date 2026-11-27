#!/usr/bin/env python3
import argparse
import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent
DEVICE_TREE = ROOT.parent
DEFAULT_TWRP_SOURCE = ROOT.parents[3]
PREBUILT = ROOT / "prebuilt"
WORK = ROOT / ".work"
IMAGE_NAMES = ("vendor_boot.img",)


def extract_cpio(
    fragment: Path, destination: Path, name: str, twrp_source: Path
) -> None:
    lz4 = twrp_source / "out/host/linux-x86/bin/lz4"
    cpio = destination.parent / f"{name}.cpio"
    destination.mkdir()
    with cpio.open("xb") as stream:
        subprocess.run([str(lz4), "-dc", str(fragment)], check=True, stdout=stream)
    with cpio.open("rb") as stream:
        subprocess.run(
            ["cpio", "--no-absolute-filenames", "-idm", "--quiet"],
            cwd=destination,
            check=True,
            stdin=stream,
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "input_dir", nargs="?", type=Path, default=DEVICE_TREE / "local-inputs"
    )
    parser.add_argument(
        "--twrp-source", type=Path, default=DEFAULT_TWRP_SOURCE
    )
    args = parser.parse_args()
    input_dir = args.input_dir.resolve()
    twrp_source = args.twrp_source.resolve()

    missing = [name for name in IMAGE_NAMES if not (input_dir / name).is_file()]
    if missing:
        raise SystemExit(
            f"missing firmware images in {input_dir}:\n  " + "\n  ".join(missing)
        )
    if WORK.exists():
        raise SystemExit(f"refusing to overwrite existing work directory: {WORK}")

    unpacker = twrp_source / "system/tools/mkbootimg/unpack_bootimg.py"
    lz4 = twrp_source / "out/host/linux-x86/bin/lz4"
    for tool in (unpacker, lz4):
        if not tool.is_file():
            raise SystemExit(f"missing build tool: {tool}")

    required_prebuilt = (
        "vendor/lib64/android.hardware.secure_element-V1-ndk.so",
        "vendor/lib64/android.se.omapi-V1-ndk.so",
        "vendor_dlkm/lib/modules/scp.ko",
        "vendor_dlkm/lib/modules/si_haptic.ko",
        "vendor_dlkm/lib/modules/xiaomi_touch_dali.ko",
        "vendor_dlkm/lib/modules/goodix_core_dali.ko",
    )
    absent = [path for path in required_prebuilt if not (PREBUILT / path).is_file()]
    if absent:
        raise SystemExit(
            f"prebuilt directory is incomplete ({PREBUILT}):\n  " + "\n  ".join(absent)
        )

    images = WORK / "images"
    boot = WORK / "vendor_boot"
    unpacked = boot / "unpacked"
    images.mkdir(parents=True)
    unpacked.mkdir(parents=True)

    for name in IMAGE_NAMES:
        (images / name).symlink_to(input_dir / name)
    subprocess.run(
        ["python3", str(unpacker), "--boot_img", str(images / "vendor_boot.img"), "--out", str(unpacked)],
        check=True,
    )
    for fragment in ("vendor_ramdisk00", "vendor_ramdisk01", "dtb"):
        if not (unpacked / fragment).is_file():
            raise SystemExit(f"vendor_boot is missing {fragment}")
    extract_cpio(
        unpacked / "vendor_ramdisk00", boot / "platform", "platform", twrp_source
    )
    extract_cpio(
        unpacked / "vendor_ramdisk01", boot / "recovery", "recovery", twrp_source
    )

    (WORK / "state.json").write_text(
        json.dumps(
            {
                "input_dir": str(input_dir),
                "images": list(IMAGE_NAMES),
                "prebuilt_dir": str(PREBUILT),
            },
            indent=2,
        )
        + "\n"
    )
    print(f"firmware prepared: {WORK}")


if __name__ == "__main__":
    main()
