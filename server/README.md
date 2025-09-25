# Meeting Minutes Server (FastAPI + faster-whisper)

## Quick start (dev)
python -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env
python main.py
# open http://127.0.0.1:8000/healthz

## Build a standalone binary (no Python needed for users)
Prereq: Python 3.11+ and PyInstaller on the build machine.

Option A: Use the helper script
```
bash ../scripts/build_server_binary.sh
# Output: dist/meeting_server (or meeting_server.exe on Windows)
```

Option B: Manual PyInstaller command
```
pip install pyinstaller
pyinstaller --clean --onefile --name meeting_server \
  --collect-all faster_whisper --collect-all ctranslate2 --collect-all tokenizers \
  main.py
```

Run the binary directly:
```
./dist/meeting_server           # Windows: dist\\meeting_server.exe
# then open http://127.0.0.1:8000/healthz
```

Environment overrides honored by the binary:
- HOST/PORT or MEETING_SERVER_HOST/MEETING_SERVER_PORT
- FFMPEG path via MEETING_SERVER_FFMPEG or FFMPEG_BIN
- WHISPER_MODEL may be a model name (e.g. large-v3) or a local path

## Bundle into the Flutter app
Build the binary, then copy it next to the Flutter bundle so the app starts it automatically:
```
# Linux
flutter build linux
bash ../scripts/package_flutter_with_server.sh linux

# Windows
flutter build windows
bash ../scripts/package_flutter_with_server.sh windows

# macOS
flutter build macos
bash ../scripts/package_flutter_with_server.sh macos
```
The Flutter app looks for `meeting_server` near the app bundle or in `server/dist`. You can also point to an explicit path via env `MEETING_APP_SERVER_BINARY`.

## Notes on FFmpeg and preprocessing
If you plan to use `preprocess=true`, the server needs FFmpeg. You can:
- Install FFmpeg system-wide, or
- Ship an FFmpeg binary alongside `meeting_server` and set `MEETING_SERVER_FFMPEG=./ffmpeg` (or `ffmpeg.exe` on Windows).
