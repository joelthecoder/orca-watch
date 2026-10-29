#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
iconset="$root/.build-app/AppIcon.iconset"
mkdir -p "$iconset" "$root/Assets/Orca/ProjectIcon" "$root/.build-app/previews"
for size in 16 32 64 128 256 512 1024; do
  rsvg-convert -w "$size" -h "$size" "$root/Assets/app-icon.svg" > "$root/.build-app/previews/icon-$size.png"
done
for size in 16 32 128 256 512; do
  cp "$root/.build-app/previews/icon-$size.png" "$iconset/icon_${size}x${size}.png"
  double=$((size * 2))
  cp "$root/.build-app/previews/icon-$double.png" "$iconset/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$iconset" -o "$root/Assets/AppIcon.icns"
cp "$root/.build-app/previews/icon-256.png" "$root/Assets/Orca/ProjectIcon/icon.png"
cp "$root/.build-app/previews/icon-1024.png" "$root/Assets/Orca/ProjectIcon/master.png"
