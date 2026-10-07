# Runtime half: EasyRPG Player patches

The game-side half of the showcase plugins, as patches for [EasyRPG Player](https://github.com/EasyRPG/Player). They are a **prototype** meant to be discussed with the EasyRPG team: the goal in [`docs/vision.tex`](../../docs/vision.tex) is a plugin or scripting interface in the Player itself, developed together with them, not a private fork.

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

## Building

```bash
runtime/easyrpg-player/build.sh            # prints the path of the built easyrpg-player
```

The script clones EasyRPG Player at the commit the patches are made for (pinned in the script), applies them and builds with CMake. It needs the Player's libraries; on Debian/Ubuntu:

```bash
sudo apt install libsdl2-dev libpixman-1-dev libpng-dev libfmt-dev libfreetype-dev \
    libharfbuzz-dev nlohmann-json3-dev libinih-dev libexpat1-dev libicu-dev
```

Then choose the built Player under **Test Play → Settings…** in the editor.

## Tests

`tests/test_pixel_runtime.gd` plays scripted input in the patched Player (`--replay-input`) and checks pixel positions against tile movement: stopping at the map edge and at water 2 px further (the hitbox's margin), diagonal movement, short taps, stopping at events' hitboxes (including a custom `@pixel_hitbox`), and Player Touch events. CI builds the patched Player and runs it on Linux.

```bash
xvfb-run godot --headless --path . --script res://tests/test_pixel_runtime.gd -- /path/to/patched/easyrpg-player
```
