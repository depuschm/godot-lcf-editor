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

	// --- editing ---------------------------------------------------------------

	// Replaces one entry with edited XML (same format as get_database_entry_xml).
	// Nothing changes if the XML does not parse cleanly; see get_last_error().
	Error set_database_entry_xml(const String &section, int index, const String &xml);

	// Sets one field of an entry from plain text ("T"/"F", "42", "1 2 3", any string).
	// `path` lists child-element indices below the entry's root in
	// get_database_entry_xml, e.g. [0] for the first field.
	Error set_database_field(const String &section, int index, const PackedInt32Array &path, const String &value);

	// True when the database has changes that are not saved yet.
	bool is_database_modified() const;

	// Saves RPG_RT.ldb if it was modified: copies the current file into
	// `backup_dir` (keeping the newest 20), writes a temporary file, reads it back
	// to verify it, then replaces the original. Increments the save counter like
	// RPG Maker does. An empty backup_dir skips the backup.
	Error save_database(const String &backup_dir);

	// Path of the backup made by the last save_database(), or empty.
	String get_last_backup() const;

	// Writes the database as it is now (no backup, no save counter) to `path`.
	Error export_database(const String &path) const;

	// Drops unsaved changes by reading RPG_RT.ldb again.
	Error revert_database();

	// Checks whether saving the database as loaded would reproduce RPG_RT.ldb byte
	// for byte: { identical, original_size, saved_size, first_difference, notes }.
	// `notes` lists what liblcf reported while reading (e.g. skipped unknown data).
	Dictionary check_round_trip() const;

protected:
	static void _bind_methods();

private:
	Error fail(const String &message);
	std::filesystem::path find_file(const std::string &name) const;
	std::unique_ptr<lcf::rpg::Map> load_map(int map_id);
	std::unique_ptr<lcf::rpg::Database> read_database(const std::filesystem::path &path) const;

	std::filesystem::path dir;
	std::string encoding;
	std::string game_title;
	std::unique_ptr<lcf::rpg::Database> db;
	std::unique_ptr<lcf::rpg::TreeMap> tree;
	mutable String last_error;
	bool db_modified = false;
	String last_backup;
};

} // namespace godot
