#!/bin/bash
# Auto wipe all internal disks after login (root only)
# Logs result to /var/log/auto-wipe.log

LOGFILE="/var/log/auto-wipe.log"

# Only run for root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root. Please log in as root." | tee -a "$LOGFILE"
    return
fi

# Timestamp for log
echo "=================================================" | tee -a "$LOGFILE"
echo "[`date '+%Y-%m-%d %H:%M:%S'`] Auto-Wipe Triggered" | tee -a "$LOGFILE"
echo "=================================================" | tee -a "$LOGFILE"

echo " ??  WARNING: This machine's internal disks will be COMPLETELY ERASED "
echo "-------------------------------------------------"
echo " Target: Internal HDD/SSD (SATA, NVMe)"
echo " Using:hdparm or nvme-cli"
echo " Excluded: Booted USB device (removable), device-mapper (dm-*), loop devices"
echo " Process: Secure Erase (hdparm) or overwrite (shred)"
echo " Log file: $LOGFILE"
echo " Source: https://github.com/kishsaver/EraseSh"
echo "================================================="
echo
echo "[*] Current block devices (ERASE TARGETS marked):" | tee -a "$LOGFILE"

# List top-level block devices with mark
for disk in $(lsblk -dn -o NAME); do
    target="/dev/$disk"

    # Skip loop devices and device-mapper (LVM, crypt, etc.)
    if [[ "$disk" == loop* || "$disk" == dm-* ]]; then
        continue
    fi

    # Check removable/system disk
    removable=$(cat /sys/block/$disk/removable)
    mounted=$(mount | grep -q "^$target" && echo "yes" || echo "no")

    mark=""
    if [[ "$removable" == "0" && "$mounted" == "no" ]]; then
        mark="[*] ERASE TARGET"
    fi

    tran=$(lsblk -dn -o TRAN "$target" 2>/dev/null)
    size=$(lsblk -dn -o SIZE "$target" 2>/dev/null)
    type=$(lsblk -dn -o TYPE "$target" 2>/dev/null)

    printf "%-8s %-6s %-8s %-6s %s\n" "$disk" "$tran" "$size" "$type" "$mark" | tee -a "$LOGFILE"
done

echo "================================================="
echo
read -p "Are you sure you want to ERASE all marked targets? (yes/NO): " ans

if [[ "$ans" != "yes" ]]; then
    echo "Aborted." | tee -a "$LOGFILE"
    return
fi

echo "[*] Starting disk erase..." | tee -a "$LOGFILE"

for dev in /sys/block/*; do
    disk=$(basename "$dev")
    target="/dev/$disk"

    # Skip loop devices and device-mapper
    if [[ "$disk" == loop* || "$disk" == dm-* ]]; then
        echo "[!] Skipping $target (loop/device-mapper)" | tee -a "$LOGFILE"
        continue
    fi

    # Skip removable devices (USB sticks, SD cards)
    if [[ "$(cat "$dev/removable")" == "1" ]]; then
        echo "[!] Skipping $target (removable/USB device)" | tee -a "$LOGFILE"
        continue
    fi

    # Skip the disk that contains the running root filesystem
    if mount | grep -q "^$target"; then
        echo "[!] Skipping $target (system/boot device)" | tee -a "$LOGFILE"
        continue
    fi

    echo "[*] Erasing $target" | tee -a "$LOGFILE"

    # Partition table wipe (metadata)
    wipefs -a "$target" || true
    sgdisk --zap-all "$target" || true

    # ===== SSD向け: コントローラ機能での消去を最優先 =====

    # NVMe: セキュアフォーマット（暗号/ユーザーデータ消去）
    if [[ "$disk" == nvme* ]] && command -v nvme &>/dev/null; then
        echo "[*] NVMe secure format (ses=2 → 1) on $target..." | tee -a "$LOGFILE"
        if nvme format "$target" --ses=2 -f; then
            echo "[+] $target securely erased with NVMe format (ses=2)" | tee -a "$LOGFILE"
            continue
        fi
        if nvme format "$target" --ses=1 -f; then
            echo "[+] $target securely erased with NVMe format (ses=1)" | tee -a "$LOGFILE"
            continue
        fi
    fi

    # SATA SSD: ATA Secure Erase（enhanced優先）
    if [[ "$disk" == sd* ]] && command -v hdparm &>/dev/null; then
        if hdparm -I "$target" 2>/dev/null | grep -qi frozen; then
            echo "[!] $target is 'frozen'; suspend/resume then rerun to allow ATA Secure Erase" | tee -a "$LOGFILE"
        else
            echo "[*] Trying ATA Secure Erase on $target..." | tee -a "$LOGFILE"
            hdparm --user-master u --security-set-pass p "$target" || true
            if hdparm -I "$target" 2>/dev/null | grep -qi "supported: enhanced erase"; then
                if hdparm --user-master u --security-erase-enhanced p "$target"; then
                    echo "[+] $target securely erased with ATA Enhanced Secure Erase" | tee -a "$LOGFILE"
                    continue
                fi
            fi
            if hdparm --user-master u --security-erase p "$target"; then
                echo "[+] $target securely erased with ATA Secure Erase" | tee -a "$LOGFILE"
                continue
            fi
        fi
    fi

    # ===== フォールバック: 全域TRIM（discard） =====
    if command -v blkdiscard &>/dev/null; then
        if [[ -r "/sys/block/$disk/queue/discard_max_bytes" ]] && \
           (( $(cat "/sys/block/$disk/queue/discard_max_bytes" 2>/dev/null || echo 0) > 0 )); then
            echo "[*] Trying blkdiscard (TRIM) on $target..." | tee -a "$LOGFILE"
            if blkdiscard -f "$target"; then
                echo "[+] $target discarded (TRIM complete)" | tee -a "$LOGFILE"
                continue
            fi
        fi
    fi

    # ===== 上書き（SSDでは保証弱め。主にパススルー不可時の保険） =====
    echo "[*] Overwriting $target (last resort; may take a long time)..." | tee -a "$LOGFILE"
    # HDDは1パスで十分。SSDもここでは1パスに統一
    shred -v -n 1 "$target" | tee -a "$LOGFILE"
    echo "[+] $target overwritten" | tee -a "$LOGFILE"
done

echo "=================================================" | tee -a "$LOGFILE"
echo " ?  All internal disks have been erased" | tee -a "$LOGFILE"
echo "[*] Final block devices state:" | tee -a "$LOGFILE"
lsblk -o NAME,TRAN,SIZE,TYPE,MOUNTPOINT | tee -a "$LOGFILE"
echo "=================================================" | tee -a "$LOGFILE"

echo
echo "================================================="
echo " ?  All internal disks have been erased"
echo " Log file: $LOGFILE"
echo "================================================="
echo
echo "Please review the above messages."
read -p "Reboot the system now? (yes/NO): " reboot_ans

if [[ "$reboot_ans" == "yes" ]]; then
    reboot
else
    echo "System will stay running. You can check logs in $LOGFILE"
fi
