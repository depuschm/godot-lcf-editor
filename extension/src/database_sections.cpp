#include "database_sections.h"

// liblcf's internal field tables; not part of its installed API, but available
// because liblcf is built from the pinned submodule.
#include "reader_struct.h"

#include <lcf/rpg/database.h>
#include <lcf/saveopt.h>
#include <lcf/writer_xml.h>

#include <functional>
#include <map>
#include <sstream>
#include <type_traits>

namespace lcf_db {
namespace {

using lcf::rpg::Database;

template <class T, class = void>
struct has_name : std::false_type {};
template <class T>
struct has_name<T, std::void_t<decltype(std::declval<T>().name)>> : std::true_type {};

template <class T, class = void>
struct has_id : std::false_type {};
template <class T>
struct has_id<T, std::void_t<decltype(std::declval<T>().ID)>> : std::true_type {};

template <class T>
std::string to_xml(const T &value, lcf::EngineVersion engine) {
	std::ostringstream out;
	lcf::XmlWriter writer(out, engine);
	lcf::Struct<T>::WriteXml(value, writer);
	return out.str();
}

struct Accessor {
	std::function<int(const Database &)> count;
	std::function<bool(const Database &, int, Entry &)> entry;
	std::function<std::string(const Database &, int)> xml;
};

template <class T>
Accessor list(std::vector<T> Database::*member) {
	Accessor a;
	a.count = [member](const Database &db) { return int((db.*member).size()); };
	a.entry = [member](const Database &db, int i, Entry &out) {
		const auto &items = db.*member;
		if (i < 0 || i >= int(items.size())) return false;
		if constexpr (has_id<T>::value) out.id = items[i].ID;
		else out.id = i + 1;
		if constexpr (has_name<T>::value) out.name = lcf::ToString(items[i].name);
		return true;
	};
	a.xml = [member](const Database &db, int i) {
		const auto &items = db.*member;
		if (i < 0 || i >= int(items.size())) return std::string();
		return to_xml(items[i], lcf::GetEngineVersion(db));
	};
	return a;
}

template <class T>
Accessor single(T Database::*member, const char *label) {
	Accessor a;
	a.count = [](const Database &) { return 1; };
	a.entry = [label](const Database &, int i, Entry &out) {
		if (i != 0) return false;
		out.id = 1;
		out.name = label;
		return true;
	};
	a.xml = [member](const Database &db, int i) {
		return i == 0 ? to_xml(db.*member, lcf::GetEngineVersion(db)) : std::string();
	};
	return a;
}

struct Registry {
	std::vector<Section> order;
	std::map<std::string, Accessor> access;

	template <class T>
	void add_list(const char *key, const char *label, std::vector<T> Database::*member) {
		order.push_back({ key, label, false });
		access[key] = list(member);
	}
	template <class T>
	void add_single(const char *key, const char *label, T Database::*member) {
		order.push_back({ key, label, true });
		access[key] = single(member, label);
	}
};

const Registry &registry() {
	static const Registry r = [] {
		Registry reg;
		reg.add_list("actors", "Actors", &Database::actors);
		reg.add_list("classes", "Classes", &Database::classes);
		reg.add_list("skills", "Skills", &Database::skills);
		reg.add_list("items", "Items", &Database::items);
		reg.add_list("enemies", "Enemies", &Database::enemies);
		reg.add_list("troops", "Troops", &Database::troops);
		reg.add_list("attributes", "Attributes", &Database::attributes);
		reg.add_list("states", "States", &Database::states);
		reg.add_list("animations", "Battle Animations", &Database::animations);
		reg.add_list("battleranimations", "Battler Animations", &Database::battleranimations);
		reg.add_single("battlecommands", "Battle Commands", &Database::battlecommands);
		reg.add_list("terrains", "Terrain", &Database::terrains);
		reg.add_list("chipsets", "Chipsets", &Database::chipsets);
		reg.add_single("terms", "Vocabulary", &Database::terms);
		reg.add_single("system", "System", &Database::system);
		reg.add_list("commonevents", "Common Events", &Database::commonevents);
		reg.add_list("switches", "Switches", &Database::switches);
		reg.add_list("variables", "Variables", &Database::variables);
		reg.add_list("maniac_string_variables", "String Variables (Maniacs)", &Database::maniac_string_variables);
		return reg;
	}();
	return r;
}

} // namespace

const std::vector<Section> &sections() {
	return registry().order;
}

int count(const Database &db, const std::string &key) {
	auto it = registry().access.find(key);
	return it == registry().access.end() ? -1 : it->second.count(db);
}

bool entry(const Database &db, const std::string &key, int index, Entry &out) {
	auto it = registry().access.find(key);
	return it != registry().access.end() && it->second.entry(db, index, out);
}

std::string entry_xml(const Database &db, const std::string &key, int index) {
	auto it = registry().access.find(key);
	return it == registry().access.end() ? std::string() : it->second.xml(db, index);
}

const char *command_name(int code) {
	return lcf::rpg::EventCommand::kCodeTags.tag(code);
}

} // namespace lcf_db
