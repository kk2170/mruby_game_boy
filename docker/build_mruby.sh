#!/usr/bin/env bash
set -euo pipefail

docker compose run --rm mruby-dev \
  bash -lc 'cd /opt/mruby && GAME_BOY_ENABLE_SDL2=1 MRUBY_CONFIG=/workspace/build_config.rb ./minirake'
