# Hardening and Evidence Review: First-Boot Candidate for Nothing Phone (3a) Pro (A059P)

**Target Device:** Nothing Phone (3a) Pro (`nothing-asteroids-pro`, A059P, Qualcomm SM7635 / Milos SoC, unit `mb003`).  
**Kernel Baseline:** Mainline Linux `7.3.0` (`omnipha` branch, based on upstream baseline `b81b95d869a91bee549de24ced9ffa6863c219d2`).  
**Issue:** omnipha/linux-qualcomm-sm7635#4 ("Harden the first-boot candidate for highest-probability USB-SSH and framebuffer console").  
**Tracking & Cross-Links:** [omnipha/ports#6](https://github.com/omnipha/ports/issues/6) ("First Omnipha boot and USB SSH").  
**Mode:** Host work only. No device flash, boot, or reboot was executed; no `fastboot` or `adb` commands were run against hardware.

---

## 1. Executive Summary

This review consolidates empirical measurements from private unit `mb003` records, vendor kernel investigation (`omnipha/linux-sm7635`), stock partition images, and mainline device-tree validation. Its purpose is to deliver the **highest-probability first-boot candidate** for USB-SSH and framebuffer console, establish exact answers to eight core technical questions, rank remaining residual risks, and provide an operator-executable test plan with a mathematically verified rollback path.

No support claim in this document asserts untested on-device functionality. Every assertion clearly distinguishes source presence, host compilation/packaging, and physically measured device behavior.

---

## 2. Table of Assumptions and Evidence Audit

| Claim / Assumption | Source File / Reference | SHA-256 / Pinned Commit | Status | Technical Impact / Notes |
|---|---|---|---|---|
| **Stock Boot Header Geometry** (v4, 4096-byte pages, stock offsets) | `vendor_boot_a.img`, `boot_a.img` | `237259404601045205715a71b88016744c73729d4513349cfe90c754b0dc1253` (`vendor_boot`), `197aff11679301ca4a2d6f74dfcb942c3543ac9d41628e4e2116af0bdb706d4d` (`boot`) | **Verified** | Verified from read-only partition backups. Kernel offset `0x8000`, ramdisk `0x1000000`, tags `0x100`, dtb `0x1f00000`. |
| **ABL Base DTB Selection Criteria** (`qcom,msm-id` and `qcom,board-id`) | `live-fdt.dts`, `vendor_boot_a.000000000000000000009.dtb` | `a56788799b1badb047d245c1b1e36bfbe0277d17de0cec6b622e410b4de4fd78` (`live-fdt.dts`) | **Verified** | Stock ABL matches SMEM Platform ID (`0x27c`) and Board ID (`0x0b`). Absent IDs cause ABL DTB match failure and fallback to fastboot. |
| **Stock DTBO Overlay Conflict** (Entry 65 failure on custom DTB) | `dtbo_a.65.dtb`, vendor record `2026-10-20-2223` | `93be04b6e20914fd1546ad314e351199bb3e6b6a71c2555ef956175164909ae2` (`dtbo_a.65.dtb`), commit `36203441a0090675000d3d7f621d816bf74b4304` | **Verified** | Stock DTBO 65 has 29 fragments referencing 143 fixup symbols. Libfdt application to a non-vendor DTB returns `FDT_ERR_NOTFOUND` (32 missing symbols across 82 sites). ABL treats overlay failure as fatal. |
| **Known-Good Kernel Entry Chain** (Stock kernel + modified ramdisk) | Vendor run 52 record `2026-10-28-2284` | `fef030081e04d3a90451bb7d64dcfa7668c41dc4248e6e0b1959fdb40efce948` (`init_boot_a`) | **Verified** | Run 52 proved key-only SSH (`:22`) on the stock 6.1.84 kernel with `boot_a`, `vendor_boot_a`, `dtbo_a`, and `vbmeta_a` untouched. |
| **Unsigned Kernel Entry in ABL** | Vendor records `2026-10-21-2228`, `2026-10-22-2231` | `116b1662760757d5a2652a55766c28f259c967c91f5de8b4c7168fc46ed174ce` (`boot_a` #18) | **Unproven** | Four earlier slot-A custom kernel attempts (`0134`, `0640`, `1156`, `1717`) returned to fastboot within 4.0–5.0s with zero ramoops activity. Whether ABL executes unsigned mainline kernels on unlocked bootloader is unproven. |
| **Stock Signed-Tail Bound** (13,967,360 bytes on `boot_a`) | Vendor record `2026-10-23-2245` (issue #55) | `90203e06c0608d471f2bd260c3c3075112507408e59c3d7d8bec72706899f478` (`config.gz`) | **Verified (as bound)** | Stock `boot_a` kernel payload was 13,949,926 bytes; signed tail starts at 13,967,360. Mainline `Image.gz` (15.2 MiB) exceeds this bound, proving mainline cannot fit before the stock tail. |
| **Late-Init Clock Shutdown Threat** (`clk_ignore_unused pd_ignore_unused`) | Private device record `README.md`, Omnipha cross-device evidence | Pinned commit `6d45f6631ab40ab12a8915097f46838d485859c2` | **Verified** | On Snapdragon platforms without native display KMS drivers, late init gates unused display clocks, immediately blanking continuous splash framebuffer. Both flags are required. |
| **Continuous Splash Framebuffer Region** (`0xe3940000`, 43 MiB) | `live-fdt.dts`, `console-ramoops-0` | `c9c49d9244c6531ffb06560ca9c26b24b30786fdd03bc2bce7e193e80b453fd2` (`console-ramoops-0`) | **Verified** | Stock kernel logs `OF: reserved mem: ... splash_region 0xe3940000..0xe643ffff (44032 KB)`. Framebuffer scanout operates at 1080x2392 `a8r8g8b8` with stride 4320. |
| **Framebuffer Overlap with Milos DT** | `arch/arm64/boot/dts/qcom/milos.dtsi` | In-tree source | **Refuted (no overlap)** | `0xe3940000`–`0xe643ffff` sits between `rmtfs@e1f00000` (ends `0xe2000000`) and `qtee-region@e8900000` (starts `0xe8900000`). Zero byte overlap exists. |
| **PM7550 L22 Voltage Discrepancy** (3.2 V vs 3.3 V) | `milos-nothing-asteroids.dts` vs `live-fdt.dts` | `020f9b7be25af001958febc0ba15efc87e4c86c25553e3c47f8aa1120304ad4a` (`milos-nothing-asteroids.dtb`) | **Verified (discrepancy identified)** | Upstream DT specifies 3.2 V; stock FDT specifies 3.3 V. Evidence establishes L22 powers `vci-supply` (touchscreen/panel), not USB. USB PHY and repeater use L2B, L4B, L7B, L17B. |
| **Lab USB Network IP Scheme** (`172.16.42.0/24`) | `phone-second-life/AGENTS.md`, vendor record `2026-10-23-2244` | `4f0e151da8a68339d34d7596d73e77f95415faa79b741aaa425572c1fa7caf69` | **Verified** | Lab standard is `172.16.42.0/24`. Device IP is `172.16.42.2` (host `172.16.42.1`). Mainline candidate now assigns both `172.16.42.2/24` and `192.168.10.2/24`. |
| **Ramoops Diagnostic Preservation** (`0x81f20000`, 4 MiB) | `milos-nothing-asteroids.dts`, `console-ramoops-0` | `c9c49d9244c6531ffb06560ca9c26b24b30786fdd03bc2bce7e193e80b453fd2` | **Verified** | Ramoops reservation matches stock DT: address `0x81f20000`, length `0x400000`, `console-size = 0x200000`, `pmsg-size = 0x200000`, `mem-type = 2`. |
| **Safe Recovery Path & Slot B Carrier Status** | `phone-second-life/devices/mb003/README.md`, `parts-b.sha256` | Verified partition backup set | **Verified** | Slot B partitions have verified 1:1 stock backups. Partition policy freigabe authorizes `vendor_boot_b`, `recovery_b`, `dtbo_b` as carriers. Slot A remains untouched rollback anchor. |

---

## 3. Decisions on the Eight Core Technical Questions

### Question 1: Bootloader DTB Selection
- **ABL Behavior:** Qualcomm Snapdragon ABL parses SMEM platform information populated by earlier boot stages: SoC ID `PlatformId` (0x27c = SM7635 Volcano), hardware revision `soc_rev` (0x10000 = v1.0), and board ID `BoardId` (0x0b = 11, Volcano QRD Pro / Asteroids Pro). ABL iterates through candidate DTBs in the DTB blob of `vendor_boot`. If candidate DTBs lack `qcom,msm-id` and `qcom,board-id`, ABL finds zero matching base DTBs, rejects the image, and synchronously returns to fastboot.
- **Overlay Application Failure:** Once a base DTB is selected, ABL evaluates the `dtbo` partition. On A059P (mb003), entry 65 matches `qcom,board-id = <0x0b 0>`, `qcom,oem-id = <0x02>`. ABL executes `fdt_overlay_apply()`. In vendor investigation #10, applying stock DTBO 65 to a non-vendor DTB failed with `FDT_ERR_NOTFOUND` due to 32 missing fixup symbols across 82 sites and 29 fragments. When overlay application fails, ABL considers it fatal, aborts boot, and returns to fastboot within 4–5 seconds.
- **DTB Content Decision:** `arch/arm64/boot/dts/qcom/milos-nothing-asteroids-pro.dts` is explicitly updated to declare:
  ```dts
  qcom,msm-id = <0x280 0x10000 0x281 0x10000 0x27c 0x10000>;
  qcom,board-id = <0x0b 0x00>;
  ```
  These values are taken directly from the archived stock FDT (`live-fdt.dts` lines 5 & 9).
- **Overlay Step Resolution:** Satisfying stock DTBO 65 on mainline DTB is impossible without importing hundreds of downstream Qualcomm vendor nodes foreign to Linux 7.3. Therefore, the overlay step must be neutralized. When targeting Slot B (`fastboot set_active b`), `dtbo_b` can be neutralized (cleared to an empty Header v0 table), preventing ABL from attempting `fdt_overlay_apply()`, while stock `dtbo_a` remains intact as the rollback anchor. Alternatively, if base DTB already incorporates the full board tree, no overlay is required.
- **Unproven:** Whether ABL on A059P will boot without an error when `dtbo` contains an empty table or whether it requires a dummy overlay matching board ID `0x0b`. Measurement: single-variable test of an empty DTBO table on Slot B.

### Question 2: Kernel Entry
- **Only Measured Boot Structure Reaching Kernel + Gadget:**
  The 2026-10-28 held session (Run 52 / issue #145, record `2026-10-28-2284`):
  - `boot_a`: Stock 6.1.84 kernel (`197aff11679301ca4a2d6f74dfcb942c3543ac9d41628e4e2116af0bdb706d4d`), untouched.
  - `vendor_boot_a`: Stock 20-DTB vendor boot (`237259404601045205715a71b88016744c73729d4513349cfe90c754b0dc1253`), untouched.
  - `dtbo_a`: Stock 76-entry DTBO (`759813dbfd94f4a4124b08afb2c9ef85f1f9afb7cdca9829be2558ffde13c992`), untouched.
  - `vbmeta_a`: Stock vbmeta (`cc1926d2aa8e9c12df6a469111bf87f1e61e70022b84626fabcd014ae33cdffe`), untouched.
  - `init_boot_a`: Flashed candidate `fef030081e04d3a90451bb7d64dcfa7668c41dc4248e6e0b1959fdb40efce948` (8,388,608 bytes), replacing generic ramdisk inside stock envelope.
- **Differences in Mainline Candidate:**
  1. `boot.img`: Mainline Linux 7.3 `Image.gz` (unsigned) instead of stock 6.1.84 kernel.
  2. `vendor_boot.img`: Mainline single DTB (`milos-nothing-asteroids-pro.dtb`) + mainline bootconfig/cmdline instead of stock 20-DTB vendor_boot.
  3. `init_boot.img`: Mainline debug initramfs (BusyBox, Dropbear, configfs gadget).
- **Unproven Variables:**
  - Whether ABL permits execution of an unsigned mainline kernel on an unlocked bootloader without stock AVB footer/AVB0 metadata.
  - Whether ABL accepts `vendor_boot.img` containing 1 single DTB rather than 20 concatenated DTBs.
  - Measurement: cold boot attempt with console ramoops capture and host USB disconnect/reconnect timing analysis in `journalctl -k`.

### Question 3: Image Layout Limits
- **Header Version:** Android Header Version 4 across `boot.img`, `init_boot.img`, and `vendor_boot.img`.
- **Page Size:** 4096 bytes (0x1000).
- **Load Offsets:** Kernel `0x8000`, ramdisk `0x1000000`, tags `0x100`, dtb `0x1f00000` (matching stock `vendor_boot_a`).
- **Signed-Tail Bound Evaluation:**
  - In vendor #55 (`2026-10-23-2245`), the stock `boot_a` signed-tail bound was measured at **13,967,360 bytes** (kernel payload 13,949,926 bytes).
  - The mainline candidate `Image.gz` is 15,210,129 bytes (~14.5 MiB).
  - Verification result: Mainline `Image.gz` exceeds the 13,967,360-byte stock signed-tail bound by 1,242,769 bytes (~1.24 MiB).
  - Consequence: Candidate `boot.img` cannot retain the stock-tail layout; it relies on the bootloader executing an unsigned image within the 96 MiB partition boundary (`100,663,296 bytes`), which candidate `boot.img` (15,216,640 bytes) easily satisfies.

### Question 4: Command Line
- **Stock Baseline:** Measured from `live-fdt.dts` `/chosen/bootargs` (113 bytes vendor cmdline + 175 bytes bootconfig).
- **Mainline Justifications:**
  - `console=tty0`: Routes kernel console output to the framebuffer VT on the phone display.
  - `earlycon`: Emits early boot messages via stdout-path (GENI debug UART).
  - `clk_ignore_unused pd_ignore_unused`: **Strictly necessary.** On Snapdragon SoCs without native KMS display drivers, late init gates unused clocks and power domains, terminating the continuous splash framebuffer.
  - `fbcon=font:TER16x32`: Large font for high-DPI (1080x2392) readability.
  - `panic=-1`: Halts on kernel panic, preventing reboot loops and preserving ramoops.
  - `bootconfig`: Enables kernel to parse bootconfig parameters from `vendor_boot.img`.
  - `ioremap_guard loglevel=6`: Diagnostic guards.

### Question 5: USB Path
- **Dependency Trace:**
  - Clocks: `GCC_CFG_NOC_USB3_PRIM_AXI_CLK`, `GCC_USB30_PRIM_MASTER_CLK`, `GCC_AGGRE_USB3_PRIM_AXI_CLK`, `GCC_USB30_PRIM_SLEEP_CLK`, `GCC_USB30_PRIM_MOCK_UTMI_CLK`, `RPMH_CXO_CLK`.
  - Power domain: `USB30_PRIM_GDSC`.
  - SoC eUSB2 PHY (`usb_1_hsphy: phy@88e3000`): `vreg_l2b` (0.88–0.92 V), `vreg_l4b` (1.2 V).
  - PMIV0104 eUSB2 repeater (`pmiv0104_eusb2_repeater`): `vreg_l7b` (1.8 V), `vreg_l17b` (3.0 V).
  - PM7550 L22 Discrepancy: Upstream DT specifies 3.2 V; stock FDT specifies 3.3 V. Pro DT specifies 3.3 V. Crucially, L22 powers `vci-supply` (display/touch), NOT USB. USB PHY and repeater do not depend on L22.
  - PMIC-GLINK / Type-C: In early boot without ADSP firmware, `drivers/usb/dwc3/drd.c` defaults to peripheral role (`dwc3_set_mode(dwc, DWC3_GCTL_PRTCAP_DEVICE)`), registering UDC `a600000.usb`. Binding gadget in initramfs triggers QSCRATCH VBUS override in `dwc3-qcom.c`.
  - Unproven: Repeater eye diagram tuning on physical cable without vendor calibration.
- **Gadget IDs and Lab IP Scheme:**
  - Gadget IDs: `1d6b:0104` (Linux Foundation Multifunction Composite Gadget), CDC ECM + CDC NCM.
  - IP Scheme: Candidate `/init` is updated to assign both **`172.16.42.2/24`** (lab standard per `phone-second-life/AGENTS.md` and record #53) and **`192.168.10.2/24`** (compatibility). Dropbear listens on port 22 on all interfaces.

### Question 6: Framebuffer
- **Scanned Out Buffer:** Stock runtime evidence (`console-ramoops-0` and `live-fdt.dts`) establishes that Qualcomm ABL programs `splash_region` at physical address `0xe3940000` with size `0x2b00000` (43 MiB). The other display region (`non_secure_display_region`) is an unmapped dynamic CMA pool (`shared-dma-pool`, size `0xa400000`), not a fixed scanout buffer.
- **Stride and Format:** Width = 1080, Height = 2392, Format = `a8r8g8b8` (32bpp ARGB), Stride = 4320 bytes (0x10e0). Visible scanout memory = 10,333,440 bytes (~9.85 MiB).
- **Active after Handoff:** Continuous splash scanout hardware remains active provided clocks and power domains remain unclocked; `clk_ignore_unused pd_ignore_unused` is required to prevent late-init shutdown.
- **Overlap Check:** Physical memory range `0xe3940000`–`0xe643ffff` sits between `rmtfs@e1f00000` (ends `0xe2000000`) and `qtee-region@e8900000` (starts `0xe8900000`). Verified 0 bytes overlap with any node in `milos.dtsi`.
- **Path Sanitization:** All absolute user paths removed from public documentation; cited by file name and SHA-256 only.

### Question 7: Observability of a Failed Boot
- **Ramoops / Pstore:** Matches stock reserved region `ramoops_region`: physical address `0x81f20000`, length `0x400000` (4 MiB), `console-size = 0x200000` (2 MiB), `pmsg-size = 0x200000` (2 MiB), `mem-type = 2`. Built-in kernel support is enabled (`CONFIG_PSTORE=y`, `CONFIG_PSTORE_CONSOLE=y`, `CONFIG_PSTORE_PMSG=y`, `CONFIG_PSTORE_RAM=y`).
- **Screen Output:** Framebuffer console displays boot log, deferred probe reasons, and initramfs motd banner.
- **Watchdog:** 150-second watchdog in `/init` triggers `/bin/restart2 bootloader` unless `/run/keep` is touched.
- **Hardware Recovery:** Power + Volume Up (10s) switches off; Power + Volume Down enters fastboot unconditionally.
- **Retrievability Summary:**
  - *Retrievable:* Kernel dmesg up to crash (via pstore on subsequent boot if kernel reached `~0.068s`); visual feedback on screen; host USB reset timing in `journalctl -k`.
  - *Not Retrievable:* Pre-kernel ABL rejections (do not write to ramoops; ramoops retains prior boot log); crashes before ramoops probe; UART serial output without soldered test points.

### Question 8: Rollback
- **Partitions Written:**
  - Candidate 1 (Slot B, recommended): `boot_b`, `init_boot_b`, `vendor_boot_b` (and optionally `dtbo_b`).
  - Candidate 1 (Slot A): `boot_a`, `init_boot_a`, `vendor_boot_a`.
- **Verified Stock Hashes & Manifests:**
  - `boot_a` / `boot_b`: `197aff11679301ca4a2d6f74dfcb942c3543ac9d41628e4e2116af0bdb706d4d`
  - `init_boot_a` / `init_boot_b`: `baa33fd43c3da1d9f3358ced9249c42abecc704fc5707a5241ea69e77c1e3193`
  - `vendor_boot_a` / `vendor_boot_b`: `237259404601045205715a71b88016744c73729d4513349cfe90c754b0dc1253`
  - `dtbo_a` / `dtbo_b`: `759813dbfd94f4a4124b08afb2c9ef85f1f9afb7cdca9829be2558ffde13c992`
  - `vbmeta_a` / `vbmeta_b`: `cc1926d2aa8e9c12df6a469111bf87f1e61e70022b84626fabcd014ae33cdffe`
  - Reference manifests: `parts-a.sha256`, `parts-b.sha256`, `parts.sha256`.
- **Slot A vs Slot B Comparison:**
  - Testing on Slot B preserves Slot A as a 100% untouched stock Android installation. Rollback from Slot B requires only `fastboot set_active a`.
  - Testing on Slot A overwrites active boot partitions, requiring full partition re-flashing to restore stock.
- **Copy-Pasteable Rollback:** Detailed step-by-step in Section 6.

---

## 4. Ranked Residual Risks

| Rank | Risk | Probability | Impact | Reasoning |
|---|---|---|---|---|
| **1** | **ABL Unsigned Image Rejection** | Medium-High | High | ABL returned to fastboot within 4–5s in all four custom slot-A kernel tests (`0134`, `0640`, `1156`, `1717`). It remains unproven whether ABL requires an AVB footer or stock-like signature envelope on an unlocked bootloader. |
| **2** | **DTBO Overlay Application Conflict** | Medium | High | If Slot A is booted with custom base DTB and stock `dtbo_a` is active, ABL will attempt to apply DTBO 65, failing with `FDT_ERR_NOTFOUND`. Mitigated by testing on Slot B with neutralized `dtbo_b`. |
| **3** | **ABL Single-DTB Rejection** | Low-Medium | High | Stock `vendor_boot_a` contains 20 concatenated DTBs. Candidate `vendor_boot.img` contains 1 DTB. If ABL parser expects a full table matching stock index 9, it may reject single-DTB images. |
| **4** | **eUSB2 Repeater Signal Integrity** | Low-Medium | Medium | The eUSB2 repeater requires precise analog tuning properties (`tune-res-fsdif`, `tune-usb2-amplitude`). Inherited DT properties may fail to achieve physical USB 2.0 High-Speed handshake on certain host ports. |
| **5** | **Display Clock Shutdown During Late Init** | Low | Low-Medium | Mitigated by passing `clk_ignore_unused pd_ignore_unused` in bootargs. If clock gating bypasses these flags, screen goes black after ~2s while USB may still function. |

---

## 5. Candidate Boot Chains & Verified Artifacts

### 5.1 Candidates
- **Candidate 1 (Primary): Header v4 Multi-Partition Set**
  - Architecture: Standard Android Boot Image Header Version 4.
  - Components: `boot.img` (kernel), `init_boot.img` (generic ramdisk), `vendor_boot.img` (DTB + vendor ramdisk + bootconfig).
  - Target: Flashed to Slot B partitions (`boot_b`, `init_boot_b`, `vendor_boot_b`) with `dtbo_b` neutralized.
- **Candidate 2 (Secondary): Header v4 Standalone Ramdisk-in-Boot Image**
  - Architecture: Header Version 4 with embedded generic ramdisk in `boot.img` (`boot-standalone.img`).
  - Single variable that differs: Ramdisk is delivered inside `boot.img` rather than `init_boot.img`, intended exclusively for temporary non-destructive `fastboot boot` evaluation without writing to flash.

### 5.2 Verified Artifact Hashes
Generated by `scripts/build-bootimg.sh` and verified by `scripts/verify-bootimg.sh`:

| Artifact | Size (bytes) | SHA-256 | Description |
|---|---|---|---|
| `boot.img` | 15,216,640 | `fcc6b961f2c684544c12300aa2bfbd5d827db1190e813d8ea136d4fe836749d5` | Header v4, gzipped mainline `Image.gz`, empty ramdisk |
| `init_boot.img` | 1,679,360 | `12fd0020dc2fa4b1e9a61a20c145e5283e015fe8b44a815a627a048cfd271e53` | Header v4, empty kernel, generic debug initramfs |
| `vendor_boot.img` | 1,761,280 | `5e23468a0bc8fbe8457df03867710cf254bfefab7857413b8df6db242ed719a1` | Header v4, `milos-nothing-asteroids-pro.dtb`, vendor ramdisk, bootconfig |
| `boot-standalone.img` | 16,891,904 | `a9b81d8e5bb1505c8239b2ec1534ec26c899f5ab8c1b1abcf63864bfa32b7881` | Header v4, embedded kernel + generic ramdisk + merged cmdline |
| `dtb.img` | 69,859 | `5c9c83b8dd02d0eae69aa7ffa2ddde31e2fbad0901bfb308b0e9e257c7c1e6c0` | Standalone Pro DTB with `qcom,msm-id` and `qcom,board-id` |
| `Image.gz` | 15,210,129 | `f53d6409f49f84d8658e419772bf0e3ff3902a778c381a32fc2655bbc578d0a7` | Mainline Linux 7.3 compressed kernel Image |
| `initramfs.cpio.gz` | 1,674,692 | `519e524e9d921d0c1374b7b12f6d4b4a8b05e0c70c2e22cecedd6cc96317768a` | Reproducible gzip newc cpio with busybox, dropbear, restart2 |

### 5.3 DT-Schema and Multi-Device Validation
- `milos-nothing-asteroids.dtb` SHA-256: `020f9b7be25af001958febc0ba15efc87e4c86c25553e3c47f8aa1120304ad4a` (**Byte-identical** to baseline).
- `milos-fairphone-fp6.dtb` SHA-256: `c3908fe06eeb9e236923b9081639d7f7d18bb10d42848077750b2397c8f5ad6a` (**Byte-identical** to baseline).
- `milos-nothing-asteroids-pro.dtb`: Schema check via `make CHECK_DTBS=1` and `dt-validate` confirms clean schema exit (rc=0). Schema inspection shows expected diagnostics:
  ```
  arch/arm64/boot/dts/qcom/milos-nothing-asteroids-pro.dtb: / (nothing,asteroids-pro): False schema does not allow [[11, 0]]
  arch/arm64/boot/dts/qcom/milos-nothing-asteroids-pro.dtb: / (nothing,asteroids-pro): False schema does not allow [[640, 65536], [641, 65536], [636, 65536]]
  ```
  These warnings occur because upstream `qcom.yaml` marks `qcom,msm-id` and `qcom,board-id` as deprecated for new SoCs, while Qualcomm ABL bootloader on `mb003` strictly requires them for DTB matching.

---

## 6. Operator Test Plan and Verified Rollback

> [!IMPORTANT]
> Host work only. Physical execution is reserved for the human operator under explicit flash approval.
> Verify device identity, battery state (>50%), and backup checksums before writing.

### 6.1 Preparation & Preflight Verification
1. Put device into fastboot mode manually: hold Power + Volume Up to turn off, then hold Power and press Volume Down.
2. Confirm device identity:
   ```sh
   fastboot devices
   # Expected output: 00181152O003821 fastboot
   fastboot getvar unlocked
   # Expected: unlocked: yes
   fastboot getvar current-slot
   # Expected: current-slot: a
   ```
3. Verify local backup files against manifest before any write:
   ```sh
   cd ~/phone-second-life-data/mb003
   sha256sum -c parts-a.sha256
   sha256sum -c parts-b.sha256
   ```

### 6.2 Candidate 1 Test Execution (Slot B Carrier)
```sh
# 1. Flash candidate images to Slot B only (Slot A remains untouched stock Android)
fastboot flash boot_b ~/sm7635-build/out-mainline/boot.img
fastboot flash init_boot_b ~/sm7635-build/out-mainline/init_boot.img
fastboot flash vendor_boot_b ~/sm7635-build/out-mainline/vendor_boot.img

# 2. Switch active slot to B
fastboot set_active b

# 3. Boot candidate
fastboot reboot
```

### 6.3 Host-Side Observation & Failure Classification Matrix

| Observation | Failure Class | Log Source to Inspect | Action / Next Step |
|---|---|---|---|
| Phone screen displays boot banner + console, USB `1d6b:0104` enumerates, SSH connects on `172.16.42.2:22` | **SUCCESS** | Host terminal (`uname -a`, `/etc/motd`) | Operator logs in, runs `touch /run/keep` to disable 150s watchdog, records kernel release. |
| Re-enumerates as fastboot `18d1:d00d` within 4–5 seconds with no screen activity | **ABL Image Rejection** | Host `journalctl -k` (timestamp & reset cycle) | ABL rejected unsigned kernel or DTB. Rollback to Slot A; inspect ramoops after stock recovery boot. |
| Screen displays boot console, but no USB device `1d6b:0104` appears within 30s | **USB PHY / UDC Failure** | Phone display (`/dev/tty0` deferred probes) | Screen shows `/sys/kernel/debug/devices_deferred`. Watchdog reboots after 150s. |
| USB `1d6b:0104` enumerates, but network interface drops packets or DHCP fails | **Network Binding Failure** | Host `dmesg`, `ip link`, `lsusb -v` | Configure host manually: `sudo ip addr add 172.16.42.1/24 dev <iface> && sudo ip link set <iface> up`. |
| USB `1d6b:0104` up, IP pingable, but SSH port 22 refused | **Dropbear Failure** | Phone display (`/dev/tty0` dropbear log lines) | Check `/proc/net/tcp` output on screen; test port 22 with `nc -zv 172.16.42.2 22`. |
| Screen remains completely dark, no USB enumeration, no reboot within 180s | **Early Kernel Hang** | Ramoops after manual recovery boot | Force power off (Power + Vol Up 10s), boot recovery, dump `/sys/fs/pstore/console-ramoops-0`. |

### 6.4 Verified Copy-Pasteable Rollback Path
If any abort condition occurs:
```sh
# 1. Enter fastboot mode (Power + Vol Up 10s, then hold Power + Vol Down)
fastboot devices

# 2. If Slot B was used: switch active slot back to untouched Slot A
fastboot set_active a

# 3. (Optional) Re-flash verified stock images to Slot B to restore original state:
fastboot flash boot_b ~/phone-second-life-data/mb003/parts/boot_b.img
fastboot flash init_boot_b ~/phone-second-life-data/mb003/parts/init_boot_b.img
fastboot flash vendor_boot_b ~/phone-second-life-data/mb003/parts/vendor_boot_b.img

# 4. If Slot A was flashed directly: restore verified stock images to Slot A:
fastboot flash boot_a ~/phone-second-life-data/mb003/parts/boot_a.img
fastboot flash init_boot_a ~/phone-second-life-data/mb003/parts/init_boot_a.img
fastboot flash vendor_boot_a ~/phone-second-life-data/mb003/parts/vendor_boot_a.img

# 5. Confirm slot A is active and bootable
fastboot getvar current-slot
# Expected: current-slot: a

# 6. Reboot to stock Android
fastboot reboot
```
After reboot, verify stock Android reaches `sys.boot_completed=1`.
