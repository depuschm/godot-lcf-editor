#pragma once
// Reading and writing single liblcf structures (a database entry, a map event, ...)
// as XML, independent of Godot. The XML is liblcf's own format, so every field is
// named after liblcf's field tables and parsing goes through liblcf's reader: what
// comes out is exactly what liblcf would read from a whole XML file.

// liblcf's internal field tables; not part of its installed API, but available
// because liblcf is built from the pinned submodule.
#include "reader_struct.h"

#include <lcf/log_handler.h>
#include <lcf/reader_xml.h>
#include <lcf/saveopt.h>
#include <lcf/writer_xml.h>

#include <sstream>
#include <string>
#include <vector>

namespace lcf_xml {

template <class T>
std::string write(const T &value, lcf::EngineVersion engine) {
	std::ostringstream out;
	lcf::XmlWriter writer(out, engine);
	lcf::Struct<T>::WriteXml(value, writer);
	return out.str();
}

// Name of the outermost element, e.g. "Actor" for <Actor id="0001">.
std::string root_name(const std::string &xml);

// Collects liblcf warnings and errors while it is alive.
struct LogCapture {
	std::string messages;
	LogCapture();
	~LogCapture();
};

// Removes an <?xml ...?> declaration and protects "\r" (XML parsers turn "\r\n"
// into "\n"; a character reference keeps it).
std::string prepare_body(const std::string &xml);

// Parses `xml` (as produced by write()) into a fresh `out`. The root element must be
// `expected_root`. On any problem liblcf reports, returns false with `error` set.
template <class T>
bool read(T &out, const std::string &xml, const std::string &expected_root, std::string &error) {
	const std::string root = root_name(xml);
	if (root != expected_root) {
		error = "Expected <" + expected_root + "> but got <" + root + ">";
		return false;
	}
	// liblcf's readers expect a wrapper around a structure (like <LDB> around
	// <Database> in whole files), so the entry goes inside <Entry>.
	std::istringstream in("<Entry>" + prepare_body(xml) + "</Entry>");
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

// Escapes text the way liblcf's XML writer does.
std::string escape_text(const std::string &value);

// Sets the text of one element of `xml`. `path` holds child-element indices below the
// root element, e.g. {0} for the first field or {16, 0, 2} for a field inside a nested
// structure. Only elements without child elements can be set. The value is plain text
// and is escaped here.
bool set_leaf_text(std::string &xml, const std::vector<int> &path, const std::string &value, std::string &error);

} // namespace lcf_xml
