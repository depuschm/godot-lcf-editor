# godot-lcf-editor

[![Build and test](https://github.com/depuschm/godot-lcf-editor/actions/workflows/build.yml/badge.svg)](https://github.com/depuschm/godot-lcf-editor/actions/workflows/build.yml)

Godot editor for RPG Maker 2000/2003 projects (LCF format), built on [liblcf](https://github.com/EasyRPG/liblcf). Extensible through plugins, playtested with [EasyRPG Player](https://github.com/EasyRPG/Player).

> **Status: early prototype.** The editor plugin opens an existing RPG Maker 2000/2003 project, lets you paint its maps, edit its events and browse and edit its whole database inside Godot. Dialogs for individual event commands come next — see the [roadmap](#roadmap). Keep backups of your projects while trying it.

## Vision

RPG Maker 2000/2003 still has an active community, but its editor and runtime are closed, Windows-only programs. Existing patches (Maniacs, DynRPG, Destiny) add fixed feature sets; none lets users extend the **editor itself**.

This project aims to change that:

- **Godot as the editor.** Maps, database and events are edited in Godot, and projects stay in the original RPG Maker 2000/2003 format.
- **EasyRPG Player as the runtime.** Games are played and tested with the open-source reimplementation of the RPG Maker runtime.
- **Everything is a plugin.** A feature such as pixel-perfect movement or shader support ships as an *editor half* (dialogs, tools, previews) and a *runtime half* (the mechanic in the player). Event command dialogs are generated from data, so a plugin registers a new command and gets its dialog for free.

<p align="center">
  <img src="docs/images/architecture.svg" alt="Architecture: a plugin has an editor half that extends the Godot editor and a runtime half that extends EasyRPG Player. The editor reads and writes RPG Maker 2000/2003 project files through liblcf; EasyRPG Player loads the same files and is launched for Test Play." width="760">
</p>

The full vision, the existing landscape and the options considered are in [`docs/vision.tex`](docs/vision.tex).

## What works today

![The Godot editor with the LCF Project dock on the left and the LCF Editor screen's Map tab: the World map with a newly painted pond (with shoreline) and dirt path, the layer and tool buttons (Lower layer, Rectangle selected), "Unsaved changes" with Save map and Revert, and the tile palette on the right with the dirt path autotile selected.](docs/images/editor-map.png)

- Open an RPG Maker 2000 or 2003 project folder from the **LCF Project** dock.
- Detects engine version (2000/2003) and text encoding (from `RPG_RT.ini` or by analysing the database).
- Shows the map tree, including areas, and basic facts per map.
- Selecting a map opens it in the **LCF Editor** screen (next to 2D, 3D and Script), **Map** tab: lower and upper layer with the project's chipset, including ground autotiles, water with shores and deep-water edges, and event markers. Zoom with the mouse wheel, pan with the middle mouse button (or Space + drag); the status line shows the tile IDs under the cursor.
- **Painting maps:** pick a tile in the palette (right of the map) and paint with **Pencil**, **Rectangle** or **Fill** on the lower or upper layer; right-click or **Pick** takes the tile under the cursor. Autotiles and water connect automatically: the painted tiles and their neighbours get the variants RPG Maker would choose, including shores and deep-water edges. Hold **Shift** to place the exact tile without autotiling. Every stroke can be undone with Godot's undo (Ctrl+Z).
- **Events:** the **Events** layer button switches the map to event editing. Click an event to select it, drag it to move it, double-click it to open the **event editor**, or double-click an empty cell to create one (named and numbered like RPG Maker does). Right-click for New, Edit, Copy, Paste and Delete; Delete, Ctrl+C and Ctrl+V work too.
- **Event editor:** name, pages as tabs (New page, Copy page, Delete page), every page setting (conditions, graphic, movement, trigger, layer, …) with readable choices such as “Action Button” or “Stay Still”, and the page's command list as RPG Maker shows it (“◆Show Message: …”). Commands can be inserted, edited and deleted; every command is editable as raw data (code, indent, text, parameters) with a searchable list of all commands, so nothing is out of reach. Every change can be undone with Ctrl+Z in the map.
- **Saving maps** works like the database: **Save map** makes a backup, writes a temporary file, reads it back and compares it before replacing `Map####.lmu`; **Revert** drops unsaved changes, and Godot asks about unsaved maps when it closes.
- The **Database** tab shows every section of the database (actors, classes, skills, items, enemies, troops, states, vocabulary, system, common events, switches, variables, …). Every field of the selected entry is listed, nested structures can be expanded, event commands appear by name with their indentation, and references such as `class_id` or `switch_id` show the name they point to. Fields come straight from liblcf's own description of the format, so new fields (including Maniacs and EasyRPG extensions) appear automatically.
- **Editing the database:** double-click a field to change it (checkbox for yes/no, number box, text field, list of named choices). **Save** writes `RPG_RT.ldb`; **Revert** drops unsaved changes, and Godot warns about unsaved changes when it closes. **Common events** get the same command list as map events.
- **Safe saving:** before every save the current file is copied to a backup (the newest 20 are kept in Godot's user data folder, under `backups/`). The new database is written to a temporary file, read back and compared before it replaces the original. The save counter is increased like RPG Maker does.
- **Byte-exact round trips:** databases saved by RPG Maker 2000 and 2003 (and PowerMode2003) are written back byte for byte when nothing was changed, and every entry passes through the editor without changing a byte (tested with [EasyRPG's TestGame](https://github.com/EasyRPG/TestGame), 760–890 entries per game). Databases from the Maniacs Patch or EasyRPG can contain empty or unknown fields that liblcf leaves out; the editor detects this when a project opens, shows a warning, and asks before saving.
- Chipsets in PNG, BMP and RPG Maker's XYZ format, with palette colour 0 transparent as in RPG Maker.
- Exposes everything to GDScript through `LcfProject` and `LcfChipset`:

```gdscript
var project := LcfProject.new()
if project.load("C:/Games/MyRpg") == OK:
    var map := project.get_map(1)  # width, height, lower, upper, events, chipset_id
    var file := project.find_image("ChipSet", project.get_chipset(map.chipset_id).file)
    var chipset := LcfChipset.new()
    if chipset.load(file) == OK:
        var tile: Image = chipset.render_tile(map.lower[0])
    for entry in project.get_database_entries("actors"):  # also "skills", "items", ...
        print(entry.id, ": ", entry.name)
    for event in map.events:  # id, name, x, y, page_count
        for command in project.get_map_event_commands(1, event.id, 0):  # code, indent, string, parameters
            print(LcfProject.get_event_command_name(command.code), " ", command.string)
```

![The Map tab on the Events layer with the chest in the demo's house selected, and the event editor open on it: name “Chest”, tabs for page 1 and 2, the page settings (Stay Still, Action Button, Same as Hero, …) and the command list with Play Sound, Show Message, Change Gold and Control Switches.](docs/images/editor-events.png)

![The Database tab with the demo's actor "Hero" selected: its fields on the right, the title just changed to "Knight of the Lake", "Unsaved changes" with Save and Revert buttons at the top, references such as class_id shown as "1 · Warrior", and the number editor open for final_level.](docs/images/editor-database.png)

The autotile and water rules (`extension/src/tile_rules.h`) are our own implementation of the chipset format. Drawing was checked against EasyRPG Player's reference tables for every ground autotile, water combination and animation frame. Painting was checked against maps saved by the real RPG Maker editor (EasyRPG's TestGame): recomputing every autotile reproduces the stored variants on all regularly painted maps; the differences are in test rooms where variants were placed by hand on purpose. Painting only recomputes the painted tiles and their neighbours, so hand-placed variants elsewhere stay as they are.

Untouched maps also save back byte for byte: all maps of TestGame-2003, -Maniacs and -EasyRPG and 77 of 78 maps of TestGame-2000 (the remaining one, and any other map where that is not the case, makes the editor ask before saving). Events go through the same exact path: every event of every TestGame (3,355 events with 54,139 commands in TestGame-2000 alone) and every common event passes through the editor without changing a byte.

**Not yet:** dialogs for individual event commands (they are edited as raw data for now), event graphics on the map, move route editing, adding or removing database entries, map properties (size, chipset), RTP graphics (chipsets must be inside the project), tile animation.

## Repository layout

```
project.godot              Open this folder in Godot 4.5+
addons/lcf_editor/         Editor plugin (GDScript) + the GDExtension's binaries
extension/                 C++ GDExtension wrapping liblcf (CMake)
thirdparty/liblcf/         git submodule – RPG Maker 2000/2003 file formats
thirdparty/godot-cpp/      git submodule – Godot C++ bindings
thirdparty/libexpat/       git submodule – XML parser liblcf uses to read edited entries
demo/                      Tiny generated test project with its own chipset (no RPG Maker assets)
tests/                     Headless smoke and round-trip tests, a map-to-PNG renderer
tools/                     Demo generators: chipset (Python), maps from text grids (C++)
docs/                      Vision document and README images
```

## Download

Every push is built and tested on **Windows** and **Linux** by [GitHub Actions](https://github.com/depuschm/godot-lcf-editor/actions/workflows/build.yml): the smoke test, the round-trip test on the demo and on EasyRPG's TestGame (2000, 2003, Maniacs), the event editor test, and a check that the Godot editor loads the plugin.

- **Releases:** ready-to-use addon zips with Windows and Linux binaries appear under [Releases](https://github.com/depuschm/godot-lcf-editor/releases) once a version is tagged.
- **Latest build:** open the newest successful run on the [Actions page](https://github.com/depuschm/godot-lcf-editor/actions/workflows/build.yml) and download `lcf_editor-Windows` or `lcf_editor-Linux` (needs a GitHub login).

To use a download, put the `lcf_editor` folder into your Godot project's `addons/` folder (or clone this repository and copy it into `addons/lcf_editor`), then enable **LCF Editor** under *Project → Project Settings → Plugins*. macOS builds are not provided yet.

## Building

**Requirements:** Godot 4.5 or newer, CMake 3.17+, a C++17 compiler, and ICU for text encodings
(Linux: `libicu-dev`; macOS: `brew install icu4c`; Windows 10 1903+ uses the ICU built into the system).

```bash
git clone --recursive https://github.com/depuschm/godot-lcf-editor
cd godot-lcf-editor
cmake -S extension -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release
```

The first build takes a while because it compiles godot-cpp. The library lands in `addons/lcf_editor/bin/`. Then open the folder in Godot; the **LCF Project** dock appears on the left.

Already cloned without `--recursive`? Run `git submodule update --init --recursive`.

**Windows:** run the commands in a *Developer Command Prompt for VS 2022* (or any shell with CMake and MSVC available).
**macOS:** pass `-DICU_ROOT=$(brew --prefix icu4c)` to the first `cmake` command. macOS builds are untested so far.
**Without ICU:** add `-DLCF_WITH_ICU=OFF`; only Western (Windows-1252) projects will then show correct text.

### Smoke test

```bash
godot --headless --path . --script res://tests/test_load_demo.gd
```

It loads `demo/` through the extension and prints the map tree. CI runs it with Godot 4.5.1 on Windows and Linux; it was also tested with 4.7.2.

In a fresh checkout, run `godot --headless --path . --import` once first. That very first headless import can abort while Godot registers the extension (godot-cpp's own example does the same); simply run it again.

### Round-trip test

Checks byte-exact saving of the database and every map, the edit path for every database entry, event and command list, a real edit with backup and the save counter, painting a small lake (shores, undo, map saving), and creating, editing, deleting and restoring an event. It always works on a copy in Godot's user data folder, never on the project itself:

```bash
godot --headless --path . --script res://tests/test_roundtrip.gd -- /path/to/RPG/project
```

Without a path it uses `demo/`.

### Event editor test

Drives the real map view, event editor and database view without a window, on a copy of `demo/`: creating, renaming, moving, copying and deleting events, page settings, pages and commands, the undo states, and common event commands.

```bash
godot --headless --path . --script res://tests/test_event_editor.gd
```

### Rendering a map to PNG

```bash
godot --headless --path . --script res://tests/render_map.gd -- res://demo 1 map.png
```

### Regenerating the demo project

The demo chipset is drawn by a script (needs Pillow), and the maps are painted from the text grids in `tools/demo_maps/` (legend at the top of `tools/make_demo_project.cpp`):

```bash
python3 tools/make_demo_chipset.py demo/ChipSet/Demo.png
cmake -S tools -B build-tools && cmake --build build-tools
./build-tools/make_demo_project demo tools/demo_maps
```

## Roadmap

| | Milestone |
|---|---|
| M0 | Evaluate EasyRPG Editor; contact the EasyRPG team about a plugin API |
| M1 | liblcf in Godot: load a project ✅ |
| M2 | Map view with correct chipsets and autotiles ✅ |
| M2b | Map painting with autotiles, undo and safe saving ✅ |
| M3a | Database browser ✅ |
| M3b | Database editing and safe saving (backups, byte-identical round trip) ✅ |
| M4a | Event editor: events on the map, pages, page settings, command lists (raw editing), undo ✅ |
| M4b | Data-driven dialogs for event commands, registered by plugins |
| M5 | Plugin API for the editor |
| M6 | Test Play with EasyRPG Player; runtime extension mechanism |
| M7 | Showcase plugins: pixel-perfect movement, shader support |

## Contributing

Ideas, issues and pull requests are welcome. Please never commit RPG Maker RTP assets or other copyrighted material; test projects must use self-made or freely licensed assets.

## License

MIT — see [LICENSE](LICENSE). Third-party components: liblcf (MIT), godot-cpp (MIT), libexpat (MIT).

This project is not affiliated with Kadokawa, Gotcha Gotcha Games or the EasyRPG project. RPG Maker is a trademark of its respective owners.
