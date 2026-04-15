# mruby_game_boy

Pure mruby first Game Boy emulator workspace.

## Current scope

- DMG only
- pure mruby only
- headless core first
- TobuTobuGirl ROM used as the default smoke ROM

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

## Docker build/run (recommended)

First build the image and mruby toolchain:

```sh
bash docker/build_mruby.sh
```

Run the headless smoke script inside Docker:

```sh
bash docker/run_headless.sh test_roms/tobutobugirl/tobu.gb 32
```

Run the SDL2 frontend on Linux/X from Docker:

```sh
xhost +local:docker
export DISPLAY=${DISPLAY:-:0}
export XAUTHORITY=${XAUTHORITY:-$HOME/.Xauthority}
bash docker/run_sdl2.sh test_roms/tobutobugirl/tobu.gb 4 mruby_game_boy
```

The Docker setup clones `mruby` into a named Docker volume on first run and keeps the emulator core repository mounted from the host.
`docker/run_sdl2.sh` will also mount `/tmp/.X11-unix` and `.Xauthority` when available.

## Run the headless runner

```sh
mruby apps/headless_runner.rb
```

If you built inside Docker, the mruby binary is typically here:

```sh
/opt/mruby/bin/mruby
```

Optional arguments:

```sh
mruby apps/headless_runner.rb test_roms/tobutobugirl/tobu.gb 32
```

- arg1: ROM path
- arg2: number of CPU steps to execute after boot-state setup

The current CPU implementation is intentionally partial. It is enough for ROM loading and early bootstrap stepping, but not a full emulator yet.

TobuTobuGirl uses an MBC1 cartridge (`0x03`), so the scaffold already includes a basic MBC1 mapper.

ROM 本体は公開リポジトリには含めていません。ローカルで `test_roms/tobutobugirl/tobu.gb` などに配置して使ってください。

## Dump a frame as PPM

```sh
mruby apps/frame_dump.rb test_roms/tobutobugirl/tobu.gb tmp/tobutobugirl/frame.ppm 30 2
```

## Linux/X preview flow

```sh
mruby apps/linux_x_preview.rb test_roms/tobutobugirl/tobu.gb tmp/linux_x_preview 20 10 3
feh --reload 0.1 tmp/linux_x_preview/frame_*.ppm
```

PPM is used because it keeps the emulator core pure mruby and can still be viewed easily on Linux/X.

## SDL2 frontend

`apps/sdl2_frontend.rb` is intended for **mruby**, not CRuby.
It relies on the local `mruby-game-boy-sdl2` mrbgem, which wraps a minimal subset of SDL2 in C.

It is also smoke-testable without a real X server:

```sh
docker compose run --rm mruby-dev \
  bash -lc 'cd /opt/mruby && SDL_VIDEODRIVER=dummy timeout 5 ./bin/mruby /workspace/apps/sdl2_frontend.rb /workspace/test_roms/tobutobugirl/tobu.gb 1'
```
