#!/usr/bin/env bash
set -euo pipefail

ROM_PATH="${1:-test_roms/tobutobugirl/tobu.gb}"
SCALE="${2:-4}"
TITLE="${3:-mruby_game_boy}"

if [[ "${ROM_PATH}" != /* ]]; then
  ROM_PATH="/workspace/${ROM_PATH}"
fi

DISPLAY_VALUE="${DISPLAY:-:0}"
XAUTH_FILE="${XAUTHORITY:-${HOME:-}/.Xauthority}"
EXTRA_ARGS=(--rm)

if [ -n "${DISPLAY_VALUE}" ]; then
  EXTRA_ARGS+=(-e "DISPLAY=${DISPLAY_VALUE}")
fi

if [ -S /tmp/.X11-unix/X0 ] || [ -d /tmp/.X11-unix ]; then
  EXTRA_ARGS+=(-v /tmp/.X11-unix:/tmp/.X11-unix)
fi

if [ -n "${XAUTH_FILE}" ] && [ -f "${XAUTH_FILE}" ]; then
  EXTRA_ARGS+=(-e "XAUTHORITY=${XAUTH_FILE}")
  EXTRA_ARGS+=(-v "${XAUTH_FILE}:${XAUTH_FILE}:ro")
fi

if [ -z "${DISPLAY:-}" ]; then
  echo "warning: DISPLAY が未設定です。必要なら 'export DISPLAY=:0' などを設定してください。" >&2
fi

docker compose run "${EXTRA_ARGS[@]}" mruby-x11 \
  bash -lc 'set -e; cd /opt/mruby && GAME_BOY_ENABLE_SDL2=1 MRUBY_CONFIG=/workspace/build_config.rb ./minirake && MRUBY_BIN=./bin/mruby && [ -x "$MRUBY_BIN" ] || MRUBY_BIN=./build/host/bin/mruby; "$MRUBY_BIN" /workspace/apps/sdl2_frontend.rb "'"${ROM_PATH}"'" "'"${SCALE}"'" "'"${TITLE}"'"'
