#!/bin/bash

RED=$(printf '\033[31m')
GREEN=$(printf '\033[32m')
YELLOW=$(printf '\033[33m')
RESET=$(printf '\033[m')
echo_error() {
  echo "${RED}$*${RESET}" >&2
}
echo_warn() {
  echo "${YELLOW}$*${RESET}" >&2
}
echo_info() {
  echo "${GREEN}$*${RESET}" >&2
}

# 检查命令是否存在
# 0:存在(true), 1:不存在(false)
function check_command_exist {
	if command -v "$1" >/dev/null 2>&1; then
		echo_warn "$1 existed"
		return 0
	else
	  return 1
	fi
}

function assert_command_exist {
  check_command_exist "$1" && exit 1
}

function assert_docker_container {
	status=$(docker ps -a --filter name="$1" --format "table {{.Status}}\t{{.ID}}" |sed -n '2p' |awk '{print $1}')
	if [[ -n $status ]]; then
		echo_warn "$1 already installed, status: $status"
		return 1
	fi
}
