# Pure mruby Game Boy architecture

## Current target

- DMG only
- Boot ROM skipped for now
- Post-boot DMG register state applied directly
- Cartridge support starts with ROM Only and basic MBC1

## Main objects

### `GameBoy::Core`

Owns the machine graph and advances the system.

### `GameBoy::CPU`

- SM83/LR35902 register state
- partial opcode implementation
- interrupt entry
- returns elapsed dots per executed step

### `GameBoy::Bus`

- central address decoder
- owns WRAM / HRAM / generic IO stub space
- routes accesses to cartridge, PPU, timer, joypad, DMA, interrupts

### `GameBoy::Cartridge`

- ROM normalization
- header parsing
- mapper selection
- currently `RomOnly` and `MBC1`

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
- framebuffer upload/present

### `GameBoy::Timer`

- DIV / TIMA / TMA / TAC
- simple dot-driven timer model

### `GameBoy::Joypad`

- FF00 matrix handling
- active-low input behavior

### `GameBoy::DMA`

- FF46 OAM DMA trigger
- currently copies immediately and keeps a transfer-active timer

## Timing unit

The core uses **dots** as the internal shared timing unit.

- 456 dots per scanline
- 70224 dots per frame

CPU steps return dots, then other devices consume the same dot count.

## Boot strategy

For now the core starts from a DMG post-boot state instead of running a boot ROM.
This keeps the first pure-mruby milestone focused on:

- cartridge loading
- bus layout
- timing skeleton
- early CPU execution
- framebuffer ownership

## Smoke ROM

Default ROM:

- `test_roms/tobutobugirl/tobu.gb`

This is only used as a local development ROM and early stepping target.

## Linux/X first output path

The project still keeps the emulation core pure mruby.
For the first visible output step, the framebuffer is exported as **PPM**.

- no native GUI binding required inside the core
- works with plain file I/O
- viewable from Linux/X using `feh`, `display`, `xdg-open`, etc.

For interactive Linux/X execution, the current plan is:

- keep the emulator core in pure mruby
- provide SDL2 only as a host-side mrbgem (`mruby-game-boy-sdl2`)
- prefer Docker to supply the SDL2 development environment and mruby build toolchain

The current verification path is:

- headless runner under mruby in Docker
- frame dump under mruby in Docker
- SDL2 frontend under mruby with `SDL_VIDEODRIVER=dummy`
- optional real X11 execution via `docker/run_sdl2.sh`
- targeted regression checks for sprite priority, HALT bug, and VRAM/OAM access gating
