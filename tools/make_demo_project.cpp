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
	db.system.title_name = DBString("");

	auto named = [](auto &list, const char *name) -> auto & {
		list.emplace_back();
		list.back().ID = int(list.size());
		list.back().name = DBString(name);
		return list.back();
	};

	auto &warrior = named(db.classes, "Warrior");
	auto &wizard = named(db.classes, "Wizard");

	auto &slash = named(db.skills, "Power Slash");
	slash.description = DBString("A strong strike against one enemy.");
	slash.sp_cost = 4;
	auto &fire = named(db.skills, "Fire");
	fire.description = DBString("Burns one enemy.");
	fire.sp_cost = 6;
	auto &heal = named(db.skills, "Heal");
	heal.description = DBString("Restores HP of one ally.");
	heal.sp_cost = 5;

	warrior.skills.push_back({});
	warrior.skills.back().ID = 1;
	warrior.skills.back().level = 3;
	warrior.skills.back().skill_id = slash.ID;
	for (int skill : { fire.ID, heal.ID }) {
		wizard.skills.push_back({});
		wizard.skills.back().ID = int(wizard.skills.size());
		wizard.skills.back().level = skill == fire.ID ? 1 : 4;
		wizard.skills.back().skill_id = skill;
	}

	auto &potion = named(db.items, "Potion");
	potion.type = rpg::Item::Type_medicine;
	potion.description = DBString("Restores 50 HP.");
	potion.price = 20;
	auto &sword = named(db.items, "Bronze Sword");
	sword.type = rpg::Item::Type_weapon;
	sword.price = 120;
	sword.atk_points1 = 8;
	auto &staff = named(db.items, "Oak Staff");
	staff.type = rpg::Item::Type_weapon;
	staff.price = 90;
	staff.spi_points1 = 6;

	struct ActorSpec { const char *name; const char *title; int class_id; int weapon; };
	for (const ActorSpec &spec : { ActorSpec{ "Hero", "Wanderer", warrior.ID, sword.ID }, ActorSpec{ "Mage", "Apprentice", wizard.ID, staff.ID } }) {
		auto &actor = named(db.actors, spec.name);
		actor.title = DBString(spec.title);
		actor.class_id = spec.class_id;
		actor.initial_equipment.weapon_id = spec.weapon;
		actor.final_level = 50;
	}

	auto &slime = named(db.enemies, "Slime");
	slime.max_hp = 30;
	slime.attack = 8;
	slime.exp = 4;
	slime.gold = 5;
	auto &bat = named(db.enemies, "Cave Bat");
	bat.max_hp = 22;
	bat.agility = 30;
	bat.exp = 6;
	bat.gold = 3;

	auto &troop = named(db.troops, "Slime x2, Bat");
	for (int enemy : { slime.ID, slime.ID, bat.ID }) {
		troop.members.push_back({});
		troop.members.back().ID = int(troop.members.size());
		troop.members.back().enemy_id = enemy;
		troop.members.back().x = 60 + 50 * int(troop.members.size());
		troop.members.back().y = 100;
	}

	named(db.states, "Poison");
	named(db.attributes, "Fire");
	named(db.terrains, "Grassland");

	rpg::Chipset chipset;
	chipset.ID = 1;
	chipset.name = DBString("Demo Tiles");
	chipset.chipset_name = DBString("Demo");
	db.chipsets.push_back(chipset);

	for (const char *name : { "Intro done", "Door open" }) named(db.switches, name);
	for (const char *name : { "Steps", "Slimes defeated" }) named(db.variables, name);

	auto &common = named(db.commonevents, "Heal party");
	auto command = [&](int code, int indent, const char *text, std::initializer_list<int32_t> params) {
		rpg::EventCommand c;
		c.code = code;
		c.indent = indent;
		c.string = DBString(text);
		c.parameters = DBArray<int32_t>(params);
		common.event_commands.push_back(std::move(c));
	};
	using Code = rpg::EventCommand::Code;
	command(int(Code::Comment), 0, "Called by the inn keeper", {});
	command(int(Code::ConditionalBranch), 0, "", { 0, 1, 0, 0, 0, 0 });
	command(int(Code::ShowMessage), 1, "Welcome back!", {});
	command(int(Code::ElseBranch), 0, "", {});
	command(int(Code::ShowMessage), 1, "Have a good rest.", {});
	command(int(Code::ShowMessage_2), 1, "Your party feels refreshed.", {});
	command(int(Code::EndBranch), 0, "", {});
	command(int(Code::FullHeal), 0, "", { 0, 0 });
	command(int(Code::PlaySound), 0, "Heal", { 100, 100, 50 });
	command(int(Code::ChangeGold), 0, "", { 1, 0, 10 });
	command(int(Code::END), 0, "", {});

	db.terms.encounter = DBString(" appeared!");
	db.terms.victory = DBString("Victory!");
	db.terms.gold = DBString("G");
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
