DEVICE_PATH := device/xiaomi/klimt

$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit_only.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/base.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/ramdisk_stub.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/virtual_ab_ota.mk)
$(call inherit-product, vendor/twrp/config/common.mk)

PRODUCT_SHIPPING_API_LEVEL := 34
PRODUCT_TARGET_VNDK_VERSION := 34

AB_OTA_UPDATER := true
ENABLE_VIRTUAL_AB := true
PRODUCT_USE_DYNAMIC_PARTITIONS := true
PRODUCT_USE_VIRTUAL_AB := true
PRODUCT_VIRTUAL_AB_OTA := true
PRODUCT_VIRTUAL_AB_COMPRESSION := true

PRODUCT_PROPERTY_OVERRIDES += \
    ro.twrp.vendor_boot=true \
    ro.virtual_ab.enabled=true \
    ro.virtual_ab.userspace.snapshots.enabled=true \
    ro.virtual_ab.compression.enabled=true \
    ro.crypto.metadata_init_delete_all_keys.enabled=true \
    ro.crypto.volume.filenames_mode=aes-256-cts

PRODUCT_PACKAGES += \
    fastbootd \
    fsck.erofs \
    fsck.f2fs \
    klimt.recovery.logd.rc \
    init.recovery.mt6991.rc \
    init.recovery.project.rc \
    lpdump \
    lpunpack \
    make_f2fs \
    snapuserd \
    snapuserd_ramdisk \
    task_profiles.json \
    ueventd.klimt.recovery.rc

# Remove optional utilities inherited by TWRP common.mk for the size-gated first build.
PRODUCT_PACKAGES -= \
    bash \
    fsck.exfat \
    htop \
    lsof \
    mkfs.ntfs \
    mount.exfat \
    mount.ntfs \
    nano \
    openvpn \
    powertop \
    fsck.ntfs \
    vim

PRODUCT_SOONG_NAMESPACES += $(DEVICE_PATH)
