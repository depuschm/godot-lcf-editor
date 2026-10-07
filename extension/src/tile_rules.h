#pragma once
// RPG Maker 2000/2003 tile IDs and chipset layout, independent of Godot.
//
// A chipset is 480x256 pixels: 30x16 tiles of 16x16 pixels. Autotiles are drawn
// from 8x8 "quarters", so source positions here are in 8-pixel units.
//
// Tile ID ranges:
//   0..999      water A1 (autotile, combined with deep-water edges)
//   1000..1999  water A2
//   2000..2999  deep water (B)
//   3000..3149  animated tiles C1..C3 (stride 50)
//   4000..4599  ground autotiles D1..D12 (stride 50, pattern 0..49)
//   5000..5143  lower layer tiles (E)
//   10000..10143 upper layer tiles (F)

#include <array>
#include <functional>
#include <vector>

namespace lcf_tiles {

constexpr int WATER_A1 = 0, WATER_A2 = 1000, DEEP_WATER = 2000, ANIMATED = 3000;
constexpr int GROUND = 4000, LOWER = 5000, UPPER = 10000;
constexpr int GROUND_COUNT = 12, LOWER_COUNT = 144, UPPER_COUNT = 144;

// Sides of a tile that border different terrain, and corners cut by a diagonal neighbour.
enum Side { LEFT = 1, TOP = 2, RIGHT = 4, BOTTOM = 8 };
enum Corner { TL = 1, TR = 2, BR = 4, BL = 8 };

// Autotile pattern (0..46) for a set of open sides and cut corners. A corner only
// counts as cut when both of its sides are closed.
inline int encode_pattern(int sides, int corners) {
	const bool l = sides & LEFT, t = sides & TOP, r = sides & RIGHT, b = sides & BOTTOM;
	auto cut = [&](int c) { return (corners & c) ? 1 : 0; };
	switch (sides) {
		case 0: return cut(TL) + cut(TR) * 2 + cut(BR) * 4 + cut(BL) * 8;
		case LEFT: return 16 + cut(TR) + cut(BR) * 2;
		case TOP: return 20 + cut(BR) + cut(BL) * 2;
		case RIGHT: return 24 + cut(BL) + cut(TL) * 2;
		case BOTTOM: return 28 + cut(TL) + cut(TR) * 2;
		case LEFT | RIGHT: return 32;
		case TOP | BOTTOM: return 33;
		case TOP | LEFT: return 34 + cut(BR);
		case TOP | RIGHT: return 36 + cut(BL);
		case BOTTOM | RIGHT: return 38 + cut(TL);
		case BOTTOM | LEFT: return 40 + cut(TR);
		case LEFT | TOP | RIGHT: return 42;
		case TOP | LEFT | BOTTOM: return 43;
		case LEFT | BOTTOM | RIGHT: return 44;
		case TOP | RIGHT | BOTTOM: return 45;
		default: return (l && t && r && b) ? 46 : 0;
	}
}

struct Pattern {
	int sides = 0;
	int corners = 0;
};

// Inverse of encode_pattern, built once by enumerating every combination. Corners are
// enumerated in ascending order, so the first match uses only corners that matter.
inline const std::array<Pattern, 47> &pattern_table() {
	static const std::array<Pattern, 47> table = [] {
		std::array<Pattern, 47> t{};
		std::array<bool, 47> seen{};
		for (int sides = 0; sides < 16; ++sides) {
			for (int corners = 0; corners < 16; ++corners) {
				const int id = encode_pattern(sides, corners);
				if (!seen[id]) {
					seen[id] = true;
					t[id] = { sides, corners };
				}
			}
		}
		return t;
	}();
	return table;
}

// Source of one 8x8 quarter, in 8-pixel units within the chipset. x < 0 means "nothing".
struct Quarter {
	int x = -1;
	int y = -1;
};

// The four quarters of a tile, in the order top-left, top-right, bottom-left, bottom-right.
using Quarters = std::array<Quarter, 4>;

namespace detail {

constexpr int QUARTER_CORNER[4] = { TL, TR, BL, BR };

inline bool is_left(int q) { return q == 0 || q == 2; }
inline bool is_top(int q) { return q < 2; }

inline Quarter tile_quarter(int tile_x, int tile_y, int q) {
	return { tile_x * 2 + (is_left(q) ? 0 : 1), tile_y * 2 + (is_top(q) ? 0 : 1) };
}

// Ground autotile block: 3x4 tiles. Tile (0,0) is the preview, (2,0) holds the cut
// inner corners, and the 3x3 area below is a framed patch of the terrain.
inline Quarters ground(int block, int pattern) {
	const int bx = block < 4 ? (block % 2) * 3 : 6 + (block % 2) * 3;
	const int by = block < 4 ? 8 + (block / 2) * 4 : ((block - 4) / 2) * 4;
	Quarters out;
	if (pattern == 49) { // preview tile
		for (int q = 0; q < 4; ++q) out[q] = tile_quarter(bx, by, q);
		return out;
	}
	if (pattern > 46) pattern = 0; // 47 and 48 look like the plain centre tile
	const Pattern p = pattern_table()[pattern];
	const bool l = p.sides & LEFT, t = p.sides & TOP, r = p.sides & RIGHT, b = p.sides & BOTTOM;
	for (int q = 0; q < 4; ++q) {
		if (p.corners & QUARTER_CORNER[q]) {
			out[q] = tile_quarter(bx + 2, by, q);
			continue;
		}
		const int col = (l && r) ? (is_left(q) ? 0 : 2) : l ? 0 : r ? 2 : 1;
		const int row = (t && b) ? (is_top(q) ? 1 : 3) : t ? 1 : b ? 3 : 2;
		out[q] = tile_quarter(bx + col, by + row, q);
	}
	return out;
}

// Water: columns 0-2 are the three animation frames of water A1 (rows 0-3: shore
// shapes; rows 4-7: open water and deep-water edges), columns 3-5 rows 0-3 are A2.
// `block` is 0 (A1), 1 (A2) or 2 (deep water); `deep` holds one bit per quarter.
inline Quarters water(int block, int deep, int pattern, int frame) {
	Quarters out;
	if (pattern > 46) return out;
	const Pattern p = pattern_table()[pattern];
	const int shore_col = frame + (block == 1 ? 3 : 0);
	for (int q = 0; q < 4; ++q) {
		const bool h_open = p.sides & (is_left(q) ? LEFT : RIGHT);
		const bool v_open = p.sides & (is_top(q) ? TOP : BOTTOM);
		int shore = -1;
		if (h_open && v_open) shore = 0;
		else if (h_open) shore = 1;
		else if (v_open) shore = 2;
		else if (p.corners & QUARTER_CORNER[q]) shore = 3;

		const int bit = (deep >> q) & 1;
		if (shore >= 0) {
			out[q] = tile_quarter(shore_col, shore, q);
			if (bit && pattern != 0) { // deep-water edge drawn over the shore quarter
				out[q] = tile_quarter(frame, 4 + (block == 2 ? 2 : 1), q);
			}
		} else {
			const int row = block == 2 ? 4 + (bit ^ 3) : 4 + bit;
			out[q] = tile_quarter(frame, row, q);
		}
	}
	return out;
}

} // namespace detail

// Quarters for any tile ID. `water_frame` is 0..2, `anim_frame` is 0..3.
inline Quarters tile_quarters(int id, int water_frame = 0, int anim_frame = 0) {
	using namespace detail;
	Quarters out;
	if (id >= 0 && id < ANIMATED) {
		return water(id / 1000, (id % 1000) / 50, id % 50, water_frame);
	}
	if (id >= ANIMATED && id < ANIMATED + 150) {
		const int col = 3 + (id - ANIMATED) / 50;
		for (int q = 0; q < 4; ++q) out[q] = tile_quarter(col, 4 + anim_frame, q);
		return out;
	}
	if (id >= GROUND && id < GROUND + GROUND_COUNT * 50) {
		return ground((id - GROUND) / 50, (id - GROUND) % 50);
	}
	int tx = -1, ty = -1;
	if (id >= LOWER && id < LOWER + LOWER_COUNT) {
		const int n = id - LOWER;
		tx = n < 96 ? 12 + n % 6 : 18 + (n - 96) % 6;
		ty = n < 96 ? n / 6 : (n - 96) / 6;
	} else if (id >= UPPER && id < UPPER + UPPER_COUNT) {
		const int n = id - UPPER;
		tx = n < 48 ? 18 + n % 6 : 24 + (n - 48) % 6;
		ty = n < 48 ? 8 + n / 6 : (n - 48) / 6;
	}
	if (tx >= 0) {
		for (int q = 0; q < 4; ++q) out[q] = tile_quarter(tx, ty, q);
	}
	return out;
}


// --- painting -------------------------------------------------------------------
// When a tile is painted, RPG Maker picks the autotile variant of it and of its eight
// neighbours from what surrounds them. `at(x, y)` returns the current tile ID; cells
// outside the map count as the same terrain (no border at the map edge).

using TileAt = std::function<int(int x, int y)>;

inline bool is_water(int id) { return id >= 0 && id < ANIMATED; }
inline bool is_deep_water(int id) { return id >= DEEP_WATER && id < ANIMATED; }
inline bool is_ground_autotile(int id) { return id >= GROUND && id < GROUND + GROUND_COUNT * 50; }
inline bool is_autotile(int id) { return is_water(id) || is_ground_autotile(id); }

// Water shores connect to any water and to the animated tiles (C block).
inline bool joins_water(int id) { return is_water(id) || (id >= ANIMATED && id < GROUND); }

// The variant of `id` at (x, y) for its current neighbours; non-autotiles are returned unchanged.
inline int autotile_variant(const TileAt &at, int width, int height, int x, int y, int id) {
	auto inside = [&](int nx, int ny) { return nx >= 0 && ny >= 0 && nx < width && ny < height; };

	auto pattern_for = [&](const std::function<bool(int)> &same) {
		auto same_at = [&](int dx, int dy) { return !inside(x + dx, y + dy) || same(at(x + dx, y + dy)); };
		int sides = 0, corners = 0;
		if (!same_at(-1, 0)) sides |= LEFT;
		if (!same_at(0, -1)) sides |= TOP;
		if (!same_at(1, 0)) sides |= RIGHT;
		if (!same_at(0, 1)) sides |= BOTTOM;
		if (!same_at(-1, -1)) corners |= TL;
		if (!same_at(1, -1)) corners |= TR;
		if (!same_at(1, 1)) corners |= BR;
		if (!same_at(-1, 1)) corners |= BL;
		return encode_pattern(sides, corners);
	};

	if (is_ground_autotile(id)) {
		const int block = (id - GROUND) / 50;
		const int pattern = pattern_for([&](int n) { return is_ground_autotile(n) && (n - GROUND) / 50 == block; });
		return GROUND + block * 50 + pattern;
	}
	if (!is_water(id)) {
		return id;
	}

	const int type = id / 1000; // 0 A1, 1 A2, 2 deep
	const int shore = pattern_for(joins_water);

	// Deep-water edges, one bit per quarter (TL 1, TR 2, BL 4, BR 8): deep water
	// borders shallow water; shallow water borders deep water.
	auto blocked = [&](int dx, int dy) {
		if (!inside(x + dx, y + dy)) return type == 2;
		const int n = at(x + dx, y + dy);
		if (type == 2) return !(is_deep_water(n) || !joins_water(n));
		return is_deep_water(n);
	};
	auto deep_diagonal = [&](int dx, int dy) {
		return inside(x + dx, y + dy) && is_deep_water(at(x + dx, y + dy));
	};
	const bool n = blocked(0, -1), e = blocked(1, 0), s = blocked(0, 1), w = blocked(-1, 0);
	int deep = 0;
	if (type == 2) {
		if (n && w && !deep_diagonal(-1, -1)) deep |= 1;
		if (n && e && !deep_diagonal(1, -1)) deep |= 2;
		if (s && w && !deep_diagonal(-1, 1)) deep |= 4;
		if (s && e && !deep_diagonal(1, 1)) deep |= 8;
	} else {
		if (n && w) deep |= 1;
		if (n && e) deep |= 2;
		if (s && w) deep |= 4;
		if (s && e) deep |= 8;
	}
	return type * 1000 + deep * 50 + shore;
}

// Cells whose variant may change when `painted` cells change: the cells and their
// eight neighbours, inside the map, without duplicates.
inline std::vector<int> affected_cells(const std::vector<int> &painted, int width, int height) {
	std::vector<char> mark(size_t(width) * height, 0);
	std::vector<int> out;
	for (int cell : painted) {
		const int cx = cell % width, cy = cell / width;
		for (int dy = -1; dy <= 1; ++dy) {
			for (int dx = -1; dx <= 1; ++dx) {
				const int x = cx + dx, y = cy + dy;
				if (x < 0 || y < 0 || x >= width || y >= height) continue;
				const int i = y * width + x;
				if (!mark[i]) {
					mark[i] = 1;
					out.push_back(i);
				}
			}
		}
	}
	return out;
}

} // namespace lcf_tiles
