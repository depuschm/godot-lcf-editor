#include "lcf_xml.h"

#include <cstdio>

namespace lcf_xml {

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

LogCapture::LogCapture() {
	lcf::LogHandler::SetHandler([](lcf::LogHandler::Level level, std::string_view message, void *self) {
		if (level >= lcf::LogHandler::Level::Warning) {
			auto &out = static_cast<LogCapture *>(self)->messages;
			out.append(message).append("\n");
		}
	}, this);
}

LogCapture::~LogCapture() {
	lcf::LogHandler::SetHandler(nullptr);
}

std::string prepare_body(const std::string &xml) {
	std::string body = xml;
	if (body.rfind("<?xml", 0) == 0) {
		body.erase(0, body.find("?>") + 2);
	}
	for (size_t pos = 0; (pos = body.find('\r', pos)) != std::string::npos; pos += 5) {
		body.replace(pos, 1, "&#13;");
	}
	return body;
}

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

namespace {

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

bool set_leaf_text(std::string &xml, const std::vector<int> &path, const std::string &value, std::string &error) {
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
			return true;
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

} // namespace lcf_xml
