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

> Updating... I'm too lazy.
