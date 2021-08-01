#!/bin/bash

RED=$(printf '\033[31m')
YELLOW=$(printf '\033[33m')
RESET=$(printf '\033[m')
echo_error() {
  echo "${RED}error: $*${RESET}" >&2
}
echo_warn() {
  echo "${YELLOW}warn: $*${RESET}" >&2
}
echo_info() {
  echo "$*" >&2
}

function check_command_exist {
	if command -v "$1" >/dev/null 2>&1; then
		echo_warn "$1 existed"
		return 1
	fi
}

function assert_command_exist {
  check_command_exist "$1"
	if [[ $? -eq 1 ]]; then
		exit 1
	fi
}

function assert_docker_container {
	status=$(docker ps -a --filter name="$1" --format "table {{.Status}}\t{{.ID}}" |sed -n '2p' |awk '{print $1}')
	if [[ -n $status ]]; then
		echo_warn "$1 already installed, status: $status"
		return 1
	fi
}
