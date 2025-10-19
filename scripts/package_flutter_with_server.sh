#!/usr/bin/env bash
set -euo pipefail

# Copy the built server binary into the Flutter app bundle for easy distribution.
# Usage: scripts/package_flutter_with_server.sh [linux|windows|macos]

target="${1:-linux}"
here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)

server_bin_linux="$repo_root/server/dist/meeting_server"
server_bin_windows="$repo_root/server/dist/meeting_server.exe"

case "$target" in
  linux)
    bin_src="$server_bin_linux"
    dest_dir="$repo_root/client/build/linux/x64/release/bundle"
    dest_name="meeting_server"
    ;;
  windows)
    bin_src="$server_bin_windows"
    dest_dir="$repo_root/client/build/windows/x64/runner/Release"
    dest_name="meeting_server.exe"
    ;;
  macos)
    bin_src="$server_bin_linux" # macOS will also produce a non-.exe artifact; adjust if you build on macOS
    # Try to detect the .app path; fall back to common default
    app_path=$(ls -d "$repo_root"/client/build/macos/Build/Products/Release/*.app 2>/dev/null | head -n1 || true)
    if [[ -z "$app_path" ]]; then
      app_path="$repo_root/client/build/macos/Build/Products/Release/meeting_minutes_app.app"
    fi
    dest_dir="$app_path/Contents/MacOS"
    dest_name="meeting_server"
    ;;
  *)
    echo "Unknown target: $target" >&2
    exit 1
    ;;
esac

if [[ ! -f "$bin_src" ]]; then
  echo "Binary not found: $bin_src. Build it first (scripts/build_server_binary.sh)." >&2
  exit 2
fi

mkdir -p "$dest_dir"
cp -f "$bin_src" "$dest_dir/$dest_name"
chmod +x "$dest_dir/$dest_name" || true

echo "Copied $bin_src -> $dest_dir/$dest_name"
echo "Ensure your app has permissions to execute bundled binaries."
