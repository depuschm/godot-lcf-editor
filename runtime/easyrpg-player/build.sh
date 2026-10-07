#!/usr/bin/env bash
# Builds EasyRPG Player with the patches in this folder and prints the path of the
# executable. Needs git, CMake, a C++17 compiler and the Player's libraries (on
# Debian/Ubuntu: libsdl2-dev libpixman-1-dev libpng-dev libfmt-dev libfreetype-dev
# libharfbuzz-dev nlohmann-json3-dev libinih-dev libexpat1-dev libicu-dev, and for
# audio libmpg123-dev libsndfile1-dev libvorbis-dev libopusfile-dev libspeexdsp-dev
# libasound2-dev). On Windows (Git Bash) the libraries come from vcpkg, see
# PLAYER_CMAKE_ARGS in .github/workflows/build.yml.
#
#   runtime/easyrpg-player/build.sh [work-dir]
#
# Extra CMake options can be passed in PLAYER_CMAKE_ARGS, e.g.
#   PLAYER_CMAKE_ARGS="-DPLAYER_AUDIO_BACKEND=OFF" runtime/easyrpg-player/build.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${1:-$HERE/build}"
# The EasyRPG Player commit the patches are made for, and the liblcf it is built
# with (the same commit as this repository's thirdparty/liblcf submodule).
BASE=0de2a9ab466a133ac6e192a84bd761a1d81f5f14
LIBLCF=6854310c3432e553fd4ae672ce861899c80c3bd0

mkdir -p "$WORK"
if [ ! -d "$WORK/Player/.git" ]; then
	git clone --quiet -c core.autocrlf=false https://github.com/EasyRPG/Player "$WORK/Player" >&2
fi
cd "$WORK/Player"
git config core.autocrlf false
git fetch --quiet origin "$BASE" >&2 || true
git checkout --quiet --force "$BASE" >&2
git clean --quiet -fd src >&2
for patch in "$HERE"/*.patch; do
	tr -d '\r' < "$patch" | git apply --whitespace=nowarn - >&2
done

# liblcf at a fixed commit (the Player would otherwise clone its master branch)
if [ "$(git -C lib/liblcf rev-parse HEAD 2>/dev/null || true)" != "$LIBLCF" ]; then
	rm -rf lib/liblcf
	git clone --quiet -c core.autocrlf=false https://github.com/EasyRPG/liblcf lib/liblcf >&2
	git -C lib/liblcf checkout --quiet "$LIBLCF" >&2
fi

# shellcheck disable=SC2086
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DPLAYER_TARGET_PLATFORM=SDL2 \
	-DPLAYER_BUILD_LIBLCF=ON -DPLAYER_ENABLE_TESTS=OFF -DPLAYER_WITH_LHASA=OFF \
	"-DPLAYER_VERSION_APPEND=(godot-lcf-editor patches)" \
	${PLAYER_CMAKE_ARGS:-} >&2
cmake --build build --config Release --parallel "$(nproc 2>/dev/null || echo 4)" >&2
for exe in build/Release/easyrpg-player.exe build/easyrpg-player.exe build/easyrpg-player; do
	if [ -f "$exe" ]; then
		echo "$WORK/Player/$exe"
		exit 0
	fi
done
echo "build.sh: the built easyrpg-player was not found" >&2
exit 1
