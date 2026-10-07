#include "lcf_project.h"

#include "database_sections.h"

#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/core/class_db.hpp>

#include <lcf/ldb/reader.h>
#include <lcf/lmt/reader.h>
#include <lcf/lmu/reader.h>
#include <lcf/reader_util.h>
#include <lcf/rpg/database.h>
#include <lcf/rpg/map.h>
#include <lcf/rpg/treemap.h>
#include <lcf/saveopt.h>

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <fstream>
#include <map>

namespace fs = std::filesystem;
using namespace godot;

namespace {

String to_godot(const std::string &s) {
	return String::utf8(s.c_str(), static_cast<int>(s.size()));
}

std::string lower(std::string s) {
	std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) { return std::tolower(c); });
	return s;
}

std::string trim(const std::string &s) {
	const auto first = s.find_first_not_of(" \t\r\n");
	if (first == std::string::npos) {
		return {};
	}
	return s.substr(first, s.find_last_not_of(" \t\r\n") - first + 1);
}

// Minimal INI reader: returns "section.key" (lowercase) -> raw value bytes.
std::map<std::string, std::string> read_ini(const fs::path &path) {
	std::map<std::string, std::string> values;
	std::ifstream in(path, std::ios::binary);
	std::string line, section;
	while (std::getline(in, line)) {
		line = trim(line);
		if (line.empty() || line[0] == ';') {
			continue;
		}
		if (line.front() == '[' && line.back() == ']') {
			section = lower(trim(line.substr(1, line.size() - 2)));
			continue;
		}
		const auto eq = line.find('=');
		if (eq != std::string::npos) {
			values[section + "." + lower(trim(line.substr(0, eq)))] = trim(line.substr(eq + 1));
		}
	}
	return values;
}

const char *map_type_name(int type) {
	switch (type) {
		case lcf::rpg::TreeMap::MapType_root:
			return "root";
		case lcf::rpg::TreeMap::MapType_area:
			return "area";
		default:
			return "map";
	}
}

} // namespace

LcfProject::LcfProject() = default;
LcfProject::~LcfProject() = default;

Error LcfProject::fail(const String &message) {
	last_error = message;
	db.reset();
	tree.reset();
	return FAILED;
}

// RPG Maker projects come from Windows, so file name case varies (RPG_RT.ldb vs RPG_RT.LDB).
fs::path LcfProject::find_file(const std::string &name) const {
	const fs::path exact = dir / name;
	std::error_code ec;
	if (fs::exists(exact, ec)) {
		return exact;
	}
	const std::string wanted = lower(name);
	for (const auto &entry : fs::directory_iterator(dir, ec)) {
		if (lower(entry.path().filename().u8string()) == wanted) {
			return entry.path();
		}
	}
	return {};
}

Error LcfProject::load(const String &project_dir) {
	last_error = String();
	String absolute = project_dir;
	if (project_dir.begins_with("res://") || project_dir.begins_with("user://")) {
		absolute = ProjectSettings::get_singleton()->globalize_path(project_dir);
	}
	dir = fs::u8path(absolute.utf8().get_data());

	const fs::path ldb_path = find_file("RPG_RT.ldb");
	const fs::path lmt_path = find_file("RPG_RT.lmt");
	if (ldb_path.empty() || lmt_path.empty()) {
		return fail("Not an RPG Maker 2000/2003 project (RPG_RT.ldb or RPG_RT.lmt missing): " + absolute);
	}

	// Encoding: [EasyRPG] Encoding in RPG_RT.ini wins, otherwise detect it from the database.
	std::map<std::string, std::string> ini;
	const fs::path ini_path = find_file("RPG_RT.ini");
	if (!ini_path.empty()) {
		ini = read_ini(ini_path);
	}
	encoding.clear();
	if (auto it = ini.find("easyrpg.encoding"); it != ini.end()) {
		encoding = lcf::ReaderUtil::CodepageToEncoding(std::atoi(it->second.c_str()));
	}

	auto load_db = [&](const std::string &enc) {
		std::ifstream in(ldb_path, std::ios::binary);
		return in ? lcf::LDB_Reader::Load(in, enc) : nullptr;
	};

	if (encoding.empty()) {
		auto raw = load_db(""); // strings stay undecoded, good enough for detection
		if (!raw) {
			return fail("Could not read " + to_godot(ldb_path.u8string()));
		}
		encoding = lcf::ReaderUtil::DetectEncoding(*raw);
		if (encoding.empty()) {
			encoding = "windows-1252";
		}
	}

	db = load_db(encoding);
	if (!db) {
		return fail("Could not read " + to_godot(ldb_path.u8string()));
	}
	std::ifstream lmt_in(lmt_path, std::ios::binary);
	tree = lcf::LMT_Reader::Load(lmt_in, encoding);
	if (!tree) {
		return fail("Could not read " + to_godot(lmt_path.u8string()));
	}

	game_title.clear();
	if (auto it = ini.find("rpg_rt.gametitle"); it != ini.end()) {
		game_title = lcf::ReaderUtil::Recode(it->second, encoding);
	}
	return OK;
}

bool LcfProject::is_loaded() const {
	return db && tree;
}

String LcfProject::get_last_error() const {
	return last_error;
}

String LcfProject::get_project_dir() const {
	return to_godot(dir.u8string());
}

String LcfProject::get_game_title() const {
	return to_godot(game_title);
}

String LcfProject::get_encoding() const {
	return to_godot(encoding);
}

String LcfProject::get_engine() const {
	if (!db) {
		return String();
	}
	return lcf::GetEngineVersion(*db) == lcf::EngineVersion::e2k3 ? "2003" : "2000";
}

Array LcfProject::get_map_tree() const {
	Array result;
	if (!tree) {
		return result;
	}
	std::map<int, const lcf::rpg::MapInfo *> by_id;
	for (const auto &info : tree->maps) {
		by_id[info.ID] = &info;
	}
	for (int id : tree->tree_order) {
		auto it = by_id.find(id);
		if (it == by_id.end()) {
			continue;
		}
		const auto &info = *it->second;
		Dictionary entry;
		entry["id"] = info.ID;
		entry["name"] = to_godot(lcf::ToString(info.name));
		entry["parent_id"] = info.parent_map;
		entry["indentation"] = info.indentation;
		entry["type"] = map_type_name(info.type);
		result.push_back(entry);
	}
	return result;
}

Dictionary LcfProject::get_database_summary() const {
	Dictionary summary;
	if (!db) {
		return summary;
	}
	summary["actors"] = static_cast<int64_t>(db->actors.size());
	summary["classes"] = static_cast<int64_t>(db->classes.size());
	summary["skills"] = static_cast<int64_t>(db->skills.size());
	summary["items"] = static_cast<int64_t>(db->items.size());
	summary["enemies"] = static_cast<int64_t>(db->enemies.size());
	summary["troops"] = static_cast<int64_t>(db->troops.size());
	summary["states"] = static_cast<int64_t>(db->states.size());
	summary["animations"] = static_cast<int64_t>(db->animations.size());
	summary["chipsets"] = static_cast<int64_t>(db->chipsets.size());
	summary["common_events"] = static_cast<int64_t>(db->commonevents.size());
	summary["switches"] = static_cast<int64_t>(db->switches.size());
	summary["variables"] = static_cast<int64_t>(db->variables.size());
	return summary;
}

std::unique_ptr<lcf::rpg::Map> LcfProject::load_map(int map_id) {
	if (!is_loaded()) {
		last_error = "No project loaded";
		return nullptr;
	}
	char name[16];
	std::snprintf(name, sizeof(name), "Map%04d.lmu", map_id);
	const fs::path path = find_file(name);
	if (path.empty()) {
		last_error = String("Map file not found: ") + name;
		return nullptr;
	}
	std::ifstream in(path, std::ios::binary);
	auto map = lcf::LMU_Reader::Load(in, encoding);
	if (!map) {
		last_error = "Could not read " + to_godot(path.u8string());
	}
	return map;
}

Dictionary LcfProject::get_map_info(int map_id) {
	Dictionary info;
	auto map = load_map(map_id);
	if (!map) {
		return info;
	}
	info["id"] = map_id;
	info["width"] = map->width;
	info["height"] = map->height;
	info["chipset_id"] = map->chipset_id;
	info["event_count"] = static_cast<int64_t>(map->events.size());
	return info;
}

Dictionary LcfProject::get_map(int map_id) {
	Dictionary result;
	auto map = load_map(map_id);
	if (!map) {
		return result;
	}
	const int64_t cells = static_cast<int64_t>(map->width) * map->height;
	auto layer = [cells](const std::vector<int16_t> &tiles) {
		PackedInt32Array out;
		out.resize(cells);
		for (int64_t i = 0; i < cells; ++i) {
			out.set(i, i < static_cast<int64_t>(tiles.size()) ? tiles[i] : 0);
		}
		return out;
	};
	Array events;
	for (const auto &event : map->events) {
		Dictionary e;
		e["id"] = event.ID;
		e["name"] = to_godot(lcf::ToString(event.name));
		e["x"] = event.x;
		e["y"] = event.y;
		e["page_count"] = static_cast<int64_t>(event.pages.size());
		events.push_back(e);
	}
	result["id"] = map_id;
	result["width"] = map->width;
	result["height"] = map->height;
	result["chipset_id"] = map->chipset_id;
	result["lower"] = layer(map->lower_layer);
	result["upper"] = layer(map->upper_layer);
	result["events"] = events;
	return result;
}

Dictionary LcfProject::get_chipset(int chipset_id) const {
	Dictionary result;
	if (!db) {
		return result;
	}
	for (const auto &chipset : db->chipsets) {
		if (chipset.ID == chipset_id) {
			result["id"] = chipset.ID;
			result["name"] = to_godot(lcf::ToString(chipset.name));
			result["file"] = to_godot(lcf::ToString(chipset.chipset_name));
			result["animation_type"] = chipset.animation_type;
			result["animation_speed"] = chipset.animation_speed;
			break;
		}
	}
	return result;
}

String LcfProject::find_image(const String &folder, const String &name) const {
	if (name.is_empty() || dir.empty()) {
		return String();
	}
	std::error_code ec;
	fs::path sub;
	const std::string wanted_folder = lower(folder.utf8().get_data());
	for (const auto &entry : fs::directory_iterator(dir, ec)) {
		if (entry.is_directory(ec) && lower(entry.path().filename().u8string()) == wanted_folder) {
			sub = entry.path();
			break;
		}
	}
	if (sub.empty()) {
		return String();
	}
	const std::string wanted = lower(name.utf8().get_data());
	fs::path found;
	int best = 99;
	for (const auto &entry : fs::directory_iterator(sub, ec)) {
		const fs::path &p = entry.path();
		if (lower(p.stem().u8string()) != wanted) {
			continue;
		}
		const std::string ext = lower(p.extension().u8string());
		const int rank = ext == ".png" ? 0 : ext == ".bmp" ? 1 : ext == ".xyz" ? 2 : 99;
		if (rank < best) {
			best = rank;
			found = p;
		}
	}
	return found.empty() ? String() : to_godot(found.u8string());
}

Array LcfProject::get_database_sections() const {
	Array result;
	if (!db) {
		return result;
	}
	for (const auto &section : lcf_db::sections()) {
		Dictionary d;
		d["key"] = section.key;
		d["label"] = section.label;
		d["single"] = section.single;
		d["count"] = lcf_db::count(*db, section.key);
		result.push_back(d);
	}
	return result;
}

Array LcfProject::get_database_entries(const String &section) const {
	Array result;
	if (!db) {
		return result;
	}
	const std::string key = section.utf8().get_data();
	const int n = lcf_db::count(*db, key);
	for (int i = 0; i < n; ++i) {
		lcf_db::Entry e;
		if (lcf_db::entry(*db, key, i, e)) {
			Dictionary d;
			d["index"] = i;
			d["id"] = e.id;
			d["name"] = to_godot(e.name);
			result.push_back(d);
		}
	}
	return result;
}

String LcfProject::get_database_entry_xml(const String &section, int index) const {
	if (!db) {
		return String();
	}
	return to_godot(lcf_db::entry_xml(*db, section.utf8().get_data(), index));
}

String LcfProject::get_event_command_name(int code) {
	const char *name = lcf_db::command_name(code);
	return name ? String(name) : String();
}

void LcfProject::_bind_methods() {
	ClassDB::bind_method(D_METHOD("load", "project_dir"), &LcfProject::load);
	ClassDB::bind_method(D_METHOD("is_loaded"), &LcfProject::is_loaded);
	ClassDB::bind_method(D_METHOD("get_last_error"), &LcfProject::get_last_error);
	ClassDB::bind_method(D_METHOD("get_project_dir"), &LcfProject::get_project_dir);
	ClassDB::bind_method(D_METHOD("get_game_title"), &LcfProject::get_game_title);
	ClassDB::bind_method(D_METHOD("get_encoding"), &LcfProject::get_encoding);
	ClassDB::bind_method(D_METHOD("get_engine"), &LcfProject::get_engine);
	ClassDB::bind_method(D_METHOD("get_map_tree"), &LcfProject::get_map_tree);
	ClassDB::bind_method(D_METHOD("get_database_summary"), &LcfProject::get_database_summary);
	ClassDB::bind_method(D_METHOD("get_map_info", "map_id"), &LcfProject::get_map_info);
	ClassDB::bind_method(D_METHOD("get_map", "map_id"), &LcfProject::get_map);
	ClassDB::bind_method(D_METHOD("get_chipset", "chipset_id"), &LcfProject::get_chipset);
	ClassDB::bind_method(D_METHOD("find_image", "folder", "name"), &LcfProject::find_image);
	ClassDB::bind_method(D_METHOD("get_database_sections"), &LcfProject::get_database_sections);
	ClassDB::bind_method(D_METHOD("get_database_entries", "section"), &LcfProject::get_database_entries);
	ClassDB::bind_method(D_METHOD("get_database_entry_xml", "section", "index"), &LcfProject::get_database_entry_xml);
	ClassDB::bind_static_method("LcfProject", D_METHOD("get_event_command_name", "code"), &LcfProject::get_event_command_name);
}
