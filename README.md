# mruby_game_boy

[Japanese README](README.ja.md)

Pure mruby first Game Boy emulator workspace.

## Current scope

- DMG only
- pure mruby only
- boot ROM is currently not loaded, mapped, or executed; core starts from direct DMG post-boot state (`PC=0x0100`, `FF50=1`)
- headless core first
- TobuTobuGirl ROM used as the default smoke ROM

## Current implementation status

- CPU execution is still partial, but boot-state startup, interrupt entry, JR, conditional CALL, HALT bug, and STOP stop/wake behavior are covered by regression tests
- PPU includes scanline timing, VBlank, a 160x144 framebuffer, BG/Window/OBJ rendering, DMG sprite priority rules, and VRAM/OAM access restrictions
- Cartridge support includes ROM Only, basic MBC1, and basic MBC2
- Battery-backed cartridges persist app/frontend saves as `"<rom_path>.sav"`
- APU currently models register state and wave RAM, including NR52 power/status handling, but does not produce audio yet
- Serial covers boot-state registers, internal clock transfer completion, interrupt request timing, and the external-clock no-progress case
- Targeted tests live in `mrbgems/mruby-game-boy/test/core_test.rb` for CPU, STOP, APU, Serial, PPU, DMA, and Joypad behavior

## Project layout

- `mrbgems/mruby-game-boy/` : emulator core
- `mrbgems/mruby-game-boy-sdl2/` : SDL2 host gem for mruby
- `apps/headless_runner.rb` : simple ROM loader / smoke runner
- `apps/frame_dump.rb` : run frames and save a PPM image
- `apps/linux_x_preview.rb` : dump frame sequence for Linux/X image viewers
- `apps/sdl2_frontend.rb` : mruby + SDL2 interactive frontend
- `docker/` : Docker-based mruby + SDL2 workflow
- `docs/architecture.md` : current architecture notes
- `test_roms/` : local ROM placement (not committed)

## Build mruby

```sh
../mruby/minirake
```

or from an mruby checkout that points to this workspace config.

If you want the **mruby SDL2 frontend**, build with:

```sh
GAME_BOY_ENABLE_SDL2=1 ../mruby/minirake
```

## Run

Run the headless runner:

```sh
mruby apps/headless_runner.rb test_roms/tobu.gb 32
```

- arg1: ROM path
- arg2: number of CPU steps to execute after boot-state setup

Dump a frame as PPM:

```sh
mruby apps/frame_dump.rb test_roms/tobu.gb tmp/tobutobugirl/frame.ppm 30 2
```

Linux/X preview flow:

```sh
mruby apps/linux_x_preview.rb test_roms/tobu.gb tmp/linux_x_preview 20 10 3
feh --reload 0.1 tmp/linux_x_preview/frame_*.ppm
```

Run the SDL2 frontend:

```sh
mruby apps/sdl2_frontend.rb test_roms/tobu.gb 4 mruby_game_boy
```

If you omit the ROM path, the frontend will scan `test_roms/**/*.gb`, auto-pick a single match, or let you choose by number in the terminal.

SDL2 frontend hotkeys:

- `P`: pause / resume
- `R`: reset by recreating the core from the ROM
- `F`: toggle 1x / 2x speed
- `Esc`: quit

Supported pads via `SDL_GameController`:

- D-pad
- `A` / `B`
- `Back` = Select
- `Start` = Start

If you built inside Docker, the mruby binary is typically here:

```sh
/opt/mruby/bin/mruby
```

ROM files are not included in the public repository. Place your local ROMs under `test_roms/...` such as `test_roms/tobu.gb`.

Battery-backed cartridges use `"<rom_path>.sav"`; `apps/headless_runner.rb`, `apps/frame_dump.rb`, `apps/linux_x_preview.rb`, and `apps/sdl2_frontend.rb` will load that file on startup and save it again on exit/reset.

PPM is used because it keeps the emulator core pure mruby and can still be viewed easily on Linux/X.

## Test

Run the mruby test suite from your local mruby checkout:

```sh
../mruby/minirake test
```

## Remaining work

### Tomorrow checklist (roughly the last 6%)

- add at least one more timing-sensitive ROM-driven regression

### After that

- MBC variants beyond the current ROM Only / basic MBC1 / basic MBC2 support
- broader ROM-driven compatibility and timing regression coverage

## Docker build/run (recommended)

First build the image and mruby toolchain:

```sh
bash docker/build_mruby.sh
```

Run the headless smoke script inside Docker:

```sh
bash docker/run_headless.sh test_roms/tobu.gb 32
```

Run the SDL2 frontend on Linux/X from Docker:

```sh
xhost +local:docker
export DISPLAY=${DISPLAY:-:0}
export XAUTHORITY=${XAUTHORITY:-$HOME/.Xauthority}
bash docker/run_sdl2.sh test_roms/tobu.gb 4 mruby_game_boy
```

Run the mruby test suite inside Docker:

```sh
docker compose run --rm mruby-dev \
  bash -lc 'cd /opt/mruby && GAME_BOY_ENABLE_SDL2=1 MRUBY_CONFIG=/workspace/build_config.rb ./minirake test'
```

Run the battery-save smoke regression inside Docker:

```sh
bash docker/verify_battery_save.sh test_roms/tobutobugirl/tobu.gb
```

The script copies the ROM under `tmp/verify_battery_save/` so it can create and reload `"<rom_path>.sav"` without touching a save next to your original ROM.

The Docker setup clones `mruby` into a named Docker volume on first run and keeps the emulator core repository mounted from the host.
`docker/run_sdl2.sh` will also mount `/tmp/.X11-unix` and `.Xauthority` when available.

## SDL2 frontend

`apps/sdl2_frontend.rb` is intended for **mruby**, not CRuby.
It relies on the local `mruby-game-boy-sdl2` mrbgem, which wraps a minimal subset of SDL2 in C.

It is also smoke-testable without a real X server:

```sh
docker compose run --rm mruby-dev \
  bash -lc 'cd /opt/mruby && SDL_VIDEODRIVER=dummy timeout 5 ./bin/mruby /workspace/apps/sdl2_frontend.rb /workspace/test_roms/tobu.gb 1'
```
