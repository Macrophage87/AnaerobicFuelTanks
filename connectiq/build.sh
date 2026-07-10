#!/usr/bin/env bash
# Build the Dual-Tank Anaerobic data field.
# Requires the Connect IQ SDK (monkeyc/monkeydo on PATH) and a developer key.
# Usage: ./build.sh [device]      device defaults to edge840
set -euo pipefail
DEVICE="${1:-edge840}"
KEY="${CIQ_KEY:-developer_key.der}"
mkdir -p bin

if [ ! -f "$KEY" ]; then
  echo "No developer key at '$KEY'. Generate one once with:"
  echo "  openssl genrsa -out developer_key.pem 4096"
  echo "  openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out developer_key.der -nocrypt"
  exit 1
fi

echo "Building for $DEVICE ..."
monkeyc -d "$DEVICE" -f monkey.jungle -o "bin/DualTank-$DEVICE.prg" -y "$KEY"
echo "Built bin/DualTank-$DEVICE.prg"
echo
echo "Run in the simulator:"
echo "  connectiq &            # launch simulator once"
echo "  monkeydo bin/DualTank-$DEVICE.prg $DEVICE"
echo
echo "Package a sideload/store .iq for all products:"
echo "  monkeyc -e -f monkey.jungle -o bin/DualTank.iq -y \"$KEY\""
