<h2 align="center">OrangeFox Device Tree for Xiaomi 15T Pro (klimt)</h2>

## 📱 Device Specifications

<table align="center">
  <tr>
    <th align="center">Item</th>
    <th align="center">Details</th>
  </tr>
  <tr>
    <td align="center"><b>Chipset</b></td>
    <td align="center">Mediatek Dimensity 9400+</td>
  </tr>
  <tr>
    <td align="center"><b>GPU</b></td>
    <td align="center">Immortalis-G925 MC12</td>
  </tr>
  <tr>
    <td align="center"><b>Memory</b></td>
    <td align="center">12GB LPDDR5X</td>
  </tr>
  <tr>
    <td align="center"><b>Shipped Android Version</b></td>
    <td align="center">Android 15 (API 35)</td>
  </tr>
  <tr>
    <td align="center"><b>Storage</b></td>
    <td align="center">256 GB / 512 GB / 1 TB (UFS 4.1)</td>
  </tr>
  <tr>
    <td align="center"><b>Battery</b></td>
    <td align="center">Li-Po 5500 mAh, non-removable</td>
  </tr>
  <tr>
    <td align="center"><b>Display</b></td>
    <td align="center">1280 × 2772 px, 6.83", 60/120/144 Hz</td>
  </tr>
</table>

<p align="center">
  <img src="https://i02.appmifile.com/684_operator_sg/27/08/2025/4a7b9b4d497d851b4cc9050d718b6f85.png" alt="Xiaomi 15T Pro" width="600"/>
</p>

## ✨ Features
- ✅ ADB
- ✅ FBE Decryption (Android 17)
- ✅ Fastbootd (Non touch)
- ✅ Flashing
- ✅ MTP
- ✅ Sideload
- ✅ USB OTG
- ✅ Vibrator

## ⚡ Tested
**HyperOS 3.0.335**
> Android 17 | Global | Full Features

**HyperOS 4.0.6.0**
> Android 17 | EU | Full Features

**ColorOS 17.0.1 (Port)**
> Android 17 | China | Full Features

## 🛠️ Build Recovery

The repository will use OrangeFox 14.1 as the source. The example directory name is `ofox-14.1`

### 1. Sync the source

```sh
# Create a location to store OrangeFox source
cd /path/to/storage
mkdir ofox-sync
# Initialize the repository and sync
cd ofox-sync
git clone https://gitlab.com/OrangeFox/sync.git # (or, using ssh, "git clone git@gitlab.com:OrangeFox/sync.git")
cd sync
./orangefox_sync.sh -b 14.1 -p /path/to/ofox-sync/ofox-14.1
```

### 2. Clone the device tree

```sh
cd /path/to/ofox-sync/ofox-14.1
git clone https://github.com/NKPGAMER/device-xiaomi-klimt-ofox.git -b main device/xiaomi/klimt
```

### 3. Apply and verify patches

`apply-patches.sh` applies the required `fox_14.1` patch stack (`bootable/recovery`, `build/make`, `hardware/interfaces`, `system/core`, `system/libhidl`, `system/security`, `system/update_engine`, `system/vold`, `vendor/twrp`), and `verify-patches.sh` verifies SHA-256 checksums and 100% git parity.

```sh
cd /path/to/ofox-sync/ofox-14.1
./device/xiaomi/klimt/patches/apply-patches.sh
./device/xiaomi/klimt/patches/verify-patches.sh
```

> [!NOTE]
> Both scripts auto-detect the OrangeFox root when run inside `ofox-14.1`. You can also pass the path explicitly (`./apply-patches.sh /path/to/ofox-14.1`) or set `ORANGEFOX_TOP`.

### 4. Provide stock `vendor_boot.img`

Place your stock `vendor_boot.img` at `device/xiaomi/klimt/local-inputs/vendor_boot.img`:

```sh
mkdir -p device/xiaomi/klimt/local-inputs
cp /path/to/stock/vendor_boot.img device/xiaomi/klimt/local-inputs/vendor_boot.img
```

### 5. Build & Repack

> [!TIP]
> `vendorsetup.sh` enables low-memory defaults (`OF_LOW_MEMORY_BUILD=1`, `OF_BUILD_JOBS=4`, `GOMEMLIMIT=6GiB`, `_JAVA_OPTIONS=-Xmx1g`). To disable them on high-RAM machines, run `export OF_LOW_MEMORY_BUILD=0` before building.

#### Option A: Auto Build (Recommended)

`tools/build.sh` runs `envsetup.sh`, `lunch`, `mka vendorbootimage`, `tools/unpack_stock.py` (when `tools/.work/state.json` is absent), and `tools/repack_twrp.py` automatically:

```sh
cd /path/to/ofox-sync/ofox-14.1
./device/xiaomi/klimt/tools/build.sh
```

Available options for `tools/build.sh`:

| Option | Description |
| :--- | :--- |
| `--security-patch YYYY-MM-DD` | Set `ro.build.version.security_patch` in `prop.default` (default: current `YYYY-MM-01`) |
| `--lunch TARGET` | Lunch target (default: `twrp_klimt-ap2a-eng`, also supports `twrp_klimt-eng`) |
| `--skip-build` | Skip `mka vendorbootimage` and only run unpack/repack |
| `--clean-work` | Remove `tools/.work` before unpacking `local-inputs/vendor_boot.img` |
| `-h`, `--help` | Show usage help |

Examples:

```sh
# Auto build with explicit security patch date
./device/xiaomi/klimt/tools/build.sh --security-patch 2026-11-01

# Re-unpack stock vendor_boot.img and repack without rebuilding OrangeFox
./device/xiaomi/klimt/tools/build.sh --skip-build --clean-work
```

#### Option B: Manual Build

1. **Set up environment and build `vendorbootimage`:**

   ```sh
   cd /path/to/ofox-sync/ofox-14.1
   source build/envsetup.sh
   lunch twrp_klimt-ap2a-eng
   mka vendorbootimage
   ```

2. **Unpack stock `vendor_boot.img`:**

   Only needed on the first run, or after removing `tools/.work` when switching `local-inputs/vendor_boot.img`.

   ```sh
   # Remove previous work directory if re-unpacking:
   # rm -rf device/xiaomi/klimt/tools/.work
   python3 device/xiaomi/klimt/tools/unpack_stock.py
   ```

3. **Repack the final OrangeFox `vendor_boot.img`:**

   ```sh
   python3 device/xiaomi/klimt/tools/repack_twrp.py --security-patch "$(date +%Y-%m-01)"
   ```

### 6. Output & Flashing

The final image and repack reports are generated in `device/xiaomi/klimt/tools/output/<YYYYMMDD-HHMMSS>/`:
- `klimt-<YYYYMMDD>-vendor_boot.img`
- `repack-report.json`
- `size-budget.json`

Flash the generated `vendor_boot` image from bootloader mode:

```sh
adb reboot bootloader
fastboot flash vendor_boot device/xiaomi/klimt/tools/output/<YYYYMMDD-HHMMSS>/klimt-<YYYYMMDD>-vendor_boot.img
fastboot reboot recovery
```
