#!/bin/bash
# create-buildenv/setup.sh 
incus init images:debian/12/cloud isobuilder-vm --vm \
  --no-profiles \
  --config=limits.cpu=2 \
  --config=limits.memory=4GiB \
  --config=cloud-init.user-data="$(cat isobuilder-vm_user-data)" \
  --config=cloud-init.network-config="$(cat isobuilder-vm_network-config)" \
  --device=root,size=20GiB
incus config device add isobuilder-vm eth0 nic nictype=bridged parent=vmbr21
incus start isobuilder-vm
