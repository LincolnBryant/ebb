#!/usr/bin/env bash
set -euo pipefail

# Subnet must match ebb's ?DEFAULT_CIDR_RANGE ("172.16.0.0/16").
NET_START="172.16.0.1"
NET_END="172.16.255.254"
NET_MASK="255.255.0.0"

exec sudo qemu-system-x86_64 \
  -machine q35 \
  -cpu qemu64 \
  -m 512 \
  -netdev vmnet-host,id=net0,start-address="${NET_START}",end-address="${NET_END}",subnet-mask="${NET_MASK}" \
  -device e1000,netdev=net0,mac=52:54:00:12:34:56 \
  -boot n \
  -nographic \
  -no-reboot
