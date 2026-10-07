#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include <filesystem>
#include <functional>
#include <iosfwd>
#include <map>
#include <memory>
#include <set>
#include <string>

namespace lcf::rpg {
class Database;
class Event;
class EventPage;
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

	// Every event command code liblcf knows, in ascending order.
	static PackedInt32Array get_event_command_codes();

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

	// --- map editing -------------------------------------------------------------
	// Maps are edited in memory; get_map() returns the edited state.

	// Paints `tile_id` into `cells` (indices y * width + x) of layer 0 (lower) or 1
	// (upper). With auto_tile on the lower layer, the painted cells and their
	// neighbours get the autotile/water variants RPG Maker would pick. Returns the
	// changed cells for undo: { cells, before, after } (PackedInt32Arrays).
	Dictionary paint_map_tiles(int map_id, int layer, const PackedInt32Array &cells, int tile_id, bool auto_tile = true);

	// Sets exact tile IDs (no autotiling), e.g. for undo/redo.
	Error set_map_tiles(int map_id, int layer, const PackedInt32Array &cells, const PackedInt32Array &ids);

	bool is_map_modified(int map_id) const;
	PackedInt32Array get_modified_maps() const;

	// Saves Map####.lmu with the same safeguards as save_database().
	Error save_map(int map_id, const String &backup_dir);
	Error revert_map(int map_id);
	Error export_map(int map_id, const String &path);
	Dictionary check_map_round_trip(int map_id) const;

	// --- events --------------------------------------------------------------------
	// Map events are addressed by their ID (as in get_map().events), pages by their
	// 0-based index. Every change marks the map as modified; save it with save_map().

	// The whole event as liblcf XML (name, position, every page with its conditions,
	// graphic, movement and commands). Empty if there is no such event.
	String get_map_event_xml(int map_id, int event_id);

	// Replaces the event with edited XML; the event keeps its ID. Nothing changes if
	// the XML does not parse cleanly. Also the way to undo any event edit.
	Error set_map_event_xml(int map_id, int event_id, const String &xml);

	// Sets one field of an event from plain text; `path` as in set_database_field,
	// below the <Event> element of get_map_event_xml.
	Error set_map_event_field(int map_id, int event_id, const PackedInt32Array &path, const String &value);

	// Creates an event with one new page (see insert_map_event_page) at (x, y), named like RPG Maker does
	// ("EV0001"), with the lowest free ID. Returns the ID, or -1 on error.
	int add_map_event(int map_id, int x, int y);

	// Adds an event from XML (e.g. to undo a deletion or paste a copy). It keeps the
	// ID in the XML if that is free, otherwise gets the lowest free ID; x and y are
	// taken from the XML. Returns the ID, or -1 on error.
	int insert_map_event_xml(int map_id, const String &xml);

	Error delete_map_event(int map_id, int event_id);

	// Inserts a page at `index` (0..page count): a copy of page `copy_from`, or a new
	// page like RPG Maker creates it (stands still, same layer as the hero) when
	// copy_from is -1. Page IDs are renumbered.
	Error insert_map_event_page(int map_id, int event_id, int index, int copy_from = -1);
	Error remove_map_event_page(int map_id, int event_id, int index);

	// Event commands of a page: [{ code, indent, string, parameters: PackedInt32Array }].
	// The list ends with the last real command; the terminating zero entry RPG Maker
	// writes after it is added when saving.
	Array get_map_event_commands(int map_id, int event_id, int page);
	Error set_map_event_commands(int map_id, int event_id, int page, const Array &commands);

	// The same for common events (index as in get_database_entries("commonevents")).
	// Changing them marks the database as modified.
	Array get_common_event_commands(int index) const;
	Error set_common_event_commands(int index, const Array &commands);

protected:
	static void _bind_methods();

private:
	Error fail(const String &message);
	std::filesystem::path find_file(const std::string &name) const;
	std::filesystem::path map_path(int map_id) const;
	std::unique_ptr<lcf::rpg::Map> load_map(int map_id);
	lcf::rpg::Map *map_ref(int map_id);
	// The event with that ID on a loaded map, or nullptr (with last_error set).
	lcf::rpg::Event *event_ref(int map_id, int event_id);
	// The page of an event, or nullptr (with last_error set).
	lcf::rpg::EventPage *page_ref(int map_id, int event_id, int page);
	std::unique_ptr<lcf::rpg::Database> read_database(const std::filesystem::path &path) const;
	std::unique_ptr<lcf::rpg::Map> read_map(const std::filesystem::path &path) const;
	Error safe_save(const std::filesystem::path &target, const String &backup_dir,
			const std::function<bool(std::ostream &)> &write,
			const std::function<bool(const std::filesystem::path &)> &verify);

	std::filesystem::path dir;
	std::string encoding;
	std::string game_title;
	std::unique_ptr<lcf::rpg::Database> db;
	std::unique_ptr<lcf::rpg::TreeMap> tree;
	std::map<int, std::unique_ptr<lcf::rpg::Map>> maps;
	std::set<int> modified_maps;
	mutable String last_error;
	bool db_modified = false;
	String last_backup;
};

} // namespace godot
