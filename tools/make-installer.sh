#!/usr/bin/env bash
# Windows インストーラ（AnchorPlayer-Setup-<version>.exe）を作る。
#
#   bash tools/make-installer.sh
#
# 事前に `flutter build windows` を済ませておくこと（Release フォルダを固める）。
# バージョンは pubspec.yaml から読む。ここにも .iss にも数字を書かない。
set -euo pipefail

cd "$(dirname "$0")/.."

RELEASE_DIR="build/windows/x64/runner/Release"
if [ ! -f "$RELEASE_DIR/anchor_player.exe" ]; then
  echo "エラー: $RELEASE_DIR に exe がない。先に flutter build windows を実行すること。" >&2
  exit 1
fi

# pubspec.yaml の "version: 0.7.1+14" から 0.7.1 を取り出す。
VERSION=$(grep -m1 '^version:' pubspec.yaml | sed -E 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
if [ -z "$VERSION" ]; then
  echo "エラー: pubspec.yaml からバージョンを読めなかった。" >&2
  exit 1
fi

# winget はユーザー領域に入れることがあるので候補を順に見る。
ISCC=""
for c in \
  "$LOCALAPPDATA/Programs/Inno Setup 6/ISCC.exe" \
  "/c/Users/$USERNAME/AppData/Local/Programs/Inno Setup 6/ISCC.exe" \
  "/c/Program Files (x86)/Inno Setup 6/ISCC.exe" \
  "/c/Program Files/Inno Setup 6/ISCC.exe"
do
  [ -f "$c" ] && ISCC="$c" && break
done
if [ -z "$ISCC" ]; then
  echo "エラー: Inno Setup (ISCC.exe) が見つからない。" >&2
  echo "  winget install -e --id JRSoftware.InnoSetup" >&2
  exit 1
fi

mkdir -p build/dist
echo "Anchor Player $VERSION のインストーラを作成中..."
"$ISCC" "//DAppVersion=$VERSION" "installer/anchor_player.iss" | tail -5

OUT="build/dist/AnchorPlayer-Setup-$VERSION.exe"
if [ -f "$OUT" ]; then
  SIZE=$(stat -c%s "$OUT" | awk '{printf "%.1f MB", $1/1048576}')
  echo "完成: $OUT ($SIZE)"
else
  echo "エラー: 出力が見つからない。" >&2
  exit 1
fi
