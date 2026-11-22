# AGENTS.md — linux-qualcomm-sm7635

Mainline Linux kernel for the Qualcomm SM7635/Milos platform across multiple
phones; Nothing Phone (3a) Pro is the first Omnipha investigation. A source
file is not proof of device support or a safe boot image.

- `upstream` mirrors the pinned Linux baseline. Put our work on `omnipha`.
- Put properties shared by the SoC in `milos.dtsi` or shared drivers; put
  board-specific wiring, panel, GPIOs, firmware names and similar information
  only in the relevant device or device-family tree.
- Do not copy vendor values or firmware without evidence and license review.
  Never commit firmware blobs, serial numbers, credentials or private data.
- State the exact device, kernel commit and test for every support claim;
  distinguish source presence, successful build and tested device behavior.
- No device flash or reboot without an independently verified recovery path.
- Follow https://github.com/omnipha/.github/blob/main/CONTRIBUTING.md and use
  English commit messages with a Signed-off-by line (`git commit -s`).
