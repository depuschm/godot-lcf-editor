# Runtime half: EasyRPG Player patches

The game-side half of the showcase plugins (pixel movement and screen shaders), as patches for [EasyRPG Player](https://github.com/EasyRPG/Player). They are a **prototype** meant to be discussed with the EasyRPG team: the goal in [`docs/vision.tex`](../../docs/vision.tex) is a plugin or scripting interface in the Player itself, developed together with them, not a private fork.

**License:** these patches modify EasyRPG Player and are licensed like it, under the GNU General Public License v3 or later (see the Player's `COPYING`). The rest of this repository is MIT.

## Pixel movement — `0001-pixel-movement.patch`

The hero walks in pixel steps (including diagonals) instead of whole tiles and collides through a hitbox:

- **Opt-in per game.** Only when the game folder holds `lcf-plugins/pixel_movement.json` with `"enabled": true` (written by the editor's *Pixel Movement* tab). Every other game plays exactly as before.
- **Hero hitbox** from that file: `{ "enabled": true, "hero": { "x": 2, "y": 4, "width": 12, "height": 12 } }`, in pixels within the hero's 16 × 16 tile.
- **Collision** with the map uses the Player's tile passability rules (the same check as a step between two tiles, including the four passable directions of each tile), applied whenever the hitbox enters a new row or column of tiles; with events on the hero's layer through their hitboxes. Events have the whole tile as hitbox unless the first comments of their active page contain `@pixel_hitbox x, y, width, height` (set in the editor's *Hitbox* panel).
- **Game logic stays tile based.** The hero's tile is the tile under the middle of its hitbox, so Player Touch / Event Touch, Action Button, terrain, encounters, steps and teleports work unchanged. Bumping into a touch event starts it.
- **Comment commands** (with EasyRPG extensions on, or in DynRPG mode): `@pixel_movement 1` / `0` turns it on or off for the session; `@pixel_move character, dx, dy` moves the hero (10001) by pixels with collision, or shifts an event's sprite.

The change to the Player is small: a pixel offset per character that is added where sprites are positioned (`Game_Character::GetSpriteX/Y`), a pixel walking step in `Game_Player` that replaces the tile step when pixel movement is on, and `src/pixel_movement.{h,cpp}` with the settings, hitboxes, collision and a DynRPG-style plugin for the commands.

**Limits of the prototype:** only the hero moves in pixels (events move by tiles; `@pixel_move` on an event only shifts its sprite); not on looping maps; vehicles, jumps and move routes are tile based (the hero snaps to its tile first); the pixel offset is not stored in save games (the hero snaps to its tile after loading).

## Screen shaders — `0002-screen-shaders.patch`

A GLSL post-process pass over the finished frame, chosen per map (applied on top of the pixel movement patch; `build.sh` applies both):

- **Opt-in per game.** Only when the game folder holds `lcf-plugins/shaders.json` (written by the editor's *Screen Shader* dock). The Player then asks SDL for its OpenGL renderer; every other game uses the renderer it always did.
- **Settings:** `{ "default": { "shader": "crt" }, "maps": { "3": { "shader": "night", "params": { "strength": 0.75 } } } }`. A map without an entry uses the default (which also covers the title screen); `"none"` turns the default off for a map.
- **Shader files** are `Shader/<name>.glsl` in the game folder: GLSL 1.20 that defines `vec4 effect(vec2 uv)` and may call `pixel(uv)` (the screen, uv 0..1 from the top left) and use `resolution` (320 × 240) and `time` (seconds). Parameters are uniforms with defaults in a trailing comment, e.g. `uniform float strength; // 0.7 [0, 1]`. Compile errors go to the log with the file's line numbers, and the game is drawn without the shader.
- **Comment commands** (with EasyRPG extensions on, or in DynRPG mode): `@shader "name"` uses a shader from now on (`"none"` for none, `""` to go back to the map's own); `@shader_param "name", value, divisor` sets a parameter of the shader in use to value / divisor (`V12` for a variable).
- **How it draws:** the Player still renders the frame on the CPU. In `Sdl2Ui::UpdateDisplay` the final copy of the game texture to the window is replaced by a quad drawn with the shader on the OpenGL context of SDL's renderer (`SDL_RenderFlush`, `SDL_GL_BindTexture`, GL state saved and restored around it). OpenGL functions are loaded through `SDL_GL_GetProcAddress`, so the Player does not link against OpenGL. The code is in `src/screen_shader.{h,cpp}` (settings, files, commands) and `src/platform/sdl/sdl2_shader.{h,cpp}` (the pass).

**Limits of the prototype:** SDL2 builds on desktop only (not SDL3, which is now the Player's default on desktop, nor the console ports); one pass; the bilinear scaling option is skipped while a shader is on; `@shader` and `@shader_param` are not stored in save games; when the Player starts without a game (the game browser), the game's shaders need a restart because the renderer is already chosen.

## Download

Every [release](https://github.com/depuschm/godot-lcf-editor/releases) has the patched Player ready to run for Windows (64-bit) and Linux (built on Ubuntu 24.04), with the complete source as `easyrpg-player-patched-source.tar.gz`. Unpack the zip's `easyrpg-player` folder into the Godot project you use the editor in, and Test Play runs it when no other Player is chosen in its settings. The builds come from CI (`.github/workflows/build.yml`), which runs the tests below with them on both systems; the version string ends in “(godot-lcf-editor patches)”.

## Building

```bash
runtime/easyrpg-player/build.sh            # prints the path of the built easyrpg-player
```

The script clones EasyRPG Player and liblcf at the commits the patches are made for (pinned in the script), applies the patches and builds with CMake; `package.sh` then makes the download zips. It needs the Player's libraries; on Debian/Ubuntu:

```bash
sudo apt install libsdl2-dev libpixman-1-dev libpng-dev libfmt-dev libfreetype-dev \
    libharfbuzz-dev nlohmann-json3-dev libinih-dev libexpat1-dev libicu-dev \
    libmpg123-dev libsndfile1-dev libvorbis-dev libopusfile-dev libspeexdsp-dev libasound2-dev
```

On Windows the script runs in Git Bash with Visual Studio and [vcpkg](https://vcpkg.io); the CI workflow shows the libraries to install and the `PLAYER_CMAKE_ARGS` to pass.

Then choose the built Player under **Test Play → Settings…** in the editor.

The patches are applied in order (`0002` builds on lines `0001` touches).

## Tests

`tests/test_pixel_runtime.gd` plays scripted input in the patched Player (`--replay-input`) and checks pixel positions against tile movement: stopping at the map edge and at water 2 px further (the hitbox's margin), diagonal movement, short taps, stopping at events' hitboxes (including a custom `@pixel_hitbox`), and Player Touch events. CI builds the patched Player and runs it on Linux.

`tests/test_shader_runtime.gd` runs the demo with shaders chosen per map, by default and by the comment commands, and checks the colours of the shaded frame (the patched Player writes it to `$EASYRPG_SHADER_CAPTURE` at game frame `$EASYRPG_SHADER_CAPTURE_FRAME`, a test hook). It needs OpenGL, e.g. Mesa under Xvfb.

```bash
xvfb-run godot --headless --path . --script res://tests/test_pixel_runtime.gd -- /path/to/patched/easyrpg-player
xvfb-run godot --headless --path . --script res://tests/test_shader_runtime.gd -- /path/to/patched/easyrpg-player
```
