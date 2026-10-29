#!/usr/bin/env bash
# Written by Ring0 (Discord: process_vm_writev)
set -euo pipefail

PFX="${1:?usage: spoof.sh <wine-prefix> [interface]}"
IFACE="${2:-eno1}"

if [ ! -d "$PFX" ]; then
  echo "[!] prefix not found at $PFX"
  exit 1
fi

gen_uuid() { python3 -c "import uuid; print(uuid.uuid4())"; }
gen_hash() { python3 -c "import hashlib, os; print(hashlib.md5(os.urandom(32)).hexdigest())"; }
gen_mac()  { python3 -c "import random; b=[random.randint(0,255) for _ in range(6)]; b[0]=b[0]&0xfe|0x02; print(':'.join(f'{x:02x}' for x in b))"; }
gen_name() { echo "DESKTOP-$(python3 -c "import random,string; print(''.join(random.choices(string.ascii_uppercase+string.digits,k=7)))")"; }
gen_serial() { python3 -c "import random; print(random.randint(100000000000000,999999999999999))"; }
gen_volserial() { python3 -c "import random; print(format(random.randint(0,0xffffffff),'08x'))"; }

NEW_GUID=$(gen_uuid)
NEW_MAC=$(gen_mac)
NEW_NAME=$(gen_name)
NEW_BOARD=$(gen_serial)
NEW_UUID=$(gen_uuid)
NEW_VOLSERIAL=$(gen_volserial)

sed -i "s|\"MachineGuid\"=\"[^\"]*\"|\"MachineGuid\"=\"$NEW_GUID\"|g" "$PFX/system.reg"
echo "[+] spoofed MachineGuid"

sed -i "s|\"ComputerName\"=\"[^\"]*\"|\"ComputerName\"=\"$NEW_NAME\"|g" "$PFX/system.reg"
echo "[+] spoofed ComputerName"

echo "Local Disk" > "$PFX/drive_c/.windows-label"
echo "$NEW_VOLSERIAL" > "$PFX/drive_c/.windows-serial"
echo "[+] spoofed VolumeLabel"

find "$PFX/drive_c/users" -maxdepth 5 -type d \( -name "Crashes" -o -name "Logs" \) -path "*/Saved/*" -exec rm -rf {} + 2>/dev/null
echo "[+] cleaned UE4/UE5 cached IDs"

find "$PFX/drive_c/users" -maxdepth 6 -name "installation_id" -path "*/.sentry-native/*" 2>/dev/null | while read -r f; do
  echo -e "$(gen_uuid)\n$(gen_hash)" > "$f"
  rm -f "$(dirname "$f")"/*.run.lock
  echo "[+] spoofed Sentry ID ($(basename "$(dirname "$(dirname "$f")")"))"
done

sudo ip link set dev "$IFACE" down
sudo ip link set dev "$IFACE" address "$NEW_MAC"
sudo ip link set dev "$IFACE" up
sleep 2
echo "[+] spoofed MAC on $IFACE"

for f in board_serial product_uuid product_serial; do
  tmp="/tmp/.dmi_$f"
  target="/sys/class/dmi/id/$f"
  case "$f" in
    board_serial)    echo "$NEW_BOARD" | sudo tee "$tmp" > /dev/null ;;
    product_uuid)    echo "$NEW_UUID"  | sudo tee "$tmp" > /dev/null ;;
    product_serial)  echo "$NEW_NAME"  | sudo tee "$tmp" > /dev/null ;;
  esac
  sudo mount --bind "$tmp" "$target" 2>/dev/null && echo "[+] spoofed $f" || echo "[!] failed to spoof $f"
done

echo ""
echo "[!] turn on your VPN before launching. the ban is IP-based"
