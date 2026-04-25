# Pure mruby Game Boy architecture

## Current target

- DMG only
- Boot ROM is currently not loaded, mapped, or executed
- DMG post-boot register state is applied directly, including `PC=0x0100` and `FF50=1`
- Cartridge support starts with ROM Only, basic MBC1, basic MBC2, and basic MBC3 with latchable RTC register storage plus basic live RTC progression from a host time source

## Main objects

### `GameBoy::Core`

Owns the machine graph and advances the system.

### `GameBoy::CPU`

- SM83/LR35902 register state
- partial opcode implementation
- interrupt entry
- HALT / STOP state handling
- returns elapsed dots per executed step

### `GameBoy::Bus`

- central address decoder
- owns WRAM / HRAM / generic IO stub space
- routes accesses to cartridge, PPU, timer, joypad, DMA, interrupts, APU, serial
- uses `io_stub` as the fallback for unimplemented `FF00..FF7F` registers; boot defaults should live on concrete devices first and only fall back to `io_stub`

### `GameBoy::Interrupts`

- owns `IF` / `IE`
- tracks serviceable interrupts and interrupt vector selection

### `GameBoy::APU`

- minimal audio-register device for `FF10..FF3F`
- stores APU register state and wave RAM
- exposes `NR52` power/status behavior needed by current tests
- returns `0xFF` for unused hole registers and ignores writes there

### `GameBoy::Serial`

- minimal `SB` / `SC` device for `FF01..FF02`
- keeps boot-state values on the real device instead of the IO stub
- implements internal-clock transfer completion after 4096 dots
- requests the serial interrupt when the transfer completes

### `GameBoy::BootState`

- applies DMG post-boot CPU / interrupt / timer / joypad / DMA / APU / serial / PPU state directly
- keeps boot defaults on concrete devices first; `BootState::IO_DEFAULTS` is a fallback path and is currently mostly APU-facing, with the non-APU stub defaults effectively empty

### `GameBoy::Cartridge`

- ROM normalization
- header parsing
- mapper selection
- currently `RomOnly`, `MBC1`, `MBC2`, and `MBC3`; timer-tagged MBC3 carts can store/latch RTC registers and advance them from a host time source

### `GameBoy::PPU`

- VRAM / OAM
- LCDC / STAT / scroll / palette registers
- scanline timing
- VBlank interrupt generation
- BG / Window / simple OBJ renderer into a 160x144 framebuffer
- DMG sprite priority (smaller X first, same X then earlier OAM)
- BG over OBJ masking after object-priority resolution
- VRAM / OAM access restrictions on active PPU modes

### `GameBoy::SDL2Host`

- optional host-only mrbgem
- wraps a small subset of SDL2 from C for mruby
- window creation
- keyboard polling
- hotkey mask polling for pause / reset / speed toggle
- basic `SDL_GameController` button support (D-pad / A / B / Back / Start)
- framebuffer upload/present

### `GameBoy::Timer`

- DIV / TIMA / TMA / TAC
- dot-driven system counter model
- selected DIV bit falling edge increments TIMA
- DIV/TAC writes may tick TIMA early
- TIMA reload / interrupt occur one M-cycle after overflow

### `GameBoy::Joypad`

- FF00 matrix handling
- active-low input behavior

### `GameBoy::DMA`

- FF46 OAM DMA trigger
- transfers OAM progressively over 640 dots

## Timing unit

The core uses **dots** as the internal shared timing unit.

- 456 dots per scanline
- 70224 dots per frame

CPU steps return dots, then other devices consume the same dot count.

Current step flow:

- `CPU.step -> DMA.tick -> Timer.tick -> Serial.tick -> PPU.tick`

Before `CPU.step`, `Core#step` also checks the joypad wake path for STOP and calls `CPU#wake_stop` when the selected-line wake condition or a queued falling edge is present.

## Boot strategy

The core starts from a DMG post-boot state instead of running a boot ROM.
For now, the boot ROM is not loaded, not mapped at `0000..00FF`, and not executed.
`BootState.apply!` writes the post-boot state directly, including `PC=0x0100`, and sets `FF50=1` via the bus latch.
`Bus#load_boot_stub_io` remains only as a fallback path for any remaining unimplemented IO defaults; boot defaults should prefer concrete devices first, and today `BootState::IO_DEFAULTS` is mainly used for APU-related defaults.

This keeps the pure-mruby milestone focused on:

- cartridge loading
- bus layout
- timing skeleton
- early CPU execution
- framebuffer ownership

This policy is unchanged: boot ROM execution/mapping is deferred, `FF50` is currently a compatibility latch only, and the machine should still start from a consistent post-boot DMG state that matches the currently implemented devices.

## STOP behavior

- `STOP` consumes the trailing byte and then sets the CPU into a stopped state
- while stopped, `CPU.step` returns `0` dots and no device ticks advance further for that step
- `Core#step` owns wake coordination with `Joypad`; it checks both the current selected-line low state and queued falling edges
- a matching wake clears STOP before the next CPU step, so the next step can either execute the next opcode or service the joypad interrupt first
- `Core#run_frame` exits early when a step returns `0`, so a stopped CPU does not spin forever waiting for a frame

## Smoke ROM

Default ROM:

- `test_roms/tobutobugirl/tobu.gb`

This is only used as a local development ROM and early stepping target.

## Linux/X output paths

The project keeps the emulation core pure mruby.
The framebuffer is exported as **PPM** for the simplest visible output path.

- no native GUI binding required inside the core
- works with plain file I/O
- viewable from Linux/X using `feh`, `display`, `xdg-open`, etc.

Current Linux/X-facing paths are:

- keep the emulator core in pure mruby
- provide SDL2 as a host-side mrbgem (`mruby-game-boy-sdl2`)
- use Docker to supply the SDL2 development environment and mruby build toolchain
- use `apps/frame_dump.rb` for headless frame export
- use `apps/linux_x_preview.rb` for sequential PPM preview output
- use `apps/sdl2_frontend.rb` for the SDL2 windowed path

The current verification path is:

- headless runner under mruby in Docker
- frame dump under mruby in Docker
- battery-save smoke regression via `docker/verify_battery_save.sh`
- TobuTobuGirl ROM-driven compatibility regression via `docker/verify_tobutobugirl_compat.sh`
- SDL2 frontend under mruby with `SDL_VIDEODRIVER=dummy`
- optional real X11 execution via `docker/run_sdl2.sh`
- regression coverage in `mrbgems/mruby-game-boy/test/core_test.rb` for:
  - boot/post-boot register state
  - bus routing for APU, serial, DMA, VRAM/OAM gating, and PPU register behavior
  - serial internal/external clock minimum behavior and interrupt timing
  - APU wave RAM, `NR52` power/status behavior, and unused-hole handling
  - PPU sprite priority rules and BG-over-OBJ masking
  - CPU HALT bug, STOP enter/wake behavior, and `Core#run_frame` early exit on STOP
  - selected CPU control-flow instructions such as `JR` and conditional `CALL`

## Frontend convenience roadmap

Phase 1 adds frontend-side ROM selection, pause/reset, a 1x/2x speed toggle, and basic controller support without changing core timing ownership.
After this phase, the next priority returns to compatibility improvements.

Short follow-up notes:

- save state support
- key / pad config UI
- recent ROM list
- compatibility follow-up after Phase 1
