# Meeting Minutes Server (FastAPI + faster-whisper)

## Quick start (dev)
python -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env
python main.py
# open http://127.0.0.1:8000/healthz

### GPU notes (เช่น RTX 3060 Ti)
- ติดตั้งไดรเวอร์ NVIDIA ให้ `nvidia-smi` ใช้งานได้ จากนั้น activate venv ตามขั้นตอนด้านบน
- กำหนด environment:
  ```bash
  export HOST=0.0.0.0          # ฟังทุกอินเทอร์เฟซเมื่อรันเป็นเซิร์ฟเวอร์แยก
  export WHISPER_COMPUTE=float16   # บังคับ ctranslate2 ใช้ CUDA ปริมาณหน่วยความจำต่ำลง
  export WHISPER_MODEL=large-v3    # หรือโมเดลที่ต้องการ
  ```
- หากคำสั่ง `uvicorn main:app --host 0.0.0.0 --port 8000` รันสำเร็จแล้วเรียก `/healthz` จะเห็นค่า `compute` เป็น `float16` เมื่อ GPU ถูกใช้งาน

### Speaker diarization (ระบุผู้พูด)
- ติดตั้ง `pyannote.audio` (อยู่ใน `requirements.txt`) และติดตั้ง `torch` เวอร์ชันที่รองรับ GPU เองหากต้องการประสิทธิภาพสูง
- ตั้งค่า token ของ Hugging Face ที่มีสิทธิ์เข้าถึง `pyannote/speaker-diarization-3.1`
  ```bash
  export DIARIZATION_AUTH_TOKEN=<your_hf_token>
  export DIARIZATION_MODEL=pyannote/speaker-diarization-3.1
  export DIARIZATION_DEVICE=cuda   # หรือ cpu
  ```
- เมื่อ `diarize=true` ในคำขอ `/transcribe` หรือ endpoint streaming ผลลัพธ์จะมี `segment.speaker` และ `speaker_segments` สำหรับวิเคราะห์ผู้พูด

### ระบบคิว / จำกัดงานพร้อมกัน
- ใช้ environment `TRANSCRIBE_CONCURRENCY` (default 1) เพื่อกำหนดจำนวนงานถอดเสียงที่รันพร้อมกัน
  ```bash
  export TRANSCRIBE_CONCURRENCY=2
  uvicorn main:app --host 127.0.0.1 --port 8001 --proxy-headers --forwarded-allow-ips='*'
  ```
- เมื่อจำนวนคำขอเกินกว่าค่า concurrency จะถูกพักคิวและเมื่อถึงคิวแล้ว response จะมีข้อมูล `queue.job_id`, `wait_seconds`, `position_on_enqueue`
- ใน endpoint แบบสตรีม ฝั่ง client จะได้รับอีเวนต์ `event: queued` แสดงลำดับคิวก่อนเข้าสู่การประมวลผล

### ส่งออกไฟล์
- Endpoint `POST /export` รองรับพารามิเตอร์:
  ```json
  {
    "format": "txt" หรือ "docx",
    "transcript": "...",
    "report_markdown": "...",
    "include_transcript": true,
    "include_report": false
  }
  ```
- สำหรับ `.docx` ต้องติดตั้ง `python-docx` (มีใน `requirements.txt` แล้ว)
- ตอบกลับเป็นไฟล์พร้อม header `Content-Disposition` เพื่อให้ฝั่ง client ดาวน์โหลดได้

### Reverse proxy ด้วย Nginx
- ให้ uvicorn ทำงานภายในเครื่อง: `uvicorn main:app --host 127.0.0.1 --port 8001 --proxy-headers --forwarded-allow-ips='*'`
- นำ `nginx.conf.example` ไปใช้เป็นต้นแบบ (copy ไป `/etc/nginx/sites-available/meeting_minutes` แล้วแก้ `server_name` และ path ของ cert/key)
- เปิดใช้ config (`ln -s ...`, `nginx -t`, `systemctl reload nginx`) แล้วชี้โดเมนมาที่เครื่องดังกล่าว
- เมื่อเข้าผ่าน HTTPS ต้องตั้ง `SERVER_BASE_URL=https://<โดเมน>` ในฝั่ง Flutter/Dart defines ด้วย

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
