#!/usr/bin/env bash
# Packages a patched EasyRPG Player built by build.sh for download:
#
#   runtime/easyrpg-player/package.sh <work-dir> <out-dir> [--source]
#
# writes <out-dir>/easyrpg-player-patched-<platform>.zip with an easyrpg-player/
# folder (the program, its licence, the patches and a README; on Windows also the
# licences of the libraries linked into it) and, with --source, the complete source
# it was built from as <out-dir>/easyrpg-player-patched-source.tar.gz (the GPL asks
# for the source to come with the program).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(cd "$1" && pwd)"
mkdir -p "$2"
OUT="$(cd "$2" && pwd)"
PLAYER="$WORK/Player"
BASE=$(sed -n 's/^BASE=//p' "$HERE/build.sh")
LIBLCF=$(sed -n 's/^LIBLCF=//p' "$HERE/build.sh")

case "$(uname -s)" in
	MINGW*|MSYS*|CYGWIN*) PLATFORM=windows-x64; NAME=easyrpg-player.exe ;;
	*) PLATFORM="$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m)"; NAME=easyrpg-player ;;
esac
EXE="$(find "$PLAYER/build" -name "$NAME" -type f -not -path '*CMakeFiles*' | head -n 1)"

STAGE="$OUT/stage-$PLATFORM"
rm -rf "$STAGE"
mkdir -p "$STAGE/easyrpg-player/patches"
DIR="$STAGE/easyrpg-player"
cp "$EXE" "$DIR/"
cp "$PLAYER/COPYING" "$DIR/COPYING.txt"
cp "$HERE"/*.patch "$DIR/patches/"
touch "$DIR/.gdignore"  # Godot leaves the folder alone when it is inside a Godot project

if [ "$PLATFORM" = windows-x64 ] && [ -n "${VCPKG_INSTALLATION_ROOT:-}" ]; then
	# Licences of the libraries linked statically into the program
	share="$(cygpath -u "$VCPKG_INSTALLATION_ROOT")/installed/x64-windows-static/share"
	mkdir -p "$DIR/licenses"
	for copyright in "$share"/*/copyright; do
		cp "$copyright" "$DIR/licenses/$(basename "$(dirname "$copyright")").txt"
	done
fi

cat > "$DIR/README.txt" <<EOF
EasyRPG Player with the godot-lcf-editor patches
================================================

This is EasyRPG Player (https://easyrpg.org/player/), built from commit
$BASE
with liblcf $LIBLCF
and the patches in the patches folder:

  0001-pixel-movement.patch   pixel movement (lcf-plugins/pixel_movement.json)
  0002-screen-shaders.patch   screen shaders (lcf-plugins/shaders.json, Shader/*.glsl)

It plays every RPG Maker 2000/2003 game like the normal EasyRPG Player; the new
features only switch on in games set up for them with the godot-lcf-editor plugins
(https://github.com/depuschm/godot-lcf-editor). It is a prototype, not an official
EasyRPG release: please report problems with it to godot-lcf-editor, not to EasyRPG.

Use it with the LCF Editor: put this easyrpg-player folder into your Godot project
(next to project.godot), and Test Play finds it on its own. Or choose the program
under Test Play > Settings.

Licence: GNU General Public License version 3 or later, see COPYING.txt. The complete
source code is easyrpg-player-patched-source.tar.gz on the same release page:
https://github.com/depuschm/godot-lcf-editor/releases
EOF
if [ -d "$DIR/licenses" ]; then
	echo "The licenses folder holds the licences of the libraries built into the program." >> "$DIR/README.txt"
fi

ZIP="$OUT/easyrpg-player-patched-$PLATFORM.zip"
rm -f "$ZIP"
if command -v zip > /dev/null; then
	(cd "$STAGE" && zip -qr -X "$ZIP" easyrpg-player)
else
	(cd "$STAGE" && 7z a -tzip -bso0 "$(cygpath -w "$ZIP" 2>/dev/null || echo "$ZIP")" easyrpg-player)
fi
rm -rf "$STAGE"
echo "$ZIP"

if [ "${3:-}" = --source ]; then
	SRC="$OUT/easyrpg-player-patched-source.tar.gz"
	# The Player with the patches applied and liblcf, without build output and git data
	tar -czf "$SRC" -C "$WORK" --exclude=Player/build --exclude=.git Player
	echo "$SRC"
fi
