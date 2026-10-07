#include "database_sections.h"

#include "lcf_xml.h"

#include <lcf/rpg/database.h>

#include <functional>
#include <map>
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
	return lcf_xml::write(value, engine);
}

using lcf_xml::root_name;

template <class T>
bool from_xml(T &out, const std::string &xml, const std::string &expected_root, std::string &error) {
	return lcf_xml::read(out, xml, expected_root, error);
}

struct Accessor {
	std::function<int(const Database &)> count;
	std::function<bool(const Database &, int, Entry &)> entry;
	std::function<std::string(const Database &, int)> xml;
	std::function<bool(Database &, int, const std::string &, std::string &)> set;
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
	a.set = [member](Database &db, int i, const std::string &xml, std::string &error) {
		auto &items = db.*member;
		if (i < 0 || i >= int(items.size())) {
			error = "No such entry";
			return false;
		}
		T parsed{};
		if (!from_xml(parsed, xml, root_name(to_xml(items[i], lcf::GetEngineVersion(db))), error)) return false;
		if constexpr (has_id<T>::value) parsed.ID = items[i].ID;
		items[i] = std::move(parsed);
		return true;
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
	a.set = [member](Database &db, int i, const std::string &xml, std::string &error) {
		if (i != 0) {
			error = "No such entry";
			return false;
		}
		T parsed{};
		if (!from_xml(parsed, xml, root_name(to_xml(db.*member, lcf::GetEngineVersion(db))), error)) return false;
		db.*member = std::move(parsed);
		return true;
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

bool set_field(Database &db, const std::string &key, int index, const std::vector<int> &path, const std::string &value, std::string &error) {
	std::string xml = entry_xml(db, key, index);
	if (xml.empty()) {
		error = "No such entry";
		return false;
	}
	return lcf_xml::set_leaf_text(xml, path, value, error) && set_entry_xml(db, key, index, xml, error);
}

bool set_entry_xml(Database &db, const std::string &key, int index, const std::string &xml, std::string &error) {
	auto it = registry().access.find(key);
	if (it == registry().access.end()) {
		error = "Unknown section " + key;
		return false;
	}
	return it->second.set(db, index, xml, error);
}

const char *command_name(int code) {
	return lcf::rpg::EventCommand::kCodeTags.tag(code);
}

} // namespace lcf_db
