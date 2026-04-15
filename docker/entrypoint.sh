#!/usr/bin/env bash
set -euo pipefail

MRUBY_ROOT="${MRUBY_ROOT:-/opt/mruby}"
MRUBY_REF="${MRUBY_REF:-master}"

if [ ! -d "${MRUBY_ROOT}/.git" ]; then
  mkdir -p "$(dirname "${MRUBY_ROOT}")"
  git clone --depth 1 --branch "${MRUBY_REF}" https://github.com/mruby/mruby.git "${MRUBY_ROOT}"
else
  git -C "${MRUBY_ROOT}" fetch --depth 1 origin "${MRUBY_REF}"
  git -C "${MRUBY_ROOT}" checkout --force FETCH_HEAD
fi

exec "$@"
