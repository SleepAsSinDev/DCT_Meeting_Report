Windows packaging with Inno Setup

Prerequisites
- Build on Windows (required to produce meeting_server.exe via PyInstaller)
- Installed: Flutter SDK, Inno Setup (adds iscc.exe to PATH)

Steps
1) Build server binary (Windows)
   - Open PowerShell in repo root
   - python -m venv server\.venv
   - server\.venv\Scripts\activate
   - pip install -r server\requirements.txt pyinstaller
   - cd server
   - pyinstaller --clean --onefile --name meeting_server ^
       --collect-all faster_whisper --collect-all ctranslate2 --collect-all tokenizers ^
       main.py
   - Confirm: server\dist\meeting_server.exe exists

2) Build Flutter Windows bundle
   - cd client
   - flutter build windows

3) Place the server binary alongside the app
   - copy server\dist\meeting_server.exe client\build\windows\x64\runner\Release\
   - (Optional) copy ffmpeg.exe to the same folder and set MEETING_SERVER_FFMPEG=.\ffmpeg.exe if you need preprocessing

4) Build installer with Inno Setup
   - Open "Inno Setup Compiler", File -> Open -> scripts\windows\meeting_minutes_app.iss
   - Build (or run via command line):
     iscc.exe scripts\windows\meeting_minutes_app.iss
   - Output: dist\windows\MeetingMinutesSetup.exe

Distribution notes
- Ship only the generated installer (MeetingMinutesSetup.exe). It installs the full Flutter bundle and meeting_server.exe.
- The app launches the server automatically. No Python or venv required for users.

Troubleshooting
- If the app UI shows it cannot start the server, confirm meeting_server.exe is present in the install folder and try running it directly. Check Windows Defender/antivirus blocks.
- If using preprocessing=true and ffmpeg is not present, either add ffmpeg.exe next to the app or disable preprocessing.
