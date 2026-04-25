#!/usr/bin/env bash
set -euo pipefail

ROM_PATH="${1:-test_roms/tobutobugirl/tobu.gb}"
EXPECTED_FRAME_LINE="frame=0 dots=135888 steps=16997 ready=true pc=015D"
EXPECTED_FRAME_SHA256="a2bdfffc1e30d5d0a6bbd7d2d9196dd013caf2381933ba5124941475a6e65dc8"

if [[ "${ROM_PATH}" != /* ]]; then
  ROM_PATH="/workspace/${ROM_PATH}"
fi

docker compose run --rm mruby-dev \
  bash -lc 'set -euo pipefail

cd /opt/mruby
GAME_BOY_ENABLE_SDL2=1 MRUBY_CONFIG=/workspace/build_config.rb ./minirake

MRUBY_BIN=./bin/mruby
if [ ! -x "$MRUBY_BIN" ]; then
  MRUBY_BIN=./build/host/bin/mruby
fi

ROM_SOURCE="'"${ROM_PATH}"'"
EXPECTED_FRAME_LINE="'"${EXPECTED_FRAME_LINE}"'"
EXPECTED_FRAME_SHA256="'"${EXPECTED_FRAME_SHA256}"'"

WORK_DIR=/workspace/tmp/verify_tobutobugirl_compat
ROM_COPY_PATH="${WORK_DIR}/$(basename "${ROM_SOURCE}")"
FRAME_PATH="${WORK_DIR}/frame.ppm"

rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"
cp "${ROM_SOURCE}" "${ROM_COPY_PATH}"

output=$("$MRUBY_BIN" /workspace/apps/frame_dump.rb "${ROM_COPY_PATH}" "${FRAME_PATH}" 1 1)
printf "%s\n" "${output}"

case "${output}" in
  *"${EXPECTED_FRAME_LINE}"*) ;;
  *)
    echo "error: unexpected Tobu frame summary" >&2
    exit 1
    ;;
esac

[ -f "${FRAME_PATH}" ] || { echo "error: frame output missing: ${FRAME_PATH}" >&2; exit 1; }

frame_sha=$(sha256sum "${FRAME_PATH}" | cut -d" " -f1)

if [ "${frame_sha}" != "${EXPECTED_FRAME_SHA256}" ]; then
  echo "error: unexpected Tobu frame hash: ${frame_sha}" >&2
  exit 1
fi

printf "%s\n" "tobutobugirl_compat=ok sha256=${frame_sha}"'
