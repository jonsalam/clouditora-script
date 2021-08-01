#!/bin/bash

source ../script-helper.sh
assert_command_exist java

yum install -y java-11-openjdk-devel.x86_64
JAVA_HOME=$(which java |xargs ls -lrt |awk '{print $NF}' |xargs ls -lrt |awk '{print $NF}' |awk -F '/' '{for (i=1;i<=NF-3;i++) printf("%s/", $i); print $(NF-2)}')

echo "JAVA_HOME=$HOME" >> /etc/profile
echo "PATH=$PATH:$JAVA_HOME/bin" >> /etc/profile

source /etc/profile
