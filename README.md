# Meeting Minutes (faster-whisper + Flutter) – Stable Starter (No Recording)

- Desktop supervisor auto-starts server (127.0.0.1:8000), no auto-shutdown on hot-restart.
- Server uses uvicorn host=127.0.0.1, reload=False.
- Endpoints: /healthz, /transcribe, /summarize, /shutdown.

## รันเซิร์ฟเวอร์ด้วย Docker

ต้องติดตั้ง [Docker](https://docs.docker.com/get-docker/) และ [Docker Compose](https://docs.docker.com/compose/) ก่อน จากนั้นที่โฟลเดอร์โปรเจกต์รันคำสั่ง:

```bash
docker compose up --build
```

คำสั่งนี้จะ:

- สร้างอิมเมจจาก `server/Dockerfile`
- เปิดคอนเทนเนอร์ชื่อ `meeting-server` และแม็พพอร์ต `8000` ออกมาที่เครื่อง host
- เก็บ cache ของโมเดลของ HuggingFace ไว้ใน volume `whisper-cache` เพื่อให้โหลดโมเดลเร็วขึ้น

ค่าเริ่มต้น:

- โมเดล: `large-v3`
- ภาษา: `th`
- คุณภาพ: `accurate`
- ประเภทการคำนวณ: `int8` (เหมาะกับ CPU)

ถ้าต้องการปรับค่าเหล่านี้ให้ตั้ง environment variable ก่อนรัน compose เช่น:

```bash
export WHISPER_MODEL=small
export WHISPER_LANG=auto
docker compose up --build
```

เสร็จแล้วเปิด `http://127.0.0.1:8000/healthz` เพื่อตรวจสอบสถานะ หรือให้ Flutter app เชื่อมต่อไปที่ `http://127.0.0.1:8000` ได้ทันที

## สร้างตัวติดตั้ง Windows (Inno Setup)

หากต้องการแพ็กแอปพร้อมเซิร์ฟเวอร์สำหรับผู้ใช้ Windows ให้ทำตามขั้นตอนโดยรวมดังนี้ (รายละเอียดมีใน `scripts/windows/README.md`):

1. **สร้างไบนารีของเซิร์ฟเวอร์** บน Windows ด้วย PyInstaller
   ```powershell
   python -m venv server\.venv
   server\.venv\Scripts\activate
   pip install -r server\requirements.txt pyinstaller
   cd server
   pyinstaller --clean --onefile --name meeting_server ^
     --collect-all faster_whisper --collect-all ctranslate2 --collect-all tokenizers ^
     main.py
   ```
   ผลลัพธ์อยู่ที่ `server\dist\meeting_server.exe`

2. **Build Flutter Windows bundle**
   ```powershell
   cd flutter_app
   flutter build windows
   ```

3. **คัดลอก meeting_server.exe** ไปไว้ที่ `flutter_app\build\windows\x64\runner\Release\` (ถ้ามี ffmpeg.exe ให้คัดลอกมาด้วย)

4. **รัน Inno Setup** ด้วยสคริปต์ `scripts\windows\meeting_minutes_app.iss`
   ```powershell
   iscc.exe scripts\windows\meeting_minutes_app.iss
   ```
   แฟ้มติดตั้งที่ได้อยู่ใน `dist\windows\MeetingMinutesSetup.exe`

ตัวติดตั้งนี้จะวางทั้ง Flutter app และ `meeting_server.exe` ให้พร้อมใช้งานบน Windows โดยไม่ต้องติดตั้ง Python เพิ่มเติม
# DCT_Meeting_Report
