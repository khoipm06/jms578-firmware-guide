#!/usr/bin/env bash
# Script to enable UAS (USB Attached SCSI) for JMS578 on Linux
# By default, Linux kernel blacklists UAS for 152d:0578 due to old firmware bugs.
# Once Hardkernel v173.01.00.02 is installed, UAS is stable and can be enabled via the 'u' quirk flag.

set -e

echo "==> Configuring usb-storage quirk for JMS578 (152d:0578)..."

RULE_FILE="/etc/modprobe.d/jms578-uas.conf"

echo "options usb-storage quirks=152d:0578:u" | sudo tee "$RULE_FILE" >/dev/null

echo "==> Configuration written to $RULE_FILE"
echo "==> To apply immediately without reboot:"
echo "    1. Unmount all partitions from the enclosure"
echo "    2. Unplug the USB cable"
echo "    3. Run: sudo modprobe -r uas usb_storage && sudo modprobe uas && sudo modprobe usb_storage"
echo "    4. Plug the USB cable back in"
echo "==> Then verify with: lsusb -t (should show 'Driver=uas')"
