#!/usr/bin/env bash
set -euo pipefail

ROM_PATH="${1:-test_roms/tobutobugirl/tobu.gb}"
SDL_TIMEOUT_SECONDS="${SDL_TIMEOUT_SECONDS:-5}"

if [[ "${ROM_PATH}" != /* ]]; then
  ROM_PATH="/workspace/${ROM_PATH}"
fi

docker compose run --rm mruby-dev \
  bash -lc 'set -euo pipefail

require_contains() {
  local output="$1"
  local expected="$2"
  local label="$3"

  case "${output}" in
    *"${expected}"*) ;;
    *)
      printf "%s\n" "${output}"
      echo "error: ${label}" >&2
      exit 1
      ;;
  esac
}

cd /opt/mruby
GAME_BOY_ENABLE_SDL2=1 MRUBY_CONFIG=/workspace/build_config.rb ./minirake

MRUBY_BIN=./bin/mruby
if [ ! -x "$MRUBY_BIN" ]; then
  MRUBY_BIN=./build/host/bin/mruby
fi

ROM_SOURCE="'"${ROM_PATH}"'"
SDL_TIMEOUT_SECONDS="'"${SDL_TIMEOUT_SECONDS}"'"

WORK_DIR=/workspace/tmp/verify_battery_save
ROM_COPY_PATH="${WORK_DIR}/$(basename "${ROM_SOURCE}")"
SAVE_PATH="${ROM_COPY_PATH}.sav"
FRAME_PATH="${WORK_DIR}/frame.ppm"
PREVIEW_DIR="${WORK_DIR}/frames"

rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"
cp "${ROM_SOURCE}" "${ROM_COPY_PATH}"

headless_output=$("$MRUBY_BIN" /workspace/apps/headless_runner.rb "${ROM_COPY_PATH}" 0)
printf "%s\n" "${headless_output}"
require_contains "${headless_output}" "saved_battery=${SAVE_PATH}" "headless_runner did not persist expected save path"
[ -f "${SAVE_PATH}" ] || { echo "error: save file not created: ${SAVE_PATH}" >&2; exit 1; }

frame_output=$("$MRUBY_BIN" /workspace/apps/frame_dump.rb "${ROM_COPY_PATH}" "${FRAME_PATH}" 1 1)
printf "%s\n" "${frame_output}"
require_contains "${frame_output}" "loaded_battery=${SAVE_PATH}" "frame_dump did not reload expected save path"
require_contains "${frame_output}" "saved_battery=${SAVE_PATH}" "frame_dump did not persist expected save path"
[ -f "${FRAME_PATH}" ] || { echo "error: frame dump not created: ${FRAME_PATH}" >&2; exit 1; }

preview_output=$("$MRUBY_BIN" /workspace/apps/linux_x_preview.rb "${ROM_COPY_PATH}" "${PREVIEW_DIR}" 0 1 1)
printf "%s\n" "${preview_output}"
require_contains "${preview_output}" "loaded_battery=${SAVE_PATH}" "linux_x_preview did not reload expected save path"
require_contains "${preview_output}" "saved_battery=${SAVE_PATH}" "linux_x_preview did not persist expected save path"
[ -f "${PREVIEW_DIR}/frame_000.ppm" ] || { echo "error: preview frame not created: ${PREVIEW_DIR}/frame_000.ppm" >&2; exit 1; }

set +e
sdl_output=$(SDL_VIDEODRIVER=dummy timeout --signal=INT "${SDL_TIMEOUT_SECONDS}" "$MRUBY_BIN" /workspace/apps/sdl2_frontend.rb "${ROM_COPY_PATH}" 1 battery_save_smoke 2>&1)
sdl_status=$?
set -e

printf "%s\n" "${sdl_output}"

if [ "${sdl_status}" -ne 0 ] && [ "${sdl_status}" -ne 124 ]; then
  echo "error: SDL2 frontend smoke failed with status ${sdl_status}" >&2
  exit 1
fi

require_contains "${sdl_output}" "loaded_battery=${SAVE_PATH}" "SDL2 frontend did not reload expected save path"
require_contains "${sdl_output}" "saved_battery=${SAVE_PATH}" "SDL2 frontend did not persist expected save path"
[ -f "${SAVE_PATH}" ] || { echo "error: save file disappeared: ${SAVE_PATH}" >&2; exit 1; }

printf "%s\n" "battery_save_smoke=ok save=${SAVE_PATH}"'
