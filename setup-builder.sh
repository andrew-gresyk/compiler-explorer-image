#!/bin/bash

set -ex

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [[ "$1" != "--updated" ]]; then
    sudo -u ubuntu git -C ${DIR} pull
    pwd
    exec bash ${BASH_SOURCE[0]} --updated
    exit 0
fi

systemctl stop docker
umount /ephemeral || true
sfdisk -f /dev/nvme0n1 <<EOF
label: dos
label-id: 0xbebcaa2e
device: /dev/nvme0n1
unit: sectors

/dev/nvme0n1p1 : start=        2048, size=   781247952, type=83
EOF
sync
sleep 2 # let the device get registered
mkfs.ext4 -F /dev/nvme0n1p1
rm -rf /ephemeral
mkdir /ephemeral
mount /dev/nvme0n1p1 /ephemeral

cat > /etc/docker/daemon.json <<EOF
{
        "data-root": "/ephemeral/docker"
}
EOF
systemctl start docker

env EXTRA_NFS_ARGS="" ${DIR}/setup-common.sh

apt -y install python2.7 python-pip mosh fish jq ssmtp cronic subversion upx gdb
chsh ubuntu -s /usr/bin/fish

cd /home/ubuntu/compiler-explorer-image
pip install --upgrade pip 
hash -r pip
pip install --upgrade awscli
pip install -r requirements.txt

# Install private and public keys
aws ssm get-parameter --name /admin/ce_private_key | jq -r .Parameter.Value > /home/ubuntu/.ssh/id_rsa

chmod 600 /home/ubuntu/.ssh/id_rsa
aws s3 cp s3://compiler-explorer/authorized_keys/admin.key /home/ubuntu/.ssh/id_rsa.pub
chown -R ubuntu:ubuntu /home/ubuntu/.ssh
chown -R ubuntu:ubuntu /home/ubuntu/compiler-explorer-image

sudo -u ubuntu fish setup.fish

# Configure email
SMTP_PASS=$(aws ssm get-parameter --name /admin/smtp_pass | jq -r .Parameter.Value)
cat > /etc/ssmtp/ssmtp.conf <<EOF
root=postmaster
mailhub=email-smtp.us-east-1.amazonaws.com
hostname=compiler-explorer.com
FromLineOverride=NO
AuthUser=AKIAJZWPG4D3SSK45LJA
AuthPass=${SMTP_PASS}
UseTLS=YES
UseSTARTTLS=YES
EOF
cat > /etc/ssmtp/revaliases <<EOF
ubuntu:admin@compiler-explorer.com:email-smtp.us-east-1.amazonaws.com
EOF

chfn -f 'Compiler Explorer Admin' ubuntu
chmod 640 /etc/ssmtp/*

hostname builder-node
perl -pi -e 's/127.0.0.1 localhost/127.0.0.1 localhost builder-node/' /etc/hosts
