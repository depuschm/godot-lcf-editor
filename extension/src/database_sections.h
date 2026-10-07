#pragma once
// Generic access to the sections of an RPG Maker database (RPG_RT.ldb), independent
// of Godot. Entries are described by liblcf's own field tables (as XML), so every
// field of every section is available without per-section code.

#include <string>
#include <vector>

namespace lcf::rpg {
class Database;
}

namespace lcf_db {

struct Section {
	const char *key;   // liblcf field name, e.g. "actors"
	const char *label; // display name, e.g. "Actors"
	bool single;       // one struct (System, Terms, ...) instead of a list
};

struct Entry {
	int id = 0;
	std::string name;
};

// All sections, in the order RPG Maker's database editor shows them.
const std::vector<Section> &sections();

// Number of entries; single sections have one. -1 for an unknown key.
int count(const lcf::rpg::Database &db, const std::string &key);

// ID and name of entry `index` (0-based). False if out of range.
bool entry(const lcf::rpg::Database &db, const std::string &key, int index, Entry &out);

// The entry as liblcf XML, with every field named. Empty if out of range.
std::string entry_xml(const lcf::rpg::Database &db, const std::string &key, int index);

// Replaces entry `index` with the given XML (same format as entry_xml). The entry is
// parsed into a fresh structure by liblcf's XML reader; it keeps its ID. On any parse
// problem nothing changes and `error` explains why.
bool set_entry_xml(lcf::rpg::Database &db, const std::string &key, int index, const std::string &xml, std::string &error);

// Sets the text of one field of an entry. `path` holds child-element indices below
// the entry's root element (as in entry_xml), e.g. {0} for the first field or
// {16, 0, 2} for a field inside a nested structure. Only fields without child
// elements can be set. The value is plain text (escaped here), e.g. "T", "42",
// "1 2 3" or any string.
bool set_field(lcf::rpg::Database &db, const std::string &key, int index, const std::vector<int> &path, const std::string &value, std::string &error);

// Name of an event command code ("ShowMessage", ...) or nullptr if unknown.
const char *command_name(int code);

} // namespace lcf_db
