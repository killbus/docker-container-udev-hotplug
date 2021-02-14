#!/bin/bash

PROGRAM_NAME="$(basename "${0}")"
ENVIRONMENTFILE="/tmp/environmentfile"

logdate() {
  date "+%Y-%m-%d %H:%M:%S"
}

log() {
  local status="${1}"
  shift

  echo >/proc/1/fd/1 2>/proc/1/fd/2 "$(logdate): ${PROGRAM_NAME}: ${status}: ${*}"

}

warning() {
  log WARNING "${@}"
}

error() {
  log ERROR "${@}"
}

info() {
  log INFO "${@}"
}

fatal() {
  log FATAL "${@}"
  exit 1
}

get_environment_value() {
  key=$1
  value=$(cat "${ENVIRONMENTFILE}" | sed -r 's/^[\w]+=/\n&/g' | awk -F= -v key="$key" '$1==key{print $2}')
  echo $value
}
