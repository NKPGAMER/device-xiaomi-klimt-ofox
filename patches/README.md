# OrangeFox 14.1 (`fox_14.1`) Patch Stack cho Xiaomi 15T Pro (`klimt`)

Thư mục này chứa toàn bộ các bản vá (patch) cần thiết để build OrangeFox Recovery 14.1 cho **Xiaomi 15T Pro (`klimt`)**, hỗ trợ giải mã FBE (Android 17 / HyperOS / ColorOS 17), Virtual A/B, fastbootd, cảm ứng/haptics và tự động reflash OrangeFox.

## Cách sử dụng

Từ thư mục gốc của mã nguồn `fox_14.1`:

```sh
# Áp dụng toàn bộ patch (tự kiểm tra SHA-256 trước khi apply)
./device/xiaomi/klimt/patches/apply-patches.sh

# Kiểm tra lại checksum và độ khớp 100% git diff/status
./device/xiaomi/klimt/patches/verify-patches.sh
```

> Nếu chạy ngoài cây thư mục `fox_14.1`, truyền đường dẫn trực tiếp: `./apply-patches.sh /path/to/ofox-14.1` hoặc đặt biến môi trường `ORANGEFOX_TOP`.

---

## Các file quản lý trong `patches/`

| File | Công dụng |
| :--- | :--- |
| `apply-patches.sh` | Kiểm tra SHA-256 và áp dụng tuần tự toàn bộ patch trong `reused/` và `new/` lên cây mã nguồn `fox_14.1` (tự nhận diện nếu đã apply sẵn). |
| `verify-patches.sh` | Đối chiếu SHA-256 qua `SHA256SUMS`, kiểm tra `HEAD` commit của 9 repo mục tiêu và xác minh 100% parity của `git diff` / `git status`. |
| `SHA256SUMS` | Danh sách mã băm SHA-256 của toàn bộ 19 file `.patch` để đảm bảo tính toàn vẹn trước khi apply. |

---

## 1. Reused Patches (`patches/reused/`)

Các bản vá kế thừa từ nền tảng `OrangeFox-rodin-source` (MediaTek / Virtual A/B):

### `bootable/recovery`
- **`reused/bootable-recovery/rodin-complete.patch`**
  - Nền tảng tùy biến OrangeFox cho thiết bị MediaTek hiện đại: sửa `applypatch`, cập nhật `etc/init.rc`, chỉnh sửa giao diện/font (`gui/`, `minuitwrp/truetype`), xử lý sự kiện cảm ứng/đồ họa (`minuitwrp/events.cpp`, `graphics.cpp`), và bổ sung hỗ trợ DTB/cấu hình recovery.
- **`reused/bootable-recovery/0008-recovery-reliably-reflash-OrangeFox-after-AB-ROM.patch`**
  - Sửa `orangefox.cpp` để luôn kích hoạt `Flash_Current_Twrp()` ổn định sau khi flash ROM A/B (khi bật tùy chọn tự động reflash), báo lỗi rõ ràng nếu reflash thất bại và tránh bỏ sót trạng thái recovery bị ghi đè.

### `build/make`
- **`reused/build-make/rodin-complete.patch`**
  - Tích hợp hook `Fox_After_Recovery_Image` vào `core/Makefile` cho target `vendor_boot`, cùng các điều chỉnh trong `core/config.mk` và `envsetup.sh` để hệ thống build OrangeFox đóng gói đúng recovery trong `vendor_boot`.

### `hardware/interfaces`
- **`reused/hardware-interfaces/rodin-fastbootd-bootcontrol-nonblocking.patch`**
  - Bổ sung `BootControlClient::TryGetService()` (non-blocking) trong `boot/aidl/client/` để `fastbootd` không bị treo khi BootControl AIDL/HIDL HAL chưa sẵn sàng hoặc không tồn tại.

### `system/core`
- **`reused/system-core/0001-fs_mgr-fix-virtual-ab-image-cleanup-in-recovery.patch`**
  - Bổ sung `DisableAllImages()` cho `libfiemap` và sửa `libsnapshot` nhằm dọn dẹp/vô hiệu hóa các Virtual A/B image sạch sẽ trong môi trường recovery.
- **`reused/system-core/0002-fs_mgr-support-file-backed-virtual-ab-cows-in-recovery.patch`**
  - Khi recovery mount `/data` trực tiếp trên block device vật lý (không qua dm layer), ánh xạ file-backed Virtual A/B COW qua loop device trong `ImageManager::MapImageDevice()` để tránh lỗi kernel `-EBUSY` của `dm-linear`.
- **`reused/system-core/rodin-fastbootd-optional-hals-nonblocking.patch`**
  - Chuyển việc lấy các HAL tùy chọn (`IHealth`, `IFastboot`) trong `fastbootd` sang dạng không chặn (`AServiceManager_checkService` / `tryGetService`) để `fastbootd` khởi động nhanh và không treo.

### `system/update_engine`
- **`reused/system-update-engine/0001-update-engine-fix-rodin-ab-recovery-installation.patch`**
  - Cho phép ghi đè kích thước `AllocatableSpace()` của phân vùng `super` thông qua property `ro.dynamic.full_size` trong `DynamicPartitionControlAndroid::CheckSuperPartitionAllocatableSpace()` khi flash OTA/ROM A/B.

### `system/vold`
- **`reused/system-vold/0001-vold-restore-orangefox-decryption-support.patch`**
  - Khôi phục và bổ sung hỗ trợ giải mã FBE của OrangeFox trong `vold` (`Decrypt.cpp`, `KeystoreInfo.cpp`, `Weaver1.*`, `Android.bp` thêm `android.hardware.weaver-V2-ndk`).

### `vendor/twrp`
- **`reused/vendor-twrp/0001-twrp-fix-rodin-orangefox-build-configuration.patch`**
  - Include `bootable/recovery/orangefox_soong.mk` trong `config/BoardConfigSoong.mk` để các biến/cờ build Soong của OrangeFox hoạt động đúng.

---

## 2. New Patches (`patches/new/`)

Các bản vá viết mới dành riêng cho **Xiaomi 15T Pro (`klimt`)** / **Android 17**:

### `bootable/recovery`
- **`new/bootable-recovery/0009-klimt-thp-haptics-drm-fastbootd-unmap-usb.patch`**
  - Tổng hợp các sửa đổi cốt lõi cho `klimt`:
    - Thêm cờ `TW_KEEP_VENDOR_MOUNTED` và `TW_KEEP_ODM_MOUNTED` trong `Android.mk` & `partitionmanager.cpp`.
    - Đồng bộ chuyển đổi USB config (`WaitForProperty("sys.usb.state", "none", 2s)`) trong `gui/action.cpp` để tránh lỗi chuyển chế độ ADB/Fastboot.
    - Sửa xử lý rung/haptics và input events (`minuitwrp/events.cpp`), `graphics_drm.cpp`, `scrolllist.cpp`, `settings.xml`.
    - Hỗ trợ unmap super devices và xử lý `fastbootd` / `startupArgs.cpp` / `twrp.cpp`.
- **`new/bootable-recovery/0010-klimt-fix-res-get-pixel-format-rgba.patch`**
  - Đổi giá trị trả về mặc định của `res_get_pixel_format()` trong `minuitwrp/resources.cpp` từ `GGL_PIXEL_FORMAT_BGRA_8888` sang `GGL_PIXEL_FORMAT_RGBA_8888` để hiển thị đúng màu sắc trên màn hình `klimt`.
- **`new/bootable-recovery/0011-klimt-settings-flush-and-vendor-boot-reflash.patch`**
  - Tự động `DataManager::Flush()` khi đổi múi giờ hoặc chuyển rời các trang cài đặt (`settings`, `advanced`, `fox_lab`, `ext_*`) sau khi đã giải mã `/data` để không bị mất cấu hình.
  - Nhận diện phân vùng `/vendor_boot` là `Vendor Boot` có thể backup/flash trong `partition.cpp`, và hỗ trợ `twrpRepacker` repack/reflash `vendor_boot` ổn định.

### `build/make`
- **`new/build-make/0002-klimt-align-makefile-prepare-order.patch`**
  - Căn chỉnh lại thứ tự/định dạng tham số gọi `Fox_After_Recovery_Image` trong `core/Makefile` cho `INSTALLED_VENDOR_BOOTIMAGE_TARGET`.

### `system/core`
- **`new/system-core/0004-fs_mgr-liblp-grow-block-devices-to-live-size.patch`**
  - Thêm `MetadataBuilder::GrowBlockDevicesToLiveSize()` (kèm unit test) vào `fs_mgr/liblp` để mở rộng kích thước block device ghi trong metadata `super` lên bằng kích thước thực tế của phân vùng trên máy (không bao giờ thu nhỏ).

### `system/libhidl`
- **`new/system-libhidl/0001-libhidl-guard-null-servicemanager-in-getAllHalInstanceNames.patch`**
  - Kiểm tra null cho `defaultServiceManager1_2()` trong `getAllHalInstanceNames()` (`transport/ServiceManagement.cpp`) để tránh crash (SIGSEGV) trong recovery khi HIDL service manager không chạy.

### `system/security`
- **`new/system-security/0001-keystore2-filter-upgrade-params-to-app-id-data.patch`**
  - Lọc `upgrade_params` chỉ giữ lại `Tag::APPLICATION_ID` và `Tag::APPLICATION_DATA` khi gọi `km_dev.upgradeKey()` trong `keystore2/src/utils.rs`, khắc phục lỗi nâng cấp keyblob khi giải mã FBE trên Android 17 / KeyMint mới.

### `system/update_engine`
- **`new/system-update-engine/0002-update-engine-grow-super-to-live-size-in-recovery.patch`**
  - Gọi `builder->GrowBlockDevicesToLiveSize(PartitionOpener())` trong `LoadMetadataBuilder()` khi đang chạy ở chế độ recovery (`IsRecovery()`), giúp `update_engine` flash được payload ngay cả khi bảng `super` cũ trên máy ghi kích thước nhỏ hơn phân vùng `super` thực tế.

### `system/vold`
- **`new/system-vold/0002-vold-coloros17-a17-fbe-weaver-keystore2-bridge.patch`**
  - Hỗ trợ giải mã FBE cho **Android 17 / ColorOS 17**: sửa đọc kích thước & endianness của file `.weaver` (`Get_Weaver_Data`), sao chép an toàn `persistent.sqlite` vào `/tmp/misc/keystore/`, cập nhật cầu nối Keystore2/Weaver (`KeyStorage.cpp`, `Keystore.cpp`, `KeystoreInfo.cpp`, `Weaver1.cpp`).

### `vendor/twrp`
- **`new/vendor-twrp/0002-twrp-add-tw-no-haptics-soong-flag.patch`**
  - Thêm biến Soong `tw_no_haptics` (`TW_NO_HAPTICS` -> `-DTW_NO_HAPTICS`) vào `build/soong/Android.bp` và `config/BoardConfigSoong.mk` để bật/tắt haptics có điều kiện khi build.
