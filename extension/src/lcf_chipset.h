#pragma once

#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

// An RPG Maker 2000/2003 chipset image (480x256, 16x16 tiles) and the rules to
// compose map tiles from it, including autotiles and water.
class LcfChipset : public RefCounted {
	GDCLASS(LcfChipset, RefCounted)

public:
	static constexpr int TILE_SIZE = 16;

	// Loads a .png, .bmp or .xyz chipset. Palette colour 0 becomes transparent,
	// as in RPG Maker.
	Error load(const String &path);
	void set_image(const Ref<Image> &image);
	Ref<Image> get_image() const;
	String get_last_error() const;

	// One 16x16 tile. water_frame: 0..2, anim_frame: 0..3.
	Ref<Image> render_tile(int tile_id, int water_frame = 0, int anim_frame = 0) const;

	// Composes every distinct tile ID into one atlas image (16x16 cells, `columns`
	// cells per row): { image: Image, coords: { tile_id: Vector2i }, columns: int }.
	Dictionary build_atlas(const PackedInt32Array &tile_ids, int water_frame = 0, int anim_frame = 0, int columns = 32) const;

protected:
	static void _bind_methods();

private:
	void draw_tile(const Ref<Image> &dst, int tile_id, int dst_x, int dst_y, int water_frame, int anim_frame) const;

	Ref<Image> image;
	String last_error;
};

} // namespace godot
