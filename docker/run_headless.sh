#!/usr/bin/env bash
set -euo pipefail

ROM_PATH="${1:-test_roms/tobutobugirl/tobu.gb}"
STEP_COUNT="${2:-32}"

if [[ "${ROM_PATH}" != /* ]]; then
  ROM_PATH="/workspace/${ROM_PATH}"
fi

docker compose run --rm mruby-dev \
  bash -lc 'set -e; cd /opt/mruby && GAME_BOY_ENABLE_SDL2=1 MRUBY_CONFIG=/workspace/build_config.rb ./minirake && MRUBY_BIN=./bin/mruby && [ -x "$MRUBY_BIN" ] || MRUBY_BIN=./build/host/bin/mruby; "$MRUBY_BIN" /workspace/apps/headless_runner.rb "'"${ROM_PATH}"'" "'"${STEP_COUNT}"'"'
