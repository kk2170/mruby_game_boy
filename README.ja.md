# mruby_game_boy

[English README](README.md)

pure mruby を優先した、初期段階の DMG(Game Boy) エミュレータ用ワークスペースです。

## 現在のスコープ

- DMG のみ
- エミュレータコアは pure mruby
- ブート ROM は当面、未ロード・未マップ・未実行で、Core は DMG の post-boot 状態 (`PC=0x0100`, `FF50=1`) を直接適用して開始
- ローカル開発用のスモーク ROM として TobuTobuGirl を利用

## 現在の実装状況

- CPU: まだ部分実装ですが、起動直後の実行、割り込み突入、JR、条件付き CALL、HALT bug、STOP の停止/復帰を回帰テストで確認済み
- PPU: 160x144 フレームバッファ、走査線タイミング、VBlank、BG/Window/OBJ 描画、DMG スプライト優先順位、VRAM/OAM 制限を実装
- Cartridge: ROM Only と基本的な MBC1 に対応
- APU: レジスタ状態と wave RAM を実装。NR52 の電源状態や一部チャネル状態は扱いますが、音声出力自体はまだありません
- Serial: ブート初期値、内部クロック転送完了、シリアル割り込み要求、外部クロック時に進まない挙動をテスト済み
- Joypad/DMA/Timer: FF00 入力行列、STOP 復帰に関わる入力変化、FF46 DMA、dot ベースのタイマ進行を含む構成
- Test: `mrbgems/mruby-game-boy/test/core_test.rb` に CPU / STOP / APU / Serial / PPU / DMA / Joypad まわりの回帰テストがあります

## プロジェクト構成

- `mrbgems/mruby-game-boy/` : エミュレータコア
- `mrbgems/mruby-game-boy-sdl2/` : mruby 用 SDL2 ホスト gem
- `apps/headless_runner.rb` : ROM 読み込みとスモーク実行
- `apps/frame_dump.rb` : フレームを進めて PPM を保存
- `apps/linux_x_preview.rb` : Linux/X 向けの連番 PPM 出力
- `apps/sdl2_frontend.rb` : mruby + SDL2 の対話実行フロントエンド
- `docker/` : Docker ベースの mruby / SDL2 ビルド・実行補助
- `docs/architecture.md` : 現状のアーキテクチャメモ
- `test_roms/` : ローカル配置用 ROM 置き場

## Build

mruby 側からこのワークスペースの `build_config.rb` を使ってビルドします。

```sh
../mruby/minirake
```

SDL2 フロントエンドも含める場合:

```sh
GAME_BOY_ENABLE_SDL2=1 ../mruby/minirake
```

## Run

ヘッドレス実行:

```sh
mruby apps/headless_runner.rb test_roms/tobu.gb 32
```

- 引数1: ROM パス
- 引数2: post-boot 状態から実行する CPU step 数

フレームダンプ:

```sh
mruby apps/frame_dump.rb test_roms/tobu.gb tmp/tobutobugirl/frame.ppm 30 2
```

Linux/X 向けプレビュー:

```sh
mruby apps/linux_x_preview.rb test_roms/tobu.gb tmp/linux_x_preview 20 10 3
feh --reload 0.1 tmp/linux_x_preview/frame_*.ppm
```

SDL2 フロントエンド:

```sh
mruby apps/sdl2_frontend.rb test_roms/tobu.gb 4 mruby_game_boy
```

ROM パスを省略した場合は `test_roms/**/*.gb` を走査し、1 本なら自動選択、複数ならターミナルで番号選択します。

SDL2 フロントエンドのホットキー:

- `P`: pause / resume
- `R`: ROM から Core を作り直して reset
- `F`: 1x / 2x 倍速切替
- `Esc`: 終了

`SDL_GameController` の基本対応:

- D-pad
- `A` / `B`
- `Back` = Select
- `Start` = Start

ROM 本体はリポジトリに含めていません。必要な ROM は `test_roms/...` にローカル配置してください。

## Test

ローカルの mruby checkout からテストを実行:

```sh
../mruby/minirake test
```

Docker でテストを実行:

```sh
docker compose run --rm mruby-dev \
  bash -lc 'cd /opt/mruby && GAME_BOY_ENABLE_SDL2=1 MRUBY_CONFIG=/workspace/build_config.rb ./minirake test'
```

## Docker build/run

mruby と SDL2 環境を Docker で用意する場合:

```sh
bash docker/build_mruby.sh
```

ヘッドレス実行:

```sh
bash docker/run_headless.sh test_roms/tobu.gb 32
```

Linux/X 上で SDL2 実行:

```sh
xhost +local:docker
export DISPLAY=${DISPLAY:-:0}
export XAUTHORITY=${XAUTHORITY:-$HOME/.Xauthority}
bash docker/run_sdl2.sh test_roms/tobu.gb 4 mruby_game_boy
```
