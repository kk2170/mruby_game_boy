module GameBoy
  module Constants
    SCREEN_WIDTH = 160
    SCREEN_HEIGHT = 144

    DOTS_PER_LINE = 456
    DOTS_PER_FRAME = 70_224

    INT_VBLANK = 0
    INT_LCD = 1
    INT_TIMER = 2
    INT_SERIAL = 3
    INT_JOYPAD = 4
  end
end
