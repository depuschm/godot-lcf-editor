// Generates the tiny RPG Maker 2003 test project in demo/ using liblcf.
// Everything in it is made up here, so it contains no RPG Maker (RTP) assets.
//
//   cmake -S tools -B build-tools && cmake --build build-tools
//   ./build-tools/make_demo_project demo

#include <lcf/ldb/reader.h>
#include <lcf/lmt/reader.h>
#include <lcf/lmu/reader.h>
#include <lcf/rpg/database.h>
#include <lcf/rpg/map.h>
#include <lcf/rpg/treemap.h>
#include <lcf/saveopt.h>

#include <cstdio>
#include <fstream>
#include <string>

using namespace lcf;

namespace {

const char *kEncoding = "windows-1252";

rpg::MapInfo map_info(int id, const char *name, int parent, int indentation, int type) {
	rpg::MapInfo info;
	info.ID = id;
	info.name = DBString(name);
	info.parent_map = parent;
	info.indentation = indentation;
	info.type = type;
	return info;
}

rpg::Map make_map(int width, int height, int event_count) {
	rpg::Map map;
	map.width = width;
	map.height = height;
	map.chipset_id = 1;
	map.lower_layer.assign(width * height, 5000);  // plain ground tile
	map.upper_layer.assign(width * height, 10000); // empty upper tile
	for (int i = 1; i <= event_count; ++i) {
		rpg::Event event;
		event.ID = i;
		event.name = DBString("EV" + std::string(i < 10 ? "000" : "00") + std::to_string(i));
		event.x = i;
		event.y = 1;
		event.pages.emplace_back();
		event.pages.back().ID = 1;
		map.events.push_back(std::move(event));
	}
	return map;
}

} // namespace

int main(int argc, char **argv) {
	const std::string dir = argc > 1 ? argv[1] : "demo";

	rpg::Database db;
	db.system.ldb_id = 2003;
	for (const char *name : { "Hero", "Mage" }) {
		rpg::Actor actor;
		actor.ID = static_cast<int>(db.actors.size()) + 1;
		actor.name = DBString(name);
		db.actors.push_back(actor);
	}
	rpg::Chipset chipset;
	chipset.ID = 1;
	chipset.name = DBString("Demo Tiles");
	db.chipsets.push_back(chipset);
	for (const char *name : { "Intro done", "Door open" }) {
		rpg::Switch sw;
		sw.ID = static_cast<int>(db.switches.size()) + 1;
		sw.name = DBString(name);
		db.switches.push_back(sw);
	}
	rpg::CommonEvent common;
	common.ID = 1;
	common.name = DBString("Heal party");
	db.commonevents.push_back(common);
	if (!LDB_Reader::Save(dir + "/RPG_RT.ldb", db, kEncoding)) {
		return 1;
	}

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
	tree.start.party_x = 5;
	tree.start.party_y = 5;
	if (!LMT_Reader::Save(dir + "/RPG_RT.lmt", tree, EngineVersion::e2k3, kEncoding)) {
		return 1;
	}

	const struct { int id, width, height, events; } maps[] = { { 1, 40, 30, 1 }, { 3, 20, 15, 3 }, { 4, 15, 10, 2 } };
	for (const auto &m : maps) {
		char name[32];
		std::snprintf(name, sizeof(name), "/Map%04d.lmu", m.id);
		if (!LMU_Reader::Save(dir + name, make_map(m.width, m.height, m.events), EngineVersion::e2k3, kEncoding)) {
			return 1;
		}
	}

	std::ofstream ini(dir + "/RPG_RT.ini", std::ios::binary);
	ini << "[RPG_RT]\r\nGameTitle=LCF Editor Demo\r\nFullPackageFlag=1\r\n\r\n[EasyRPG]\r\nEncoding=1252\r\n";
	std::printf("Demo project written to %s\n", dir.c_str());
	return 0;
}
