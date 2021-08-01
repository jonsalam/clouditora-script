#!/bin/bash

source ../script-helper.sh
assert_command_exist docker

yum install -y yum-utils device-mapper-persistent-data lvm2
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
yum install -y docker-ce docker-ce-cli containerd.io
mkdir -p /etc/docker
cat <<EOF | tee /etc/docker/daemon.json
{
  "registry-mirrors": [
    "https://registry.cn-beijing.aliyuncs.com"
  ],
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "5"
  },
  "storage-driver": "overlay2"
}
EOF
systemctl daemon-reload
systemctl enable docker
systemctl restart docker
