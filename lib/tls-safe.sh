#!/usr/bin/env bash
# shellcheck shell=bash

# Keep optional URI parameters from returning status 1 under `set -e`.
insecure_query_hy2() {
  if [[ ${CERT_CLIENT_INSECURE:-false} == true ]]; then
    printf '&insecure=1'
  fi
  return 0
}

insecure_query_tuic() {
  if [[ ${CERT_CLIENT_INSECURE:-false} == true ]]; then
    printf '&allow_insecure=1'
  fi
  return 0
}
