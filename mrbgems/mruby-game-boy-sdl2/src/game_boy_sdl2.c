#include <stdint.h>
#include <string.h>

#include <SDL2/SDL.h>

#include <mruby.h>
#include <mruby/array.h>
#include <mruby/class.h>
#include <mruby/data.h>
#include <mruby/numeric.h>
#include <mruby/string.h>

enum {
  GB_BUTTON_RIGHT = 0x01,
  GB_BUTTON_LEFT = 0x02,
  GB_BUTTON_UP = 0x04,
  GB_BUTTON_DOWN = 0x08,
  GB_BUTTON_A = 0x10,
  GB_BUTTON_B = 0x20,
  GB_BUTTON_SELECT = 0x40,
  GB_BUTTON_START = 0x80
};

typedef struct {
  SDL_Window *window;
  SDL_Renderer *renderer;
  SDL_Texture *texture;
  uint32_t *pixels;
  int width;
  int height;
  int scale;
  uint8_t buttons_mask;
  mrb_bool quit_requested;
} gb_sdl2_host;

static const uint32_t gb_palette[4] = {
  0xFFE0F8D0,
  0xFF88C070,
  0xFF346856,
  0xFF081820
};

static void
gb_sdl2_host_cleanup(gb_sdl2_host *host)
{
  if (host == NULL) {
    return;
  }

  if (host->texture != NULL) {
    SDL_DestroyTexture(host->texture);
    host->texture = NULL;
  }

  if (host->renderer != NULL) {
    SDL_DestroyRenderer(host->renderer);
    host->renderer = NULL;
  }

  if (host->window != NULL) {
    SDL_DestroyWindow(host->window);
    host->window = NULL;
  }
}

static void
gb_sdl2_host_free(mrb_state *mrb, void *ptr)
{
  gb_sdl2_host *host = (gb_sdl2_host *)ptr;

  if (host == NULL) {
    return;
  }

  gb_sdl2_host_cleanup(host);

  if (host->pixels != NULL) {
    mrb_free(mrb, host->pixels);
    host->pixels = NULL;
  }

  SDL_Quit();
  mrb_free(mrb, host);
}

static const struct mrb_data_type gb_sdl2_host_type = {
  "GameBoy::SDL2Host", gb_sdl2_host_free
};

static gb_sdl2_host *
gb_sdl2_host_get(mrb_state *mrb, mrb_value self)
{
  gb_sdl2_host *host = DATA_GET_PTR(mrb, self, &gb_sdl2_host_type, gb_sdl2_host);

  if (host == NULL) {
    mrb_raise(mrb, E_RUNTIME_ERROR, "SDL2 host is closed");
  }

  return host;
}

static uint8_t
gb_button_from_key(SDL_Keycode key)
{
  switch (key) {
    case SDLK_RIGHT: return GB_BUTTON_RIGHT;
    case SDLK_LEFT: return GB_BUTTON_LEFT;
    case SDLK_UP: return GB_BUTTON_UP;
    case SDLK_DOWN: return GB_BUTTON_DOWN;
    case SDLK_z: return GB_BUTTON_A;
    case SDLK_x: return GB_BUTTON_B;
    case SDLK_RETURN: return GB_BUTTON_START;
    case SDLK_SPACE: return GB_BUTTON_SELECT;
    case SDLK_RSHIFT: return GB_BUTTON_SELECT;
    default: return 0;
  }
}

static mrb_value
gb_sdl2_host_initialize(mrb_state *mrb, mrb_value self)
{
  mrb_value title_value;
  mrb_int width;
  mrb_int height;
  mrb_int scale;
  const char *title;
  gb_sdl2_host *host;

  mrb_get_args(mrb, "Siii", &title_value, &width, &height, &scale);

  if (width <= 0 || height <= 0 || scale <= 0) {
    mrb_raise(mrb, E_ARGUMENT_ERROR, "width, height, and scale must be positive");
  }

  title = mrb_string_value_cstr(mrb, &title_value);
  host = (gb_sdl2_host *)mrb_malloc(mrb, sizeof(gb_sdl2_host));
  memset(host, 0, sizeof(*host));
  host->width = (int)width;
  host->height = (int)height;
  host->scale = (int)scale;

  if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS) != 0) {
    mrb_free(mrb, host);
    mrb_raise(mrb, E_RUNTIME_ERROR, SDL_GetError());
  }

  host->window = SDL_CreateWindow(
    title,
    SDL_WINDOWPOS_CENTERED,
    SDL_WINDOWPOS_CENTERED,
    host->width * host->scale,
    host->height * host->scale,
    SDL_WINDOW_SHOWN
  );
  if (host->window == NULL) {
    gb_sdl2_host_free(mrb, host);
    mrb_raise(mrb, E_RUNTIME_ERROR, SDL_GetError());
  }

  host->renderer = SDL_CreateRenderer(host->window, -1, SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
  if (host->renderer == NULL) {
    host->renderer = SDL_CreateRenderer(host->window, -1, SDL_RENDERER_SOFTWARE);
  }
  if (host->renderer == NULL) {
    gb_sdl2_host_free(mrb, host);
    mrb_raise(mrb, E_RUNTIME_ERROR, SDL_GetError());
  }

  host->texture = SDL_CreateTexture(
    host->renderer,
    SDL_PIXELFORMAT_ARGB8888,
    SDL_TEXTUREACCESS_STREAMING,
    host->width,
    host->height
  );
  if (host->texture == NULL) {
    gb_sdl2_host_free(mrb, host);
    mrb_raise(mrb, E_RUNTIME_ERROR, SDL_GetError());
  }

  host->pixels = (uint32_t *)mrb_malloc(mrb, sizeof(uint32_t) * host->width * host->height);
  memset(host->pixels, 0, sizeof(uint32_t) * host->width * host->height);

  DATA_PTR(self) = host;
  DATA_TYPE(self) = &gb_sdl2_host_type;

  return self;
}

static mrb_value
gb_sdl2_host_poll(mrb_state *mrb, mrb_value self)
{
  gb_sdl2_host *host = gb_sdl2_host_get(mrb, self);
  SDL_Event event;

  while (SDL_PollEvent(&event)) {
    switch (event.type) {
      case SDL_QUIT:
        host->quit_requested = TRUE;
        break;

      case SDL_KEYDOWN:
      case SDL_KEYUP:
      {
        uint8_t bit = gb_button_from_key(event.key.keysym.sym);

        if (event.type == SDL_KEYDOWN && event.key.keysym.sym == SDLK_ESCAPE) {
          host->quit_requested = TRUE;
        }

        if (bit != 0) {
          if (event.type == SDL_KEYDOWN) {
            host->buttons_mask |= bit;
          }
          else {
            host->buttons_mask &= (uint8_t)~bit;
          }
        }
        break;
      }

      default:
        break;
    }
  }

  return mrb_fixnum_value(host->buttons_mask);
}

static mrb_value
gb_sdl2_host_render(mrb_state *mrb, mrb_value self)
{
  gb_sdl2_host *host = gb_sdl2_host_get(mrb, self);
  mrb_value frame_buffer;
  mrb_int index;
  mrb_int expected_size;

  mrb_get_args(mrb, "A", &frame_buffer);
  expected_size = (mrb_int)(host->width * host->height);

  if (RARRAY_LEN(frame_buffer) < expected_size) {
    mrb_raise(mrb, E_ARGUMENT_ERROR, "frame buffer is too small");
  }

  for (index = 0; index < expected_size; index++) {
    mrb_int shade = mrb_fixnum(mrb_ary_ref(mrb, frame_buffer, index));
    if (shade < 0 || shade > 3) {
      shade = 0;
    }
    host->pixels[index] = gb_palette[shade];
  }

  if (SDL_UpdateTexture(host->texture, NULL, host->pixels, host->width * (int)sizeof(uint32_t)) != 0) {
    mrb_raise(mrb, E_RUNTIME_ERROR, SDL_GetError());
  }

  SDL_SetRenderDrawColor(host->renderer, 0, 0, 0, 255);
  SDL_RenderClear(host->renderer);
  SDL_RenderCopy(host->renderer, host->texture, NULL, NULL);
  SDL_RenderPresent(host->renderer);

  return mrb_nil_value();
}

static mrb_value
gb_sdl2_host_quit_requested(mrb_state *mrb, mrb_value self)
{
  gb_sdl2_host *host = gb_sdl2_host_get(mrb, self);
  return mrb_bool_value(host->quit_requested);
}

static mrb_value
gb_sdl2_host_delay(mrb_state *mrb, mrb_value self)
{
  mrb_int milliseconds;
  mrb_get_args(mrb, "i", &milliseconds);
  if (milliseconds < 0) {
    milliseconds = 0;
  }
  SDL_Delay((Uint32)milliseconds);
  return mrb_nil_value();
}

static mrb_value
gb_sdl2_host_close(mrb_state *mrb, mrb_value self)
{
  gb_sdl2_host *host = DATA_GET_PTR(mrb, self, &gb_sdl2_host_type, gb_sdl2_host);

  if (host != NULL) {
    gb_sdl2_host_free(mrb, host);
    DATA_PTR(self) = NULL;
  }

  return mrb_nil_value();
}

void
mrb_mruby_game_boy_sdl2_gem_init(mrb_state *mrb)
{
  struct RClass *game_boy;
  struct RClass *host_class;

  game_boy = mrb_module_get(mrb, "GameBoy");
  host_class = mrb_define_class_under(mrb, game_boy, "SDL2Host", mrb->object_class);
  MRB_SET_INSTANCE_TT(host_class, MRB_TT_DATA);

  mrb_define_method(mrb, host_class, "initialize", gb_sdl2_host_initialize, MRB_ARGS_REQ(4));
  mrb_define_method(mrb, host_class, "poll", gb_sdl2_host_poll, MRB_ARGS_NONE());
  mrb_define_method(mrb, host_class, "render", gb_sdl2_host_render, MRB_ARGS_REQ(1));
  mrb_define_method(mrb, host_class, "quit_requested?", gb_sdl2_host_quit_requested, MRB_ARGS_NONE());
  mrb_define_method(mrb, host_class, "delay", gb_sdl2_host_delay, MRB_ARGS_REQ(1));
  mrb_define_method(mrb, host_class, "close", gb_sdl2_host_close, MRB_ARGS_NONE());

  mrb_define_const(mrb, host_class, "BUTTON_RIGHT", mrb_fixnum_value(GB_BUTTON_RIGHT));
  mrb_define_const(mrb, host_class, "BUTTON_LEFT", mrb_fixnum_value(GB_BUTTON_LEFT));
  mrb_define_const(mrb, host_class, "BUTTON_UP", mrb_fixnum_value(GB_BUTTON_UP));
  mrb_define_const(mrb, host_class, "BUTTON_DOWN", mrb_fixnum_value(GB_BUTTON_DOWN));
  mrb_define_const(mrb, host_class, "BUTTON_A", mrb_fixnum_value(GB_BUTTON_A));
  mrb_define_const(mrb, host_class, "BUTTON_B", mrb_fixnum_value(GB_BUTTON_B));
  mrb_define_const(mrb, host_class, "BUTTON_SELECT", mrb_fixnum_value(GB_BUTTON_SELECT));
  mrb_define_const(mrb, host_class, "BUTTON_START", mrb_fixnum_value(GB_BUTTON_START));
}

void
mrb_mruby_game_boy_sdl2_gem_final(mrb_state *mrb)
{
  (void)mrb;
}
