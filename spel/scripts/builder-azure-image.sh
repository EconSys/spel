#!/bin/bash
#
# Script to create a custom image from which to later create a spel image.
# This script expects an Azure marketplace EL7 offer, publisher, sku that does
# not have cloud-init configured.  The script will install and configure
# cloud-init in the resultant custom image which is to be used in subsequent
# execution for spel image creation.
#
##############################################################################
set -eu -o pipefail

HTTP_PROXY="${SPEL_HTTP_PROXY}"

if [[ -n "${HTTP_PROXY:-}" ]]
then
   printf "\n%s\n" "${HTTP_PROXY}" >> /etc/yum.conf
fi

# install cloud-init
yum -y install cloud-init cloud-utils-growpart gdisk hyperv-daemons
yum -y update
yum clean all

# Configure waagent for cloud-init, per https://docs.microsoft.com/en-us/azure/virtual-machines/linux/create-upload-centos#centos-70
sed -i 's/Provisioning.UseCloudInit=n/Provisioning.UseCloudInit=y/g' /etc/waagent.conf
sed -i 's/Provisioning.Enabled=y/Provisioning.Enabled=n/g' /etc/waagent.conf

sed -i 's/ResourceDisk.Format=y/ResourceDisk.Format=n/g' /etc/waagent.conf
sed -i 's/ResourceDisk.EnableSwap=y/ResourceDisk.EnableSwap=n/g' /etc/waagent.conf

echo "Adding mounts and disk_setup to init stage"
sed -i '/ - mounts/d' /etc/cloud/cloud.cfg
sed -i '/ - disk_setup/d' /etc/cloud/cloud.cfg
sed -i '/cloud_init_modules/a\\ - mounts' /etc/cloud/cloud.cfg
sed -i '/cloud_init_modules/a\\ - disk_setup' /etc/cloud/cloud.cfg

echo "Allow only Azure datasource, disable fetching network setting via IMDS"
cat > /etc/cloud/cloud.cfg.d/91-azure_datasource.cfg <<EOF
datasource_list: [ Azure ]
datasource:
    Azure:
        apply_network_config: False
EOF

if [[ -f /mnt/resource/swapfile ]]; then
echo Removing swapfile - RHEL uses a swapfile by default
swapoff /mnt/resource/swapfile
rm /mnt/resource/swapfile -f
fi

echo "Add console log file"
cat >> /etc/cloud/cloud.cfg.d/05_logging.cfg <<EOF

# This tells cloud-init to redirect its stdout and stderr to
# 'tee -a /var/log/cloud-init-output.log' so the user can see output
# there without needing to look on the console.
output: {all: '| tee -a /var/log/cloud-init-output.log'}
EOF

cat > /etc/cloud/cloud.cfg.d/00-azure-swap.cfg << EOF
#cloud-config
# Generated by Azure cloud image build
disk_setup:
  ephemeral0:
    table_type: mbr
    layout: [66, [33, 82]]
    overwrite: True
fs_setup:
  - device: ephemeral0.1
    filesystem: ext4
  - device: ephemeral0.2
    filesystem: swap
mounts:
  - ["ephemeral0.1", "/mnt"]
  - ["ephemeral0.2", "none", "swap", "sw", "0", "0"]
EOF

sudo rm -rf /var/lib/waagent/
sudo rm -f /var/log/waagent.log
waagent -force -deprovision+user

echo "builder-azure-image.sh complete"'!'

rm -f ~/.bash_history
export HISTSIZE=0
