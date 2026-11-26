#!/system/bin/sh
# ============================================================================
# touch_init.sh — on-device, PC-free bring-up of the Xiaomi THP touch HAL
#                 inside TWRP for klimt (Xiaomi 15T Pro, Goodix GT9916).
#                 Baked into the recovery ramdisk at /thp/ and launched by
#                 init.recovery.project.rc (recovery-only).
#
# This implements the THP userspace stack: mounts stock partitions, starts
# servicemanager with sm_stab3.so shim, then runs the touch HAL with
# touch_shim.so so it can compute finger coordinates from raw capacitance
# frames and inject them via /dev/input.
# ============================================================================
THP=/thp
LOG=/tmp/touch_init.log
exec >>"$LOG" 2>&1
echo "=== touch_init start ==="

if [ "$(getprop ro.twrp.fastbootd)" = "1" ] || [ "$(getprop sys.orangefox.fastbootd)" = "1" ]; then
    echo "fastbootd mode: skipping THP mounts"
    exit 0
fi

SLOT="$(getprop ro.boot.slot_suffix)"
[ -z "$SLOT" ] && SLOT=_a
ODM=/dev/block/mapper/odm$SLOT
VENDOR=/dev/block/mapper/vendor$SLOT
SYSTEM=/dev/block/mapper/system$SLOT
echo "slot=$SLOT"

# Wait for the dynamic-partition mapper nodes (TWRP sets these up) and the touch
# IC char node (created when goodix_core_dali loads via modules.load.recovery).
i=0
while [ $i -lt 500 ]; do
    [ -e "$SYSTEM" ] && [ -e "$VENDOR" ] && [ -e "$ODM" ] && break
    sleep 0.2; i=$((i+1))
done
i=0
while [ ! -e /dev/xiaomi-touch ] && [ $i -lt 500 ]; do sleep 0.2; i=$((i+1)); done
echo "mapper+IC ready (xiaomi-touch: $([ -e /dev/xiaomi-touch ] && echo yes || echo NO))"

# Mount the stock partitions. odm goes to the REAL /odm path (the HAL hardcodes
# /odm/bin, /odm/lib64, /odm/firmware, /odm/etc); system/vendor are reached via
# LD_LIBRARY_PATH only (do NOT overmount TWRP's live /vendor).
if [ "$(getprop ro.twrp.fastbootd)" = "1" ] || [ "$(getprop sys.orangefox.fastbootd)" = "1" ]; then
    echo "fastbootd mode detected before mount: skipping THP mounts"
    exit 0
fi
mkdir -p /mnt_sys /mnt_vendor /odm
mountpoint -q /mnt_sys    || mount -t erofs -o ro "$SYSTEM" /mnt_sys    || echo "WARN mount system"
mountpoint -q /mnt_vendor || mount -t erofs -o ro "$VENDOR" /mnt_vendor || echo "WARN mount vendor"
mountpoint -q /odm        || mount -t erofs -o ro "$ODM" /odm           || echo "WARN mount odm"

# APEX linker symlink -> TWRP's REAL linker64 (NOT /mnt_sys's, which loops back
# into /apex => ELOOP). Mandatory for the stock binaries to exec.
mkdir -p /apex/com.android.runtime/bin /system/bin/bootstrap /apex/com.android.vintf/etc/vintf
ln -sf /system/bin/linker64 /apex/com.android.runtime/bin/linker64
ln -sf /system/bin/linker64 /system/bin/bootstrap/linker64
cp /mnt_vendor/etc/vintf/manifest.xml /apex/com.android.vintf/etc/vintf/ 2>/dev/null

# binder context for our servicemanager.
mountpoint -q /dev/binderfs || { mkdir -p /dev/binderfs; mount -t binder binder /dev/binderfs; }
[ -e /dev/binder ] || ln -sf /dev/binderfs/binder /dev/binder

# System libs FIRST so the system libbinder_ndk resolves against the system
# libbinder (get_trace_enabled_tags); then vendor-only libs; then odm.
LLP=/mnt_sys/system/lib64:/mnt_vendor/lib64:/odm/lib64

# Keep recovery's own /system/bin/servicemanager running: it serves KeyMint,
# Keystore2, Weaver, SE, and touchfeature across both HyperOS (A15/A16) and
# ColorOS 17 (whose /mnt_sys servicemanager aborts under sm_stab3 libbinder).
[ -z "$(pidof servicemanager)" ] && setprop ctl.start servicemanager
i=0
while [ $i -lt 75 ]; do
    [ "$(getprop servicemanager.ready)" = "true" ] && [ -n "$(pidof servicemanager)" ] && break
    sleep 0.2; i=$((i+1))
done
echo "SM ready: $(getprop servicemanager.ready) pid=$(pidof servicemanager) (waited ${i}x0.2s)"

# Sync ROM security patch & OS properties before starting KeyMint / Keystore2
# so metadata & synthetic_password unwrap matches both ColorOS 17 and HyperOS.
if [ -r /mnt_sys/system/build.prop ]; then
    SYS_PATCH=$(sed -n 's/^ro\.build\.version\.security_patch=//p' /mnt_sys/system/build.prop | head -n 1)
    VND_PATCH=$(sed -n 's/^ro\.vendor\.build\.security_patch=//p' /mnt_vendor/build.prop | head -n 1)
    SYS_REL=$(sed -n 's/^ro\.build\.version\.release=//p' /mnt_sys/system/build.prop | head -n 1)
    SYS_SDK=$(sed -n 's/^ro\.build\.version\.sdk=//p' /mnt_sys/system/build.prop | head -n 1)
    SYS_BRAND=$(sed -n 's/^ro\.product\.system\.brand=//p' /mnt_sys/system/build.prop | head -n 1)
    [ -n "$SYS_PATCH" ] && resetprop ro.build.version.security_patch "$SYS_PATCH"
    if [ "$SYS_BRAND" = "oplus" ] || grep -q '^ro\.oplus\.' /mnt_sys/system/build.prop 2>/dev/null; then
        [ -n "$SYS_PATCH" ] && resetprop ro.vendor.build.security_patch "$SYS_PATCH"
    elif [ -n "$VND_PATCH" ]; then
        resetprop ro.vendor.build.security_patch "$VND_PATCH"
    fi
    [ -n "$SYS_REL" ] && resetprop ro.build.version.release "$SYS_REL"
    [ -n "$SYS_SDK" ] && resetprop ro.build.version.sdk "$SYS_SDK"
    echo "ROM sync: brand=$SYS_BRAND rel=$SYS_REL sdk=$SYS_SDK sys_patch=$SYS_PATCH vnd_patch=$(getprop ro.vendor.build.security_patch)"
fi

setprop klimt.sm.ready 1
setprop sys.boot_completed 1

# the THP touch HAL under touch_shim (NULL-stubs the absent aux HALs).
# EXEC it (do NOT background + exit): this replaces the shell, so the init
# service's main process BECOMES the HAL and stays alive. If the script merely
# backgrounded it and then exited, init would tear down the whole service
# process group (oneshot/stop semantics) — killing both the HAL and the
# backgrounded servicemanager, leaving no touch (exactly the failure we hit).
# servicemanager keeps running as a child of this exec'd process.
kill -9 $(pidof vendor.xiaomi.hw.touchfeature-service) 2>/dev/null
echo "=== touch_init: exec HAL (keeps the service alive) ==="
exec env LD_PRELOAD=$THP/touch_shim.so LD_LIBRARY_PATH=$LLP \
    /odm/bin/hw/vendor.xiaomi.hw.touchfeature-service >>/tmp/touch.log 2>&1
