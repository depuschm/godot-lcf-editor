#include "lcf_chipset.h"

#include "tile_rules.h"

#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <cstdint>
#include <cstring>
#include <map>

using namespace godot;

namespace {

uint32_t read_u32_be(const uint8_t *p) {
	return (uint32_t(p[0]) << 24) | (uint32_t(p[1]) << 16) | (uint32_t(p[2]) << 8) | p[3];
}
uint32_t read_u32_le(const uint8_t *p) {
	return uint32_t(p[0]) | (uint32_t(p[1]) << 8) | (uint32_t(p[2]) << 16) | (uint32_t(p[3]) << 24);
}
uint16_t read_u16_le(const uint8_t *p) {
	return uint16_t(p[0] | (p[1] << 8));
}

struct Rgb {
	uint8_t r, g, b;
};

// Palette entry 0 of an indexed PNG (colour type 3), if any.
bool png_key_color(const PackedByteArray &bytes, Rgb &out) {
	const uint8_t *d = bytes.ptr();
	const int64_t n = bytes.size();
	if (n < 33 || d[25] != 3) {
		return false;
	}
	for (int64_t pos = 8; pos + 12 <= n;) {
		const uint32_t len = read_u32_be(d + pos);
		if (std::memcmp(d + pos + 4, "PLTE", 4) == 0 && len >= 3 && pos + 8 + 3 <= n) {
			out = { d[pos + 8], d[pos + 9], d[pos + 10] };
			return true;
		}
		pos += 12 + int64_t(len);
	}
	return false;
}

// Palette entry 0 of a BMP with 8 or fewer bits per pixel, if any.
bool bmp_key_color(const PackedByteArray &bytes, Rgb &out) {
	const uint8_t *d = bytes.ptr();
	const int64_t n = bytes.size();
	if (n < 30) {
		return false;
	}
	const uint32_t dib_size = read_u32_le(d + 14);
	const uint16_t bits = dib_size == 12 ? read_u16_le(d + 24) : read_u16_le(d + 28);
	const int64_t palette = 14 + int64_t(dib_size);
	if (bits > 8 || palette + 3 > n) {
		return false;
	}
	out = { d[palette + 2], d[palette + 1], d[palette] }; // stored as BGR(A)
	return true;
}

void make_transparent(const Ref<Image> &img, Rgb key) {
	PackedByteArray data = img->get_data();
	uint8_t *p = data.ptrw();
	for (int64_t i = 0; i + 3 < data.size(); i += 4) {
		if (p[i] == key.r && p[i + 1] == key.g && p[i + 2] == key.b) {
			p[i + 3] = 0;
		}
	}
	img->set_data(img->get_width(), img->get_height(), false, Image::FORMAT_RGBA8, data);
}

// RPG Maker's own format: "XYZ1", u16 width, u16 height, then zlib data holding
// a 256-colour RGB palette followed by one palette index per pixel.
Ref<Image> load_xyz(const PackedByteArray &bytes, String &error) {
	const uint8_t *d = bytes.ptr();
	if (bytes.size() < 8 || std::memcmp(d, "XYZ1", 4) != 0) {
		error = "Not an XYZ image";
		return Ref<Image>();
	}
	const int w = read_u16_le(d + 4);
	const int h = read_u16_le(d + 6);
	const PackedByteArray raw = bytes.slice(8).decompress_dynamic(-1, FileAccess::COMPRESSION_DEFLATE);
	if (raw.size() < 768 + int64_t(w) * h) {
		error = "Damaged XYZ image";
		return Ref<Image>();
	}
	const uint8_t *src = raw.ptr();
	PackedByteArray rgba;
	rgba.resize(int64_t(w) * h * 4);
	uint8_t *out = rgba.ptrw();
	for (int64_t i = 0; i < int64_t(w) * h; ++i) {
		const uint8_t index = src[768 + i];
		out[i * 4 + 0] = src[index * 3 + 0];
		out[i * 4 + 1] = src[index * 3 + 1];
		out[i * 4 + 2] = src[index * 3 + 2];
		out[i * 4 + 3] = index == 0 ? 0 : 255;
	}
	return Image::create_from_data(w, h, false, Image::FORMAT_RGBA8, rgba);
}

} // namespace

Error LcfChipset::load(const String &path) {
	last_error = String();
	const PackedByteArray bytes = FileAccess::get_file_as_bytes(path);
	if (bytes.size() < 8) {
		last_error = "Could not read " + path;
		return ERR_CANT_OPEN;
	}
	const uint8_t *d = bytes.ptr();
	Ref<Image> img;
	Rgb key{};
	bool has_key = false;

	if (d[0] == 0x89 && d[1] == 'P' && d[2] == 'N' && d[3] == 'G') {
		img.instantiate();
		if (img->load_png_from_buffer(bytes) != OK) {
			img.unref();
		}
		has_key = png_key_color(bytes, key);
	} else if (d[0] == 'B' && d[1] == 'M') {
		img.instantiate();
		if (img->load_bmp_from_buffer(bytes) != OK) {
			img.unref();
		}
		has_key = bmp_key_color(bytes, key);
	} else if (std::memcmp(d, "XYZ1", 4) == 0) {
		img = load_xyz(bytes, last_error);
	} else {
		last_error = "Unsupported image format: " + path;
		return ERR_FILE_UNRECOGNIZED;
	}
	if (img.is_null() || img->is_empty()) {
		if (last_error.is_empty()) {
			last_error = "Could not decode " + path;
		}
		return ERR_FILE_CORRUPT;
	}
	img->convert(Image::FORMAT_RGBA8);
	if (has_key) {
		make_transparent(img, key);
	}
	image = img;
	return OK;
}

void LcfChipset::set_image(const Ref<Image> &p_image) {
	image = p_image;
	if (image.is_valid() && image->get_format() != Image::FORMAT_RGBA8) {
		image = image->duplicate();
		image->convert(Image::FORMAT_RGBA8);
	}
}

Ref<Image> LcfChipset::get_image() const {
	return image;
}

String LcfChipset::get_last_error() const {
	return last_error;
}

void LcfChipset::draw_tile(const Ref<Image> &dst, int tile_id, int dst_x, int dst_y, int water_frame, int anim_frame) const {
	const lcf_tiles::Quarters quarters = lcf_tiles::tile_quarters(tile_id, water_frame, anim_frame);
	for (int q = 0; q < 4; ++q) {
		const lcf_tiles::Quarter &src = quarters[q];
		if (src.x < 0) {
			continue;
		}
		dst->blit_rect(image, Rect2i(src.x * 8, src.y * 8, 8, 8),
				Vector2i(dst_x + (q % 2) * 8, dst_y + (q / 2) * 8));
	}
}

Ref<Image> LcfChipset::render_tile(int tile_id, int water_frame, int anim_frame) const {
	Ref<Image> tile = Image::create_empty(TILE_SIZE, TILE_SIZE, false, Image::FORMAT_RGBA8);
	if (image.is_valid()) {
		draw_tile(tile, tile_id, 0, 0, water_frame, anim_frame);
	}
	return tile;
}

Dictionary LcfChipset::build_atlas(const PackedInt32Array &tile_ids, int water_frame, int anim_frame, int columns) const {
	std::map<int, int> slots; // tile id -> atlas index, in ascending id order
	for (int64_t i = 0; i < tile_ids.size(); ++i) {
		slots.emplace(tile_ids[i], 0);
	}
	columns = columns > 0 ? columns : 32;
	const int count = int(slots.size());
	const int rows = count > 0 ? (count + columns - 1) / columns : 1;

	Ref<Image> atlas = Image::create_empty(columns * TILE_SIZE, rows * TILE_SIZE, false, Image::FORMAT_RGBA8);
	Dictionary coords;
	int index = 0;
	for (auto &slot : slots) {
		const Vector2i cell(index % columns, index / columns);
		if (image.is_valid()) {
			draw_tile(atlas, slot.first, cell.x * TILE_SIZE, cell.y * TILE_SIZE, water_frame, anim_frame);
		}
		coords[slot.first] = cell;
		++index;
	}
	Dictionary result;
	result["image"] = atlas;
	result["coords"] = coords;
	result["columns"] = columns;
	return result;
}

void LcfChipset::_bind_methods() {
	ClassDB::bind_method(D_METHOD("load", "path"), &LcfChipset::load);
	ClassDB::bind_method(D_METHOD("set_image", "image"), &LcfChipset::set_image);
	ClassDB::bind_method(D_METHOD("get_image"), &LcfChipset::get_image);
	ClassDB::bind_method(D_METHOD("get_last_error"), &LcfChipset::get_last_error);
	ClassDB::bind_method(D_METHOD("render_tile", "tile_id", "water_frame", "anim_frame"), &LcfChipset::render_tile, DEFVAL(0), DEFVAL(0));
	ClassDB::bind_method(D_METHOD("build_atlas", "tile_ids", "water_frame", "anim_frame", "columns"), &LcfChipset::build_atlas, DEFVAL(0), DEFVAL(0), DEFVAL(32));
}
