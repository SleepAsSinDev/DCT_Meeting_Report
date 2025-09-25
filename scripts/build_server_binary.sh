#!/usr/bin/env bash
set -euo pipefail

# Build a standalone server binary using PyInstaller.
# Works on the current OS/arch of this machine.

here=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "$here/.." && pwd)
server_dir="$repo_root/server"

cd "$server_dir"

if [[ ! -f requirements.txt ]]; then
  echo "requirements.txt not found under $server_dir" >&2
  exit 1
fi

python3 -m venv .venv
source .venv/bin/activate
python -m pip install -U pip wheel
python -m pip install -r requirements.txt pyinstaller

pyinstaller --clean --onefile --name meeting_server \
  --collect-all faster_whisper --collect-all ctranslate2 --collect-all tokenizers \
  main.py

echo
echo "Built binary: $server_dir/dist/meeting_server (or meeting_server.exe on Windows)"
