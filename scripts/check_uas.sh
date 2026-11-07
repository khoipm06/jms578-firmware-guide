#!/usr/bin/env bash
# Simple check for JMS578 UAS driver status and kernel quirks
set -e

echo "==> Auditing JMS578 (152d:0578) driver binding and quirks..."

# 1. Check for conflicting usb-storage quirks
if grep -rn "152d:0578:u" /etc/modprobe.d/ 2>/dev/null; then
    echo "[WARNING] Found 'quirks=152d:0578:u' in /etc/modprobe.d/."
    echo "          In the Linux kernel, flag 'u' sets US_FL_IGNORE_UAS, which disables UAS."
    echo "          Remove this file to allow native UAS binding."
else
    echo "[OK] No conflicting ':u' (IGNORE_UAS) quirks found in /etc/modprobe.d/."
fi

# 2. Check active driver binding in USB tree
if lsusb -t | grep -q "Driver=uas"; then
    echo "[SUCCESS] Driver=uas is active (SuperSpeed UAS multi-queue enabled)."
elif lsusb -t | grep -q "Driver=usb-storage"; then
    echo "[INFO] Driver=usb-storage is active (BOT fallback mode)."
    echo "       Ensure firmware is updated to Hardkernel v173.01.00.02 and no quirks are set."
else
    echo "[INFO] JMS578 device not currently detected on USB bus."
fi
