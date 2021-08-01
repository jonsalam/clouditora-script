#!/bin/bash

source ../script-helper.sh

yum install -y python3

check_command_exist || {
  curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py
  python3 get-pip.py
  rm -rf get-pip.py
}
