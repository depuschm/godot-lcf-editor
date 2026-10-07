#!/usr/bin/env bash
# Builds EasyRPG Player with the patches in this folder and prints the path of the
# executable. Needs git, CMake, a C++17 compiler and the Player's libraries (on
# Debian/Ubuntu: libsdl2-dev libpixman-1-dev libpng-dev libfmt-dev libfreetype-dev
# libharfbuzz-dev nlohmann-json3-dev libinih-dev libexpat1-dev libicu-dev).
#
#   runtime/easyrpg-player/build.sh [work-dir]
#
# Extra CMake options can be passed in PLAYER_CMAKE_ARGS, e.g.
#   PLAYER_CMAKE_ARGS="-DPLAYER_AUDIO_BACKEND=OFF" runtime/easyrpg-player/build.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${1:-$HERE/build}"
# The EasyRPG Player commit the patches are made for.
BASE=0de2a9ab466a133ac6e192a84bd761a1d81f5f14

mkdir -p "$WORK"
if [ ! -d "$WORK/Player/.git" ]; then
	git clone --quiet https://github.com/EasyRPG/Player "$WORK/Player" >&2
fi
cd "$WORK/Player"
git fetch --quiet origin "$BASE" >&2 || true
git checkout --quiet --force "$BASE" >&2
git clean --quiet -fd src >&2
for patch in "$HERE"/*.patch; do
	git apply --whitespace=nowarn "$patch" >&2
done

# shellcheck disable=SC2086
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DPLAYER_TARGET_PLATFORM=SDL2 \
	-DPLAYER_BUILD_LIBLCF=ON -DPLAYER_ENABLE_TESTS=OFF -DPLAYER_WITH_LHASA=OFF \
	${PLAYER_CMAKE_ARGS:-} >&2
cmake --build build --parallel "$(nproc 2>/dev/null || echo 4)" >&2
echo "$WORK/Player/build/easyrpg-player"
