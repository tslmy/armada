#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: boot-internal.sh [--now] [--esp DEVICE]

Run this from an Armada SD-card boot after boot-sd-once.sh. It mounts the
internal ROCKNIX ESP, renames KERNEL.armada-disabled back to KERNEL, then
optionally reboots so ROCKNIX ABL chooses the internal install again.

Options:
  --now         Reboot immediately after restoring internal /KERNEL.
  --esp DEVICE Internal ESP block device. Default: /dev/sda18.
EOF
}

reboot_now=0
internal_esp=/dev/sda18
while (($#)); do
    case "$1" in
        --now) reboot_now=1; shift ;;
        --esp)
            [[ $# -ge 2 ]] || { usage >&2; exit 2; }
            internal_esp=$2
            shift 2
            ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

if [[ ${EUID} -ne 0 ]]; then
    exec sudo -- "$0" "$@"
fi

efi_source=$(findmnt -no SOURCE /boot/efi)
if [[ ${efi_source} != /dev/mmcblk* ]]; then
    echo "ERROR: /boot/efi is ${efi_source}; run this from the Armada SD-card boot." >&2
    exit 1
fi

if [[ ! -b ${internal_esp} ]]; then
    echo "ERROR: internal ESP device does not exist: ${internal_esp}" >&2
    exit 1
fi

internal_label=$(lsblk -no LABEL "${internal_esp}" | head -1)
internal_partlabel=$(lsblk -no PARTLABEL "${internal_esp}" | head -1)
if [[ ${internal_label} != ROCKNIX && ${internal_partlabel} != ROCKNIX ]]; then
    echo "ERROR: ${internal_esp} does not look like the internal ROCKNIX ESP:" >&2
    echo "  label: ${internal_label:-<none>}" >&2
    echo "  partlabel: ${internal_partlabel:-<none>}" >&2
    exit 1
fi

mountpoint=/run/armada-internal-efi
mkdir -p "${mountpoint}"
if mountpoint -q "${mountpoint}"; then
    echo "ERROR: ${mountpoint} is already mounted." >&2
    exit 1
fi

cleanup() {
    if mountpoint -q "${mountpoint}"; then
        umount "${mountpoint}"
    fi
}
trap cleanup EXIT

mount "${internal_esp}" "${mountpoint}"

if [[ -f "${mountpoint}/KERNEL" ]]; then
    echo "Internal /KERNEL is already restored on ${internal_esp}."
elif [[ -f "${mountpoint}/KERNEL.armada-disabled" ]]; then
    mv -f "${mountpoint}/KERNEL.armada-disabled" "${mountpoint}/KERNEL"
    sync "${mountpoint}"
    echo "Restored internal /KERNEL on ${internal_esp}."
else
    echo "ERROR: neither KERNEL nor KERNEL.armada-disabled exists on ${internal_esp}." >&2
    exit 1
fi

cleanup
trap - EXIT

if ((reboot_now)); then
    systemctl reboot
else
    echo "Reboot when ready, or run: sudo systemctl reboot"
fi
