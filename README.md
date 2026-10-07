# godot-lcf-editor

Godot editor for RPG Maker 2000/2003 projects (LCF format), built on [liblcf](https://github.com/EasyRPG/liblcf). Extensible through plugins, playtested with [EasyRPG Player](https://github.com/EasyRPG/Player).

> **Status: early prototype.** The editor plugin opens an existing RPG Maker 2000/2003 project and shows its map tree and database overview inside Godot. Editing comes next — see the [roadmap](#roadmap).

## Vision

RPG Maker 2000/2003 still has an active community, but its editor and runtime are closed, Windows-only programs. Existing patches (Maniacs, DynRPG, Destiny) add fixed feature sets; none lets users extend the **editor itself**.

This project aims to change that:

- **Godot as the editor.** Maps, database and events are edited in Godot, and projects stay in the original RPG Maker 2000/2003 format.
- **EasyRPG Player as the runtime.** Games are played and tested with the open-source reimplementation of the RPG Maker runtime.
- **Everything is a plugin.** A feature such as pixel-perfect movement or shader support ships as an *editor half* (dialogs, tools, previews) and a *runtime half* (the mechanic in the player). Event command dialogs are generated from data, so a plugin registers a new command and gets its dialog for free.

The full vision, the existing landscape and the options considered are in [`docs/vision.tex`](docs/vision.tex).

## What works today

- Open an RPG Maker 2000 or 2003 project folder from the **LCF Project** dock.
- Detects engine version (2000/2003) and text encoding (from `RPG_RT.ini` or by analysing the database).
- Shows the map tree, including areas, and basic facts per map (size, chipset, event count).
- Exposes the project to GDScript through the `LcfProject` class:

```gdscript
var project := LcfProject.new()
if project.load("C:/Games/MyRpg") == OK:
    print(project.get_game_title(), " (RPG Maker ", project.get_engine(), ")")
    for entry in project.get_map_tree():
        print(entry.name, " ", entry.type)
```

## Repository layout

```
project.godot              Open this folder in Godot 4.5+
addons/lcf_editor/         Editor plugin (GDScript) + the GDExtension's binaries
extension/                 C++ GDExtension wrapping liblcf (CMake)
thirdparty/liblcf/         git submodule – RPG Maker 2000/2003 file formats
thirdparty/godot-cpp/      git submodule – Godot C++ bindings
demo/                      Tiny generated test project (no RPG Maker assets)
tests/                     Headless smoke test
tools/                     Helper programs (demo project generator)
docs/vision.tex            Vision document
```

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

It loads `demo/` through the extension and prints the map tree. Tested with Godot 4.5.1 and 4.7.2 on Linux.

In a fresh checkout, run `godot --headless --path . --import` once first. That very first headless import can abort while Godot registers the extension (godot-cpp's own example does the same); simply run it again.

### Regenerating the demo project

```bash
cmake -S tools -B build-tools && cmake --build build-tools
./build-tools/make_demo_project demo
```

## Roadmap

| | Milestone |
|---|---|
| M0 | Evaluate EasyRPG Editor; contact the EasyRPG team about a plugin API |
| M1 | liblcf in Godot: load a project ✅ |
| M2 | Map view with correct chipsets and autotiles |
| M3 | Database viewer and editor |
| M4 | Event editor with data-driven command dialogs |
| M5 | Plugin API for the editor |
| M6 | Test Play with EasyRPG Player; runtime extension mechanism |
| M7 | Showcase plugins: pixel-perfect movement, shader support |

## Contributing

Ideas, issues and pull requests are welcome. Please never commit RPG Maker RTP assets or other copyrighted material; test projects must use self-made or freely licensed assets.

## License

MIT — see [LICENSE](LICENSE). Third-party components: liblcf (MIT), godot-cpp (MIT).

This project is not affiliated with Kadokawa, Gotcha Gotcha Games or the EasyRPG project. RPG Maker is a trademark of its respective owners.
