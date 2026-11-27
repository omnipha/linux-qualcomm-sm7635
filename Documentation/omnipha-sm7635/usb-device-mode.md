# Mainline USB Device Mode Preparation for Qualcomm SM7635 / Milos

Host-side verification, dependency trace, build configuration, and initramfs
handoff specifications for USB device-mode bring-up on Qualcomm SM7635
(Milos), focusing initially on Nothing Phone (3a) Pro (A059P, `asteroids`) while
preserving platform multi-device support.

This document describes **host preparation and verification only**.
It does **not** claim on-device USB enumeration, working SSH, or a successful
device boot. No device flashing, booting, or rebooting was performed.

---

## 1. Early-Boot Dependency Chain Analysis

### 1.1 Hardware and Core Subsystems
The SM7635 platform USB subsystem relies on the following components:
1. **Clocks and Resets (`drivers/clk/qcom/gcc-sm7635.c`, `CONFIG_SM_GCC_7635` & `CONFIG_QCOM_CLK_RPMH`):**
   - Core / NOC clocks: `GCC_CFG_NOC_USB3_PRIM_AXI_CLK`, `GCC_USB30_PRIM_MASTER_CLK`, `GCC_AGGRE_USB3_PRIM_AXI_CLK`, `GCC_USB30_PRIM_SLEEP_CLK`, `GCC_USB30_PRIM_MOCK_UTMI_CLK`, and `RPMH_CXO_CLK`.
   - Core reset: `GCC_USB30_PRIM_BCR`.
   - PHY reset: `GCC_QUSB2PHY_PRIM_BCR`.
2. **Power Domains & OPP (`CONFIG_QCOM_RPMHPD`):**
   - Power domain: `USB30_PRIM_GDSC` (in GCC).
   - OPP: `rpmhpd_opp_nom`.
3. **Regulators (`CONFIG_REGULATOR_QCOM_RPMH` over SPMI):**
   - SoC High-Speed PHY (`usb_1_hsphy`): `vdd-supply` from `vreg_l2b` (0.88–0.92 V) and `vdda12-supply` from `vreg_l4b` (1.2 V).
   - PMIV0104 eUSB2 repeater (`pmiv0104_eusb2_repeater`): `vdd18-supply` from `vreg_l7b` (1.8 V) and `vdd3-supply` from `vreg_l17b` (3.0 V).
4. **Interconnects (`CONFIG_INTERCONNECT_QCOM_SM7635`):**
   - Paths `aggre1_noc MASTER_USB3_0` -> `mc_virt SLAVE_EBI1` (`usb-ddr`) and `gem_noc MASTER_APPSS_PROC` -> `cnoc_cfg SLAVE_USB3_0` (`apps-usb`).

### 1.2 PHY & Repeater Architecture
SM7635 utilizes an embedded USB 2.0 (eUSB2) architecture consisting of two stages:
1. **SoC eUSB2 PHY:**
   - Node: `usb_1_hsphy: phy@88e3000` (`compatible = "qcom,milos-snps-eusb2-phy", "qcom,sm8550-snps-eusb2-phy"`).
   - Driver: `drivers/phy/phy-snps-eusb2.c` (`CONFIG_PHY_SNPS_EUSB2`).
   - Translates internal digital UTMI controller signaling to low-voltage eUSB2 signals.
2. **PMIC eUSB2 Repeater:**
   - Node: `pmiv0104_eusb2_repeater: repeater` (`compatible = "qcom,pmiv0104-eusb2-repeater"` under SPMI bus PMIV0104).
   - Driver: `drivers/phy/qualcomm/phy-qcom-eusb2-repeater.c` (`CONFIG_PHY_QCOM_EUSB2_REPEATER`).
   - References board tuning properties: `qcom,tune-res-fsdif`, `qcom,tune-usb2-amplitude`, `qcom,tune-usb2-disc-thres`, `qcom,tune-usb2-preem`.
   - Converts low-voltage eUSB2 signaling to standard USB 2.0 High-Speed 3.3 V differential signaling (D+/D-) on the physical connector.
   - Referenced by `usb_1_hsphy` through `phys = <&pmiv0104_eusb2_repeater>;`.

### 1.3 Controller Layer (DWC3 & Qualcomm Glue)
- Node: `usb_1: usb@a600000` (`compatible = "qcom,milos-dwc3", "qcom,snps-dwc3"`).
- Glue driver: `drivers/usb/dwc3/dwc3-qcom.c` (`CONFIG_USB_DWC3_QCOM`).
- Core driver: `drivers/usb/dwc3/core.c` (`CONFIG_USB_DWC3`).
- Quirk: `qcom,select-utmi-as-pipe-clk;` configures UTMI clock as pipe clock because hardware does not support USB 3.x SuperSpeed (no SuperSpeed QMP PHY is wired).

### 1.4 Role Selection & Remote Processor (PMIC-GLINK / UCSI / ADSP) Interaction
The board device tree includes a PMIC-GLINK Type-C node (`pmic-glink`) with a child `usb-c-connector` whose endpoint `pmic_glink_hs_in` links to `usb_1_dwc3_hs`:
1. **Dynamic Type-C / UCSI Path:**
   - `pmic_glink` platform driver (`drivers/soc/qcom/pmic_glink.c`, `CONFIG_QCOM_PMIC_GLINK`) creates auxiliary device `ucsi`.
   - `ucsi_glink` auxiliary driver (`drivers/usb/typec/ucsi/ucsi_glink.c`, `CONFIG_UCSI_PMIC_GLINK`) communicates with Qualcomm UCSI firmware running on the Audio DSP (ADSP).
   - The RPMSG link (`qcom_pmic_glink_rpmsg`) relies on rpmsg channel `PMIC_RTR_ADSP_APPS`, exposed over GLINK IPC only after `remoteproc_adsp` (`drivers/remoteproc/qcom_q6v5_pas.c`, `CONFIG_QCOM_Q6V5_PAS`) loads vendor firmware (`adsp.mbn` and `adsp_dtb.mbn`) via PAS TrustZone calls.
   - When operational, UCSI receives connector status notifications from the ADSP and drives `usb_role_switch_set_role(con->usb_role_sw, role)`.
2. **Headless / Firmware-Independent Fallback in Device Mode:**
   - In `drivers/usb/dwc3/drd.c`:
     When `usb-role-switch` is present and no `role-switch-default-mode` is declared in DT, DWC3 defaults to `USB_DR_MODE_PERIPHERAL` and invokes `dwc3_set_mode(dwc, DWC3_GCTL_PRTCAP_DEVICE)`. The UDC controller `a600000.usb` is registered.
   - In `drivers/usb/dwc3/dwc3-qcom.c`:
     When userspace/initramfs binds the gadget UDC via ConfigFS (`echo a600000.usb > UDC`), `dwc3_gadget_run_stop(dwc, 1)` calls `dwc3_pre_run_stop(dwc, true)`.
     The Qualcomm glue callback `dwc3_qcom_run_stop_notifier` asserts `dwc3_qcom_vbus_override_enable(qcom, true)`, writing `UTMI_OTG_VBUS_VALID | SW_SESSVLD_SEL` into `QSCRATCH_HS_PHY_CTRL` and `LANE0_PWR_PRESENT` into `QSCRATCH_SS_PHY_CTRL`.
     This asserts internal VBUS session valid signals to the DWC3 controller without requiring external VBUS hardware sensing or ADSP UCSI firmware interaction.

### 1.5 Unresolved Assumptions & Evidence Status
- **Type-C CC Pull-Down (Rd):**
  USB device mode requires the device to present 5.1 kΩ pull-down resistors (Rd) on the Type-C CC pins to instruct the host to supply 5 V VBUS and enumerate. In hardware, Qualcomm PMICs (PM7550/PMK8550) maintain hardware default / dead-battery Rd pull-downs even before Linux boots. The device also successfully communicates over fastboot/ABL prior to kernel launch. However, dynamic CC orientation detection (flipping the cable) and role switching (host/OTG) in Linux depend on ADSP firmware and UCSI.
- **ADSP Firmware Availability:**
  The board device tree references proprietary firmware blobs (`qcom/milos/nothing/asteroids/adsp.mbn`). These blobs are not part of the mainline repository and must not be committed. Headless USB device mode preparation avoids hard dependence on ADSP firmware for initial boot networking.
- **Pro Inherited Wiring:**
  `milos-nothing-asteroids-pro.dts` inherits the Phone (3a) USB, repeater, and PMIC configuration. Physical rail measurements and hardware verification on the Pro remain open points for the first-boot issue.

---

## 2. Configuration Strategy: Built-in vs. Modular

### 2.1 Analysis
In upstream `defconfig`:
- Built in (`=y`): `CONFIG_USB_DWC3=y`, `CONFIG_USB_DWC3_QCOM=y`, `CONFIG_USB_DWC3_DUAL_ROLE=y`, `CONFIG_USB_GADGET=y`, `CONFIG_USB_ROLE_SWITCH=y`, `CONFIG_BLK_DEV_INITRD=y`, `CONFIG_NET=y`.
- Modular (`=m`): `CONFIG_PHY_SNPS_EUSB2=m`, `CONFIG_PHY_QCOM_EUSB2_REPEATER=m`, `CONFIG_USB_CONFIGFS=m` (and its sub-options `CONFIG_USB_F_ECM=m`, `CONFIG_USB_F_NCM=m`, `CONFIG_USB_U_ETHER=m`, `CONFIG_USB_LIBCOMPOSITE=m`).

If the modular configuration were used for the first-stage ramdisk:
- The initramfs would need to bundle 6–8 exact-version `.ko` files matching the kernel release (`7.3.0-gb81b95d869a9`).
- Modules would need manual `insmod` sequencing:
  `phy-qcom-eusb2-repeater.ko` -> `phy-snps-eusb2.ko` -> `libcomposite.ko` -> `u_ether.ko` -> `usb_f_ecm.ko` / `usb_f_ncm.ko`.
- Any recompilation of `Image` during bring-up would invalidate the initramfs modules due to vermagic mismatches.

### 2.2 Built-in Fragment Decision
A versioned configuration fragment (`arch/arm64/configs/omnipha_usb_gadget.config`) is added.
It promotes the complete USB device-mode networking stack to built-in (`=y`).

**Benefits:**
1. **Decoupled initramfs:** A single minimal initramfs containing only standard userspace tools (`busybox`, `dropbear`, and a gadget setup script) works across arbitrary kernel test builds without carrying `.ko` files.
2. **Immediate hardware readiness:** The PHY, repeater, controller, and ConfigFS functions are fully registered before `/init` runs; no module loading delays or deferred probe race conditions.
3. **Preserves upstream `defconfig`:** The upstream `defconfig` remains unmodified for general multi-device use and can be merged cleanly via standard Kconfig targets (`make defconfig omnipha_usb_gadget.config`).

---

## 3. Configuration Fragment Contents

File: `arch/arm64/configs/omnipha_usb_gadget.config`

```ini
# SPDX-License-Identifier: GPL-2.0-only
CONFIG_USB_DWC3=y
CONFIG_USB_DWC3_DUAL_ROLE=y
CONFIG_USB_DWC3_QCOM=y
CONFIG_USB_ROLE_SWITCH=y

CONFIG_PHY_SNPS_EUSB2=y
CONFIG_PHY_QCOM_EUSB2_REPEATER=y

CONFIG_USB_LIBCOMPOSITE=y
CONFIG_USB_CONFIGFS=y
CONFIG_USB_CONFIGFS_SERIAL=y
CONFIG_USB_CONFIGFS_ACM=y
CONFIG_USB_CONFIGFS_NCM=y
CONFIG_USB_CONFIGFS_ECM=y
CONFIG_USB_CONFIGFS_ECM_SUBSET=y

CONFIG_USB_U_SERIAL=y
CONFIG_USB_U_ETHER=y
CONFIG_USB_F_SERIAL=y
CONFIG_USB_F_ACM=y
CONFIG_USB_F_NCM=y
CONFIG_USB_F_ECM=y
CONFIG_USB_F_ECM_SUBSET=y
```

---

## 4. Build and Verification Evidence

### 4.1 Environment and Toolchain
- **Host:** Linux x86_64
- **Date:** 2026-11-27
- **Base commit:** `b81b95d869a91bee549de24ced9ffa6863c219d2`
- **Compiler:** `aarch64-linux-gnu-gcc` (Ubuntu 15.2.0-16ubuntu1) 15.2.0
- **Make:** GNU Make 4.4.1
- **DTC:** 1.7.2
- **dtschema:** 2026.9 (isolated virtual environment)
- **Kernel release:** `7.3.0-gb81b95d869a9`

### 4.2 Configuration Resolution
```sh
make O=out ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- defconfig omnipha_usb_gadget.config
make O=out ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig
```
Command output confirmed:
- `CONFIG_USB_LIBCOMPOSITE`: `m` -> `y`
- `CONFIG_USB_CONFIGFS`: `m` -> `y`
- `CONFIG_USB_F_ECM`: `m` -> `y`
- `CONFIG_USB_F_NCM`: `m` -> `y`
- `CONFIG_USB_U_ETHER`: `m` -> `y`
- `CONFIG_PHY_SNPS_EUSB2`: `m` -> `y`
- `CONFIG_PHY_QCOM_EUSB2_REPEATER`: `m` -> `y`
`olddefconfig` verified that no requested options were silently dropped or modified.

### 4.3 Build Commands & Artifact Hashes
```sh
make -j8 O=out ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
    Image qcom/milos-nothing-asteroids.dtb qcom/milos-nothing-asteroids-pro.dtb \
    qcom/milos-fairphone-fp6.dtb
```

Artifacts generated (baseline `b81b95d869a91bee549de24ced9ffa6863c219d2` with config fragment applied):

| Artifact | SHA-256 | Notes |
|---|---|---|
| `out/arch/arm64/boot/Image` (`7.3.0-gb81b95d869a9`) | `91ea47c02b219d135e134293e7583613b132c695e649550de1e7f2802dd7216b` | Built-in eUSB2 PHY, repeater, ConfigFS, CDC ECM/NCM |
| `out/arch/arm64/boot/Image` (`7.3.0-g7801124399bf`) | `292e4f4e5600c3bc14681a506f3f3d8dee83f2aa8a20d3e055eb99ab88f551bd` | Built on top of branch commits |
| `out/arch/arm64/boot/dts/qcom/milos-nothing-asteroids.dtb` | `020f9b7be25af001958febc0ba15efc87e4c86c25553e3c47f8aa1120304ad4a` | Identical to baseline hash (unmodified) |
| `out/arch/arm64/boot/dts/qcom/milos-nothing-asteroids-pro.dtb` | `25ee4f8dd5789bc679d009712bba0e14d06ac1b8df65131e8d35219b24663228` | Identical to baseline hash (unmodified) |
| `out/arch/arm64/boot/dts/qcom/milos-fairphone-fp6.dtb` | `c3908fe06eeb9e236923b9081639d7f7d18bb10d42848077750b2397c8f5ad6a` | Identical to baseline hash (unmodified) |
| `out/.config` | `c29e93559faa37a7ec9baf38650c21531c4e53dd29d7b67846e336740bca6d1c` | Resolved defconfig + omnipha_usb_gadget fragment |

The bit-for-bit identical hashes for the three DTBs demonstrate that existing device-tree configurations were not altered.

### 4.4 Device-Tree Schema and Binding Validation
```sh
make -j8 O=out ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CHECK_DTBS=1 \
    qcom/milos-nothing-asteroids.dtb qcom/milos-nothing-asteroids-pro.dtb \
    qcom/milos-fairphone-fp6.dtb

dt-validate -m -u Documentation/devicetree/bindings \
    -p out/Documentation/devicetree/bindings/processed-schema.json \
    out/arch/arm64/boot/dts/qcom/milos-nothing-asteroids.dtb \
    out/arch/arm64/boot/dts/qcom/milos-nothing-asteroids-pro.dtb \
    out/arch/arm64/boot/dts/qcom/milos-fairphone-fp6.dtb

make -j8 O=out ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
    DT_SCHEMA_FILES=arm/qcom.yaml dt_binding_check
```
All schema checks completed with exit status 0 and zero schema diagnostics or warnings.

---

## 5. Initramfs Handoff Interface Specification

For the separate boot-image creation and first-boot issues, the kernel expects the following userspace handoff interface inside the initramfs:

1. **Mount ConfigFS:**
   ```sh
   mount -t configfs none /sys/kernel/config
   ```
2. **Gadget Creation (`/sys/kernel/config/usb_gadget/g1`):**
   ```sh
   mkdir -p /sys/kernel/config/usb_gadget/g1
   cd /sys/kernel/config/usb_gadget/g1
   echo 0x1d6b > idVendor   # Linux Foundation
   echo 0x0104 > idProduct  # Multifunction Composite Gadget
   mkdir -p strings/0x409
   echo "0123456789" > strings/0x409/serialnumber
   echo "Omnipha" > strings/0x409/manufacturer
   echo "SM7635 Bringup Gadget" > strings/0x409/product
   ```
3. **Function Instantiation (CDC ECM and/or CDC NCM):**
   ```sh
   mkdir -p functions/ecm.usb0
   mkdir -p functions/ncm.usb0
   mkdir -p configs/c.1/strings/0x409
   echo "CDC Network" > configs/c.1/strings/0x409/configuration
   ln -s functions/ecm.usb0 configs/c.1/
   # Or functions/ncm.usb0 depending on host OS preference
   ```
4. **UDC Controller Binding:**
   ```sh
   UDC_NAME=$(ls /sys/class/udc | head -n 1) # Resolves to a600000.usb
   echo "${UDC_NAME}" > UDC
   ```
   Binding triggers `dwc3_gadget_run_stop`, enabling QSCRATCH VBUS override in `dwc3-qcom`.
5. **Network Interface Setup & SSH:**
   ```sh
   ip addr add 192.168.10.2/24 dev usb0
   ip link set usb0 up
   /usr/sbin/dropbear -E -R -p 192.168.10.2:22
   ```

---

## 6. Acceptance Checklist
- [x] Baseline and config reproducibly resolved from clean checkout; `olddefconfig` did not silently drop options.
- [x] Kernel `Image` and DTBs built successfully; release `7.3.0-gb81b95d869a9`, SHA-256 hashes recorded.
- [x] DT schema check and binding check clean without warnings; existing DTB hashes unchanged.
- [x] Dependency analysis complete; initramfs handoff and live-device testing requirements documented.
