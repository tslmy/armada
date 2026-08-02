#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: boot-sd-once.sh [--now]

Run this from an internally-installed Armada system while an Armada SD card is
inserted. It installs a temporary shutdown unit that lets Armada regenerate the
internal ABL /KERNEL normally, then renames it to KERNEL.armada-disabled as the
last shutdown step so ROCKNIX ABL falls through to the SD card.

Options:
  --now    Reboot immediately after arming the one-shot shutdown unit.
EOF
}

reboot_now=0
case "${1:-}" in
    "") ;;
    --now) reboot_now=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
esac

if [[ ${EUID} -ne 0 ]]; then
    exec sudo -- "$0" "$@"
fi

efi_source=$(findmnt -no SOURCE /boot/efi)
if [[ ${efi_source} == /dev/mmcblk* ]]; then
    echo "ERROR: /boot/efi is already on SD (${efi_source}); run this from internal Armada." >&2
    exit 1
fi

if [[ ! -f /boot/efi/KERNEL ]]; then
    echo "ERROR: /boot/efi/KERNEL is not present on the internal ESP." >&2
    exit 1
fi

if [[ ! -b /dev/mmcblk0p1 || ! -b /dev/mmcblk0p2 || ! -b /dev/mmcblk0p3 ]]; then
    echo "ERROR: expected Armada SD card partitions /dev/mmcblk0p1..p3 are not present." >&2
    exit 1
fi

sd_efi_label=$(lsblk -no LABEL /dev/mmcblk0p1 | head -1)
sd_boot_label=$(lsblk -no LABEL /dev/mmcblk0p2 | head -1)
sd_root_label=$(lsblk -no LABEL /dev/mmcblk0p3 | head -1)
if [[ ${sd_efi_label} != ARMADA || ${sd_boot_label} != boot || ${sd_root_label} != root ]]; then
    echo "ERROR: /dev/mmcblk0 does not look like an Armada SD card:" >&2
    echo "  p1 label: ${sd_efi_label:-<none>} (expected ARMADA)" >&2
    echo "  p2 label: ${sd_boot_label:-<none>} (expected boot)" >&2
    echo "  p3 label: ${sd_root_label:-<none>} (expected root)" >&2
    exit 1
fi

cat >/run/systemd/system/armada-boot-sd-once.service <<'EOF'
[Unit]
Description=Temporarily disable internal Armada ABL image to boot SD once
DefaultDependencies=no
RequiresMountsFor=/boot/efi
After=local-fs.target systemd-journal-flush.service
Before=armada-bootimg-sync.service final.target
Conflicts=final.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/true
ExecStop=/bin/sh -eu -c 'if [ -f /boot/efi/KERNEL ]; then mv -f /boot/efi/KERNEL /boot/efi/KERNEL.armada-disabled; sync /boot/efi; else echo "armada-boot-sd-once: /boot/efi/KERNEL already missing" >&2; fi'
EOF

systemctl daemon-reload
systemctl start armada-boot-sd-once.service

echo "Armed SD boot for the next shutdown."
echo "Internal ESP: ${efi_source}"
echo "SD card: /dev/mmcblk0 (ARMADA/boot/root)"

if ((reboot_now)); then
    systemctl reboot
else
    echo "Reboot when ready, or run: sudo systemctl reboot"
fi
