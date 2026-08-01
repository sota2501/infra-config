#!/usr/bin/env bash
set -euo pipefail

TEMPLATE_VMID=9000
CLOUDINIT_IMAGE_TARGET_VOLUME=local-lvm
TEMPLATE_BOOT_IMAGE_TARGET_VOLUME=local-lvm

# re-running this script to rebuild the template requires removing the old one first
qm destroy $TEMPLATE_VMID --purge 2>/dev/null || true

# download the image(ubuntu 24.04 LTS)
wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img

# bake qemu-guest-agent into the image so it's already running on first boot.
# without this, Terraform's `agent { enabled = true }` waits forever for the
# agent to respond and `terraform apply` hangs on "Still creating...".
# requires: apt-get install -y libguestfs-tools
virt-customize -a noble-server-cloudimg-amd64.img \
  --install qemu-guest-agent \
  --run-command 'systemctl enable qemu-guest-agent'

# create a new VM and attach Network Adaptor
qm create $TEMPLATE_VMID --cores 2 --memory 4096 --net0 virtio,bridge=vmbr0 --name iris-k8s-template

# import the downloaded disk to $TEMPLATE_BOOT_IMAGE_TARGET_VOLUME storage
qm importdisk $TEMPLATE_VMID noble-server-cloudimg-amd64.img $TEMPLATE_BOOT_IMAGE_TARGET_VOLUME

# finally attach the new disk to the VM as scsi drive
qm set $TEMPLATE_VMID --scsihw virtio-scsi-pci --scsi0 $TEMPLATE_BOOT_IMAGE_TARGET_VOLUME:vm-$TEMPLATE_VMID-disk-0

# add Cloud-Init CD-ROM drive
qm set $TEMPLATE_VMID --ide2 $CLOUDINIT_IMAGE_TARGET_VOLUME:cloudinit

# set the bootdisk parameter to scsi0
qm set $TEMPLATE_VMID --boot c --bootdisk scsi0

# set serial console
qm set $TEMPLATE_VMID --serial0 socket --vga serial0

# migrate to template
qm template $TEMPLATE_VMID

# cleanup
rm noble-server-cloudimg-amd64.img
