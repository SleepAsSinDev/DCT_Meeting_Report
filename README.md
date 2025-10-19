# Meeting Minutes (Remote Transcription + Reporting)

โครงการนี้ประกอบด้วย **เซิร์ฟเวอร์ FastAPI** สำหรับถอดเสียง/สรุปผล และ **แอปเดสก์ท็อป Flutter** สำหรับผู้ใช้ปลายทาง ทั้งสองส่วนถูกแยกโฟลเดอร์ชัดเจน (`server/`, `client/`) เพื่อให้ deploy แยกได้สะดวก

## ไฮไลต์
- **ถอดเสียงด้วย faster-whisper** (รองรับ GPU/CPU, ปรับโมเดลผ่าน environment variable)
- **ระบบคิว** จำกัดจำนวนงานพร้อมกัน (`TRANSCRIBE_CONCURRENCY`) และส่งสถานะคิวแบบสตรีม
- **Speaker diarization** (ทางเลือก) ผ่าน `pyannote.audio`
- **สรุปรายงาน Markdown** จาก transcript
- **ส่งออกไฟล์** เลือก transcript/report เป็น `.txt` หรือ `.docx`
- **Flutter client** แสดง transcript สด, รายงาน Markdown, ปุ่มส่งออก และแสดงสถานะคิว/การเชื่อมต่อ

## โครงสร้างรีโป
```
client/   # Flutter desktop app (Windows, macOS, Linux)
server/   # FastAPI + faster-whisper backend
scripts/  # Utility scripts (แพ็ก Windows, คัดลอก server binary ฯลฯ)
docker-compose.yml
```

---

## การตั้งค่าเซิร์ฟเวอร์

### ตัวเลือก 1: Docker Compose
ต้องติดตั้ง [Docker](https://docs.docker.com/get-docker/) และ [Docker Compose](https://docs.docker.com/compose/) ก่อน จากนั้นรัน:
```bash
docker compose up --build
```
**หมายเหตุ**
- build จาก `server/Dockerfile`
- เปิดพอร์ต 8000
- เก็บ cache โมเดลไว้ใน volume `whisper-cache`

ปรับโมเดล/ภาษา/โหมดคุณภาพได้ด้วย environment variables ก่อนรัน `docker compose` เช่น:
```bash
export WHISPER_MODEL=small
export WHISPER_LANG=auto
docker compose up --build
```
ตรวจสอบสถานะได้ที่ `http://127.0.0.1:8000/healthz`

### ตัวเลือก 2: รันด้วย Python (รองรับ GPU)
1. เตรียมเครื่องให้ `nvidia-smi` ใช้งานได้ (หากต้องใช้ GPU)
2. ติดตั้ง Python 3.10+, Git แล้วสร้าง venv
   ```bash
   cd server
   python -m venv .venv
   source .venv/bin/activate   # Windows: .venv\Scripts\activate
   pip install --upgrade pip
   pip install -r requirements.txt
   ```
3. ตั้ง environment variables ที่ต้องการ เช่น:
   ```bash
   export HOST=0.0.0.0
   export PORT=8000
   export WHISPER_MODEL=large-v3
   export WHISPER_COMPUTE=float16        # ใช้ GPU
   export TRANSCRIBE_CONCURRENCY=2
   # ถ้าเปิด diarization
   export DIARIZATION_AUTH_TOKEN=<hf_token>
   export DIARIZATION_DEVICE=cuda
   ```
4. รันเซิร์ฟเวอร์:
   ```bash
   uvicorn main:app --host ${HOST:-0.0.0.0} --port ${PORT:-8000}
   ```

### Reverse Proxy ผ่าน Nginx (ทางเลือก)
- รัน uvicorn ภายในเครื่อง (เช่น 127.0.0.1:8001)
- นำ `server/nginx.conf.example` ไปปรับใช้, ตั้งค่า SSL ตามต้องการ
- reload Nginx แล้วให้ client ใช้ URL แบบ https://your-domain

---

## การใช้งานระบบคิว
- ปรับ `TRANSCRIBE_CONCURRENCY` เพื่อจำกัดจำนวนงานที่ถอดเสียงพร้อมกัน
- ถ้าคิวเต็ม endpoint streaming จะส่ง event `{"event":"queued", ...}` ให้ client แจ้งผู้ใช้
- เมื่อถึงคิวแล้วจะเริ่มถอดเสียงและส่ง `wait_seconds`, `job_id` กลับมาพร้อมผลลัพธ์

---

## การส่งออกไฟล์
- เรียก `POST /export` บนเซิร์ฟเวอร์:
  ```json
  {
    "format": "txt" หรือ "docx",
    "transcript": "ข้อความถอดเสียง",
    "report_markdown": "รายงาน Markdown",
    "include_transcript": true,
    "include_report": false
  }
  ```
- หากเลือก `docx` ต้องติดตั้ง `python-docx` (มีอยู่ใน `server/requirements.txt`)
- Flutter client มี UI ให้เลือกฟอร์แมต/เนื้อหา แล้วดาวน์โหลดไฟล์ผ่าน dialog

---

## การใช้งานฝั่ง Client (Flutter desktop)
1. ติดตั้ง Flutter SDK (รองรับ Windows/macOS/Linux)
2. กำหนดค่าการเชื่อมต่อด้วย Dart define แล้วรัน/บิลด์:
   ```bash
   cd client
   flutter run \
     --dart-define=SERVER_BASE_URL=http://<ip หรือ โดเมน>:8000

   # หรือบิลด์:
   flutter build windows \
     --dart-define=SERVER_BASE_URL=http://<ip หรือ โดเมน>:8000
   ```
3. แอปจะ:
   - แสดง transcript สดขณะสตรีมผลลัพธ์
   - สร้างรายงาน Markdown (“สร้างรายงาน”)
   - แจ้งสถานะคิว/ความคืบหน้า
   - ส่งออกไฟล์ `.txt/.docx` (“ส่งออกไฟล์”)

---

## เคล็ดลับเพิ่มเติม
- **Speaker diarization**: ต้องตั้ง `DIARIZATION_AUTH_TOKEN` และติดตั้ง `pyannote.audio` + `torch` เวอร์ชัน GPU/CPU ตามเครื่อง
- **FFmpeg preprocess**: ตั้ง `MEETING_SERVER_FFMPEG` ให้อ้างถึงไบนารี ffmpeg หากต้องการคุณภาพเสียงดีขึ้นก่อนถอดเสียง
- **Windows Installer**: ดู `scripts/windows/README.md`, สคริปต์จะใช้งานโฟลเดอร์ `client/` ใหม่แล้ว
- **แพ็ก binary + แอป**: ใช้ `scripts/package_flutter_with_server.sh <platform>` เพื่อคัดลอก server binary ไปฝั่ง client หลัง build

---

พร้อมใช้งานแล้ว! ปรับแต่งเพิ่มหรือเชื่อมต่อระบบอื่นต่อได้ตามต้องการ หากพบปัญหาให้ตรวจสอบ log จาก `/healthz`, คิวในผลลัพธ์ หรือ message บนหน้า UI เพื่อแก้ไข. # DCT_Meeting_Report
