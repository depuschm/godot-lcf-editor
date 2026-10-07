#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include <filesystem>
#include <memory>
#include <string>

namespace lcf::rpg {
class Database;
class Map;
class TreeMap;
} // namespace lcf::rpg

namespace godot {

// An RPG Maker 2000/2003 project (RPG_RT.ldb, RPG_RT.lmt, Map####.lmu, RPG_RT.ini),
// loaded through liblcf. All strings handed to Godot are UTF-8.
class LcfProject : public RefCounted {
	GDCLASS(LcfProject, RefCounted)

public:
	LcfProject();
	~LcfProject() override;

	// Loads the project in `project_dir` (absolute path or res://, user:// path).
	Error load(const String &project_dir);
	bool is_loaded() const;
	String get_last_error() const;

	String get_project_dir() const;
	String get_game_title() const;
	String get_encoding() const;
	String get_engine() const; // "2000" or "2003"

	// One Dictionary per map tree entry, in editor tree order:
	// { id, name, parent_id, indentation, type ("root" | "map" | "area") }
	Array get_map_tree() const;

	// Entry counts per database section, e.g. { actors: 8, items: 40, ... }.
	Dictionary get_database_summary() const;

	// Basic facts about one map (loads Map####.lmu on demand):
	// { id, width, height, chipset_id, event_count }. Empty on error.
	Dictionary get_map_info(int map_id);

	// Everything needed to draw a map:
	// { id, width, height, chipset_id, lower: PackedInt32Array, upper: PackedInt32Array,
	//   events: [{ id, name, x, y, page_count }] }. Tiles are row by row. Empty on error.
	Dictionary get_map(int map_id);

	// { id, name, file, animation_type, animation_speed } for a database chipset.
	Dictionary get_chipset(int chipset_id) const;

	// Absolute path of an image in a project folder such as "ChipSet", matched
	// case-insensitively; prefers .png over .bmp over .xyz. Empty if not found.
	String find_image(const String &folder, const String &name) const;

	// Database sections in RPG Maker's order: [{ key, label, single, count }].
	Array get_database_sections() const;

	// Entries of one section: [{ index, id, name }].
	Array get_database_entries(const String &section) const;

	// One entry as liblcf XML: every field by name, nested structures as child
	// elements, booleans as T/F, number lists space-separated. Empty on error.
	String get_database_entry_xml(const String &section, int index) const;

	// "ShowMessage", "CallCommonEvent", ... for an event command code; empty if unknown.
	static String get_event_command_name(int code);

protected:
	static void _bind_methods();

private:
	Error fail(const String &message);
	std::filesystem::path find_file(const std::string &name) const;
	std::unique_ptr<lcf::rpg::Map> load_map(int map_id);

	std::filesystem::path dir;
	std::string encoding;
	std::string game_title;
	std::unique_ptr<lcf::rpg::Database> db;
	std::unique_ptr<lcf::rpg::TreeMap> tree;
	String last_error;
};

} // namespace godot
