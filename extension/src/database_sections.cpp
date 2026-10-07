#include "database_sections.h"

// liblcf's internal field tables; not part of its installed API, but available
// because liblcf is built from the pinned submodule.
#include "reader_struct.h"

#include <lcf/log_handler.h>
#include <lcf/reader_xml.h>
#include <lcf/rpg/database.h>
#include <lcf/saveopt.h>
#include <lcf/writer_xml.h>

#include <cstdio>
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

// Name of the outermost element, e.g. "Actor" for <Actor id="0001">.
std::string root_name(const std::string &xml) {
	size_t pos = 0;
	while ((pos = xml.find('<', pos)) != std::string::npos) {
		if (pos + 1 < xml.size() && xml[pos + 1] != '?' && xml[pos + 1] != '!') {
			const size_t end = xml.find_first_of(" \t\r\n/>", pos + 1);
			return xml.substr(pos + 1, end == std::string::npos ? std::string::npos : end - pos - 1);
		}
		++pos;
	}
	return {};
}

// Collects liblcf warnings and errors while parsing.
struct LogCapture {
	std::string messages;
	LogCapture() {
		lcf::LogHandler::SetHandler([](lcf::LogHandler::Level level, std::string_view message, void *self) {
			if (level >= lcf::LogHandler::Level::Warning) {
				auto &out = static_cast<LogCapture *>(self)->messages;
				out.append(message).append("\n");
			}
		}, this);
	}
	~LogCapture() { lcf::LogHandler::SetHandler(nullptr); }
};

template <class T>
bool from_xml(T &out, const std::string &xml, const std::string &expected_root, std::string &error) {
	const std::string root = root_name(xml);
	if (root != expected_root) {
		error = "Expected <" + expected_root + "> but got <" + root + ">";
		return false;
	}
	// liblcf's readers expect a wrapper around a structure (like <LDB> around
	// <Database> in whole files), so the entry goes inside <Entry>.
	std::string body = xml;
	if (body.rfind("<?xml", 0) == 0) {
		body.erase(0, body.find("?>") + 2);
	}
	// XML parsers turn "\r\n" into "\n"; a character reference keeps the "\r".
	for (size_t pos = 0; (pos = body.find('\r', pos)) != std::string::npos; pos += 5) {
		body.replace(pos, 1, "&#13;");
	}
	std::istringstream in("<Entry>" + body + "</Entry>");
	lcf::XmlReader reader(in);
	if (!reader.IsOk()) {
		error = "liblcf was built without XML support";
		return false;
	}
	LogCapture log;
	reader.SetHandler(new lcf::RootXmlHandler<T>(out, "Entry"));
	reader.Parse();
	if (!log.messages.empty()) {
		error = log.messages;
		return false;
	}
	return true;
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

namespace {

// Escapes text the way liblcf's XML writer does.
std::string escape_text(const std::string &value) {
	std::string out;
	for (char c : value) {
		switch (c) {
			case '<': out += "&lt;"; break;
			case '>': out += "&gt;"; break;
			case '&': out += "&amp;"; break;
			case '\n': case '\r': case '\t': out += c; break;
			default:
				if (c >= 0 && c < 32) {
					char temp[10];
					std::snprintf(temp, sizeof(temp), "&#x%04x;", 0xE000 + c);
					out += temp;
				} else {
					out += c;
				}
		}
	}
	return out;
}

struct Tag {
	enum Kind { START, END, EMPTY } kind;
	size_t begin, end; // position of '<' and one past '>'
};

std::vector<Tag> scan_tags(const std::string &xml) {
	std::vector<Tag> tags;
	size_t pos = 0;
	while ((pos = xml.find('<', pos)) != std::string::npos) {
		const size_t close = xml.find('>', pos);
		if (close == std::string::npos) break;
		const char next = pos + 1 < xml.size() ? xml[pos + 1] : 0;
		if (next != '?' && next != '!') {
			Tag::Kind kind = next == '/' ? Tag::END : xml[close - 1] == '/' ? Tag::EMPTY : Tag::START;
			tags.push_back({ kind, pos, close + 1 });
		}
		pos = close + 1;
	}
	return tags;
}

} // namespace

bool set_field(Database &db, const std::string &key, int index, const std::vector<int> &path, const std::string &value, std::string &error) {
	std::string xml = entry_xml(db, key, index);
	if (xml.empty()) {
		error = "No such entry";
		return false;
	}
	if (path.empty()) {
		error = "Empty field path";
		return false;
	}
	const std::vector<Tag> tags = scan_tags(xml);
	// Walk the tags, tracking each element's position among its siblings.
	std::vector<int> current;   // path of the element we are inside (below the root)
	std::vector<int> children;  // number of child elements seen at each depth
	int depth = -1;             // -1 = before the root element
	for (size_t i = 0; i < tags.size(); ++i) {
		const Tag &tag = tags[i];
		if (tag.kind == Tag::END) {
			if (depth > 0) current.pop_back();
			children.pop_back();
			--depth;
			continue;
		}
		if (depth >= 0) {
			current.push_back(children.back()++);
		}
		if (depth >= 0 && current == path) {
			if (tag.kind == Tag::EMPTY) {
				const std::string name = xml.substr(tag.begin + 1, xml.find_first_of(" /", tag.begin + 1) - tag.begin - 1);
				xml.replace(tag.begin, tag.end - tag.begin, "<" + name + ">" + escape_text(value) + "</" + name + ">");
			} else {
				if (i + 1 >= tags.size() || tags[i + 1].kind != Tag::END) {
					error = "This field contains other fields and cannot be set as text";
					return false;
				}
				xml.replace(tag.end, tags[i + 1].begin - tag.end, escape_text(value));
			}
			return set_entry_xml(db, key, index, xml, error);
		}
		if (tag.kind == Tag::EMPTY) {
			if (depth >= 0) current.pop_back();
		} else {
			children.push_back(0);
			++depth;
		}
	}
	error = "No field at that path";
	return false;
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
