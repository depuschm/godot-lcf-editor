// Generates the tiny RPG Maker 2003 test project in demo/ using liblcf.
// The maps are painted from the text grids in tools/demo_maps/ (one character per
// tile, legend below), and every water and ground autotile gets the pattern RPG Maker
// would pick for its neighbours. Everything is made up here, so the project contains
// no RPG Maker (RTP) assets; the chipset comes from tools/make_demo_chipset.py.
//
//   cmake -S tools -B build-tools && cmake --build build-tools
//   ./build-tools/make_demo_project demo tools/demo_maps
//
// Legend
//   .  grass (autotile D1)       ,  dark grass (D3)        =  dirt path (D2)
//   #  stone path (D4)           ~  water (A1)
//   *  yellow flowers            +  red flowers            "  tall grass
//   X  darkness                  W  wall top               K  brick wall
//   w  wood floor                C  carpet
//   T  tree (top drawn one tile above)   b bush   o rock   f fence   s sign
//   <  ^  >  roof left/middle/right      n window wall   h wall   D door
//   c  chest   t table   B barrel        (objects stand on the ground to their left)

#include "tile_rules.h"

#include <lcf/ldb/reader.h>
#include <lcf/lmt/reader.h>
#include <lcf/lmu/reader.h>
#include <lcf/rpg/database.h>
#include <lcf/rpg/map.h>
#include <lcf/rpg/treemap.h>
#include <lcf/saveopt.h>

#include <cstdio>
#include <fstream>
#include <map>
#include <string>
#include <vector>

using namespace lcf;
using namespace lcf_tiles;

namespace {

const char *kEncoding = "windows-1252";

// Lower-layer terrain kinds; values >= LOWER are fixed tile IDs.
enum Kind { GRASS = 1, DARK_GRASS, PATH, STONE, WATER };

const std::map<char, int> kLower = {
	{ '.', GRASS }, { ',', DARK_GRASS }, { '=', PATH }, { '#', STONE }, { '~', WATER },
	{ '*', LOWER + 1 }, { '+', LOWER + 2 }, { '"', LOWER + 3 },
	{ 'W', LOWER + 8 }, { 'K', LOWER + 9 }, { 'X', LOWER + 10 }, { 'w', LOWER + 7 }, { 'C', LOWER + 11 },
};

const std::map<char, int> kUpper = {
	{ 'T', UPPER + 7 }, { 'b', UPPER + 2 }, { 'o', UPPER + 3 }, { 'f', UPPER + 4 }, { 's', UPPER + 5 },
	{ '<', UPPER + 8 }, { '^', UPPER + 9 }, { '>', UPPER + 10 },
	{ 'n', UPPER + 12 }, { 'h', UPPER + 13 }, { 'D', UPPER + 14 },
	{ 'c', UPPER + 15 }, { 't', UPPER + 16 }, { 'B', UPPER + 17 },
};
constexpr int TREE_TOP = UPPER + 1;

int ground_block(int kind) {
	switch (kind) {
		case GRASS: return 0;
		case PATH: return 1;
		case DARK_GRASS: return 2;
		case STONE: return 3;
		default: return -1;
	}
}

std::vector<std::string> read_grid(const std::string &path) {
	std::vector<std::string> rows;
	std::ifstream in(path);
	std::string line;
	while (std::getline(in, line)) {
		if (!line.empty() && line.back() == '\r') line.pop_back();
		if (!line.empty()) rows.push_back(line);
	}
	return rows;
}

// Paints a map from a text grid. `floor` is the lower kind under objects.
bool paint(rpg::Map &map, const std::vector<std::string> &grid, int floor) {
	if (grid.empty()) return false;
	const int w = int(grid[0].size()), h = int(grid.size());
	for (const auto &row : grid) {
		if (int(row.size()) != w) return false;
	}
	std::vector<int> kind(w * h, floor);
	map.width = w;
	map.height = h;
	map.chipset_id = 1;
	map.upper_layer.assign(w * h, UPPER);
	for (int y = 0; y < h; ++y) {
		for (int x = 0; x < w; ++x) {
			const char ch = grid[y][x];
			if (auto it = kLower.find(ch); it != kLower.end()) {
				kind[y * w + x] = it->second;
			} else if (x > 0) {
				kind[y * w + x] = kind[y * w + x - 1]; // objects stand on the ground to their left
			}
			if (auto it = kUpper.find(ch); it != kUpper.end()) {
				map.upper_layer[y * w + x] = int16_t(it->second);
				if (ch == 'T' && y > 0) map.upper_layer[(y - 1) * w + x] = int16_t(TREE_TOP);
			}
		}
	}

	// Outside the map counts as the same terrain, so map edges get no border.
	auto same = [&](int x, int y, int k) {
		if (x < 0 || y < 0 || x >= w || y >= h) return true;
		return kind[y * w + x] == k;
	};
	map.lower_layer.assign(w * h, 0);
	for (int y = 0; y < h; ++y) {
		for (int x = 0; x < w; ++x) {
			const int k = kind[y * w + x];
			if (k >= LOWER) {
				map.lower_layer[y * w + x] = int16_t(k);
				continue;
			}
			int sides = 0, corners = 0;
			if (!same(x - 1, y, k)) sides |= LEFT;
			if (!same(x, y - 1, k)) sides |= TOP;
			if (!same(x + 1, y, k)) sides |= RIGHT;
			if (!same(x, y + 1, k)) sides |= BOTTOM;
			if (!same(x - 1, y - 1, k)) corners |= TL;
			if (!same(x + 1, y - 1, k)) corners |= TR;
			if (!same(x + 1, y + 1, k)) corners |= BR;
			if (!same(x - 1, y + 1, k)) corners |= BL;
			const int pattern = encode_pattern(sides, corners);
			const int id = k == WATER ? WATER_A1 + pattern : GROUND + ground_block(k) * 50 + pattern;
			map.lower_layer[y * w + x] = int16_t(id);
		}
	}
	return true;
}

void add_event(rpg::Map &map, const char *name, int x, int y) {
	rpg::Event event;
	event.ID = int(map.events.size()) + 1;
	event.name = DBString(name);
	event.x = x;
	event.y = y;
	event.pages.emplace_back();
	event.pages.back().ID = 1;
	map.events.push_back(std::move(event));
}

rpg::MapInfo map_info(int id, const char *name, int parent, int indentation, int type) {
	rpg::MapInfo info;
	info.ID = id;
	info.name = DBString(name);
	info.parent_map = parent;
	info.indentation = indentation;
	info.type = type;
	return info;
}

} // namespace

int main(int argc, char **argv) {
	const std::string dir = argc > 1 ? argv[1] : "demo";
	const std::string maps_dir = argc > 2 ? argv[2] : "tools/demo_maps";

	rpg::Database db;
	db.system.ldb_id = 2003;
	for (const char *name : { "Hero", "Mage" }) {
		rpg::Actor actor;
		actor.ID = int(db.actors.size()) + 1;
		actor.name = DBString(name);
		db.actors.push_back(actor);
	}
	rpg::Chipset chipset;
	chipset.ID = 1;
	chipset.name = DBString("Demo Tiles");
	chipset.chipset_name = DBString("Demo");
	db.chipsets.push_back(chipset);
	for (const char *name : { "Intro done", "Door open" }) {
		rpg::Switch sw;
		sw.ID = int(db.switches.size()) + 1;
		sw.name = DBString(name);
		db.switches.push_back(sw);
	}
	rpg::CommonEvent common;
	common.ID = 1;
	common.name = DBString("Heal party");
	db.commonevents.push_back(common);
	if (!LDB_Reader::Save(dir + "/RPG_RT.ldb", db, kEncoding)) return 1;

	rpg::TreeMap tree;
	tree.maps = {
		map_info(0, "LCF Editor Demo", 0, 0, rpg::TreeMap::MapType_root),
		map_info(1, "World", 0, 1, rpg::TreeMap::MapType_map),
		map_info(2, "Forest", 1, 2, rpg::TreeMap::MapType_area),
		map_info(3, "Town", 1, 2, rpg::TreeMap::MapType_map),
		map_info(4, "House", 3, 3, rpg::TreeMap::MapType_map),
	};
	tree.tree_order = { 0, 1, 2, 3, 4 };
	tree.active_node = 1;
	tree.start.party_map_id = 1;
	tree.start.party_x = 20;
	tree.start.party_y = 15;
	if (!LMT_Reader::Save(dir + "/RPG_RT.lmt", tree, EngineVersion::e2k3, kEncoding)) return 1;

	struct MapSpec {
		int id;
		const char *file;
		int floor;
	};
	for (const MapSpec &spec : { MapSpec{ 1, "world.txt", GRASS }, MapSpec{ 3, "town.txt", GRASS }, MapSpec{ 4, "house.txt", LOWER + 7 } }) {
		rpg::Map map;
		if (!paint(map, read_grid(maps_dir + "/" + spec.file), spec.floor)) {
			std::fprintf(stderr, "Bad map grid: %s/%s\n", maps_dir.c_str(), spec.file);
			return 1;
		}
		if (spec.id == 1) {
			add_event(map, "Sign", 11, 16);
		} else if (spec.id == 3) {
			add_event(map, "Door A", 4, 5);
			add_event(map, "Door B", 15, 5);
			add_event(map, "Villager", 9, 10);
		} else {
			add_event(map, "Chest", 13, 3);
			add_event(map, "Exit", 7, 8);
		}
		char name[32];
		std::snprintf(name, sizeof(name), "/Map%04d.lmu", spec.id);
		if (!LMU_Reader::Save(dir + name, map, EngineVersion::e2k3, kEncoding)) return 1;
	}

	std::ofstream ini(dir + "/RPG_RT.ini", std::ios::binary);
	ini << "[RPG_RT]\r\nGameTitle=LCF Editor Demo\r\nFullPackageFlag=1\r\n\r\n[EasyRPG]\r\nEncoding=1252\r\n";
	std::printf("Demo project written to %s\n", dir.c_str());
	return 0;
}
