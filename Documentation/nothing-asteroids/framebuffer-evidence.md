# Framebuffer and Early Console Evidence: Nothing Phone (3a) Pro (A059P)

Host-side hardware evidence and configuration parameters for early display console
via the bootloader continuous splash framebuffer on the Nothing Phone (3a) Pro (A059P),
Qualcomm SM7635 (Milos) platform.

This note establishes scanout buffer parameters from archived, read-only private stock
evidence on unit `mb003` to enable `simple-framebuffer` / `simpledrm` early text console.
Per `AGENTS.md`, this document contains only shareable hardware parameters, source file
references, and cryptographic hashes; no raw archives, device serial numbers, credentials,
or proprietary blobs are stored in this repository.

---

## 1. Framebuffer Parameters

The bootloader (Qualcomm Snapdragon ABL) initializes the primary display panel and leaves
a continuous splash scanout buffer active at kernel handoff. The parameters established
from private stock evidence are:

| Parameter | Value | Value (Hex) | Derivation & Source |
|---|---|---|---|
| **Base Address** | `3,818,127,360` | `0xe3940000` | Physical start address of `splash_region` in stock live FDT |
| **Reserved Region Size** | `45,088,768` bytes (43 MiB) | `0x02b00000` | Full reserved-memory reservation (`0xe3940000`–`0xe643ffff`) |
| **Visible Framebuffer Size** | `10,333,440` bytes (~9.85 MiB) | `0x009db800` | Active scanout buffer: `1080 * 2392 * 4` bytes |
| **Width** | `1080` pixels | `0x438` | `qcom,mdss-dsi-panel-width` in bound stock panel node |
| **Height** | `2392` pixels | `0x958` | `qcom,mdss-dsi-panel-height` in bound stock panel node |
| **Stride** | `4320` bytes | `0x10e0` | Line pitch: `width (1080) * 4 bytes/pixel` |
| **Format** | `a8r8g8b8` | - | Standard 32bpp little-endian ARGB format used by Qualcomm ABL |

---

## 2. Private Stock Evidence Sources

All evidence is derived from read-only host archives of unit `mb003`:

### 2.1 Stock Live Devicetree (Live FDT)
- **Binary archive:** `/home/gregor/phone-second-life-data/mb003/dtb/live-fdt.dtb`
  - **SHA-256:** `7310d10a9dc9c78a7c5bedd20375fd5506d0e7cbdc9ed7eac47a83651c259c6c`
- **Decompiled DTS:** `/home/gregor/phone-second-life-data/mb003/dtb/live-fdt.dts`
  - **SHA-256:** `a56788799b1badb047d245c1b1e36bfbe0277d17de0cec6b622e410b4de4fd78`
- **Key Evidence Nodes:**
  1. `/reserved-memory/splash_region`:
     ```dts
     splash_region {
         phandle = <0x5b8>;
         label = "cont_splash_region";
         reg = <0x00 0xe3940000 0x00 0x2b00000>;
     };
     ```
  2. `/soc/disp_rdump_region@e3940000`:
     ```dts
     disp_rdump_region@e3940000 {
         phandle = <0x5b7>;
         label = "disp_rdump_region";
         reg = <0xe3940000 0x800000>;
     };
     ```
  3. Bound display panel node `qcom,mdss_dsi_rm69220_fhd_plus_120hz_vid_boe`:
     - `qcom,mdss-dsi-panel-width = <0x438>;` (1080)
     - `qcom,mdss-dsi-panel-height = <0x958>;` (2392)
     - `qcom,mdss-dsi-panel-framerate = <0x78>;` (120 Hz)
     - `qcom,mdss-dsi-bpp = <0x1e>;` (30 bpp DSC / 32bpp scanout)
     - `qcom,mdss-dsi-panel-name = "rm69220 amoled vid mode dsi BOE panel with DSC";`
  4. Boot arguments in `/chosen`:
     ```
     bootargs = "... msm_drm.dsi_display0=qcom,mdss_dsi_rm69220_fhd_plus_120hz_vid_boe: ...";
     ```

### 2.2 Vendor Kernel Ramoops Console Log
- **File:** `/home/gregor/phone-second-life-data/mb003/pstore/console-ramoops-0`
- **SHA-256:** `c9c49d9244c6531ffb06560ca9c26b24b30786fdd03bc2bce7e193e80b453fd2`
- **Recorded Boot Evidence:**
  - `OF: reserved mem: 0x00000000e3940000..0x00000000e643ffff ( 44032 KB ) map non-reusable splash_region`
  - `[drm] cont_splash enabled in 1 of 1 display(s)`
  - `[drm:dsi_display_bind [msm_drm]] [msm-dsi-info]: Successfully bind display panel 'qcom,mdss_dsi_rm69220_fhd_plus_120hz_vid_boe '`
  - `[drm:dsi_display_set_mode [msm_drm]] [msm-dsi-info]: mdp_transfer_time=0, hactive=1080, vactive=2392, fps=120, clk_rate=0`

### 2.3 Stock DTBO Entry 65 (Pro Overlay)
- **File:** `/home/gregor/phone-second-life-data/mb003/dtb/dtbo_a.65.dtb`
- **SHA-256:** `93be04b6e20914fd1546ad314e351199bb3e6b6a71c2555ef956175164909ae2`
- **Model:** `Qualcomm Technologies, Inc. Volcano QRD Pro`
- **Identifiers:** `qcom,board-id = <11 0>`, `qcom,oem-id = <2>`

---

## 3. Devicetree Integration Design

To utilize this scanout buffer in mainline Linux without disturbing other targets:
1. **Multi-device boundary:**
   Additions are made exclusively to `arch/arm64/boot/dts/qcom/milos-nothing-asteroids-pro.dts`.
   The Nothing Phone (3a) (`milos-nothing-asteroids.dts`), Fairphone 6 (`milos-fairphone-fp6.dts`),
   and base SoC tree (`milos.dtsi`) remain untouched, ensuring byte-identical DTB outputs.
2. **`simple-framebuffer` node:**
   Placed under `/chosen` per the `Documentation/devicetree/bindings/display/simple-framebuffer.yaml`
   specification:
   ```dts
   chosen {
       #address-cells = <2>;
       #size-cells = <2>;
       ranges;

       framebuffer0: framebuffer@e3940000 {
           compatible = "simple-framebuffer";
           reg = <0x0 0xe3940000 0x0 (1080 * 2392 * 4)>;
           width = <1080>;
           height = <2392>;
           stride = <(1080 * 4)>;
           format = "a8r8g8b8";
       };
   };
   ```
3. **Matching `reserved-memory` node:**
   Protects the full continuous splash region from being recycled or allocated by the kernel
   memory management subsystem:
   ```dts
   reserved-memory {
       cont_splash_mem: cont-splash@e3940000 {
           reg = <0x0 0xe3940000 0x0 0x2b00000>;
           no-map;
       };
   };
   ```

---

## 4. Verification Boundaries and Out-of-Scope Capabilities

- **What this implementation provides:**
  Host-verified `simple-framebuffer` device tree bindings and kernel driver configurations that
  allow Linux to scan out early boot messages (`/dev/kmsg`), identity banner, and an interactive
  terminal (`/dev/tty0`) using the scanout buffer established by ABL.
- **What this does NOT prove:**
  - This is **not** a native DRM/KMS display driver.
  - Panel initialization, dynamic mode switching, DSC compression configuration, and refresh rate control are **out of scope**.
  - Backlight / brightness controls, display power management (runtime PM / suspend / resume), and touchscreen input are **out of scope**.
  - A lit screen or bootloader logo does not imply a functional display controller stack under Linux.
- **Hardware test status:**
  Host preparation, verification, and packaging complete. Physical booting on device is reserved
  for the human operator under explicit safety protocols.
