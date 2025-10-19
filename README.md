# Meeting Minutes (faster-whisper + Flutter) – Remote Server Setup

- Flutter desktop app เชื่อมต่อเซิร์ฟเวอร์ FastAPI ที่รันแยกต่างหาก
- เซิร์ฟเวอร์มี endpoint หลัก: `/healthz`, `/transcribe`, `/transcribe_stream`, `/transcribe_stream_upload`, `/summarize`
- รองรับ speaker diarization, ระบบคิว, และการกำหนดโมเดลผ่าน environment variables

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

## รันเซิร์ฟเวอร์บนเครื่อง GPU แยก (เช่น PC ที่มี RTX 3060 Ti)

1. เตรียมเครื่องเซิร์ฟเวอร์
   - อัปเดตไดรเวอร์ NVIDIA ให้ใช้งาน `nvidia-smi` ได้
   - ติดตั้ง Python 3.10+ และ Git
2. โคลนหรือคัดลอกโฟลเดอร์ `server/` ไปไว้บนเครื่องนั้น จาก root ของโปรเจกต์นี้:
   ```bash
   cd server
   python -m venv .venv
   source .venv/bin/activate   # Windows: .venv\Scripts\activate
   pip install --upgrade pip
   pip install -r requirements.txt
   ```
   แพ็กเกจ `faster-whisper` จะติดตั้ง `ctranslate2` เวอร์ชันที่รองรับ CUDA ให้อัตโนมัติ (ต้องมีไดรเวอร์/Runtime ของ CUDA เพียงพอ)
3. กำหนด environment variables ให้เซิร์ฟเวอร์ฟังทุกอินเทอร์เฟซและบังคับให้ใช้ GPU:
   ```bash
   export HOST=0.0.0.0          # Windows PowerShell: setx HOST 0.0.0.0
   export PORT=8000             # ปรับได้ตามต้องการ
   export WHISPER_COMPUTE=float16
   export WHISPER_MODEL=large-v3   # หรือโมเดลอื่นตามต้องการ
   # เลือกภาษาหลัก (ค่าเริ่มต้นคือ th)
   export WHISPER_LANG=th
   ```
   - ถ้าจะใช้ FFmpeg preprocess ให้ติดตั้ง ffmpeg แล้วกำหนด `MEETING_SERVER_FFMPEG=/path/to/ffmpeg`
4. รันเซิร์ฟเวอร์:
   ```bash
   uvicorn main:app --host ${HOST:-0.0.0.0} --port ${PORT:-8000} --workers 1
   ```
5. ตรวจสอบว่า GPU ถูกใช้งาน:
   - สังเกต log ตอนเริ่มที่พิมพ์ขึ้นมา หรือเรียก `http://<ip-เซิร์ฟเวอร์>:8000/healthz` ค่า `compute` จะเป็น `float16`
   - ใช้ `nvidia-smi` ดู process ของ `python` / `uvicorn`

### เชื่อมต่อ Flutter app ให้ใช้เซิร์ฟเวอร์แยก

ฝั่ง client (เครื่องที่รัน Flutter app) ให้กำหนด base URL ของเซิร์ฟเวอร์ผ่าน Dart define ตอนรัน:
```bash
cd flutter_app
flutter run \
  --dart-define=SERVER_BASE_URL=http://<ip-เซิร์ฟเวอร์>:8000
```
หรือถ้า build เป็น executable:
```bash
flutter build windows \
  --dart-define=SERVER_BASE_URL=http://<ip-เซิร์ฟเวอร์>:8000
```
- แอปจะเชื่อมต่อ REST API โดยตรง และแสดงสถานะคิว / ข้อผิดพลาดผ่านหน้า Home
- หากต้องการเรียกผ่าน HTTPS ให้เปลี่ยน `SERVER_BASE_URL=https://your-domain`

## แยกผู้พูดด้วย Speaker Diarization

- ติดตั้ง dependencies เพิ่มเติม (มีใน `server/requirements.txt` แล้ว เช่น `pyannote.audio`) และอย่าลืมติดตั้ง `torch` ที่รองรับ GPU ตาม CUDA เวอร์ชันของคุณ
- สร้างหรือใช้ Hugging Face access token ที่มีสิทธิ์เข้าถึงโมเดล `pyannote/speaker-diarization-3.1` จากนั้นตั้งค่า:
  ```bash
  export DIARIZATION_AUTH_TOKEN=<your_hf_token>
  # เลือกโมเดลอื่นได้ เช่น pyannote/speaker-diarization-3.1
  export DIARIZATION_MODEL=pyannote/speaker-diarization-3.1
  # บังคับอุปกรณ์ (ไม่กำหนด = เลือกอัตโนมัติ, ถ้ามี CUDA จะใช้ cuda)
  export DIARIZATION_DEVICE=cuda
  ```
- รันเซิร์ฟเวอร์ตามปกติ เมื่อเรียก `/transcribe` หรือ endpoint streaming พร้อมฟิลด์ `diarize=true` จะได้ `segments` ที่มี `speaker` ระบุ รวมทั้ง `speaker_segments` ในผลลัพธ์
- ฝั่งแอป Flutter สามารถเปิดสวิตช์ “ระบุผู้พูด” ในหน้า “ปรับแต่งการถอดเสียง” เพื่อส่งคำขอแบบมี diarization ได้ และ transcript บนหน้าหลักจะแสดงชื่อผู้พูดในแต่ละบรรทัด

## ให้บริการผ่าน Nginx

1. รัน uvicorn ภายในเครื่อง (ไม่ต้องเปิด public port ตรง ๆ):
   ```bash
   cd server
   uvicorn main:app --host 127.0.0.1 --port 8001 --proxy-headers --forwarded-allow-ips='*'
   ```
   - ตั้งค่า environment variables ต่าง ๆ (WHISPER_MODEL, DIARIZATION_* ฯลฯ) ตามจำเป็นก่อนรันคำสั่งนี้
2. ติดตั้ง Nginx แล้ววางไฟล์ตัวอย่าง `server/nginx.conf.example` ใน `/etc/nginx/sites-available/meeting_minutes` จากนั้นปรับ:
   - `server_name` ให้ตรงกับโดเมนที่ใช้
   - Path ของ certificate (`ssl_certificate`, `ssl_certificate_key`) ถ้าใช้ HTTPS
3. เปิดใช้งาน config:
   ```bash
   sudo ln -s /etc/nginx/sites-available/meeting_minutes /etc/nginx/sites-enabled/meeting_minutes
   sudo nginx -t
   sudo systemctl reload nginx
   ```
4. หาก proxy อยู่หลัง HTTPS ให้ตั้งค่าแอป Flutter ด้วย base URL ที่ตรงกับโดเมน เช่น
   ```bash
   flutter run --dart-define=MANAGE_SERVER=false \
     --dart-define=SERVER_BASE_URL=https://meeting.example.com
   ```

## จำกัดจำนวนงานพร้อมกัน / ระบบคิว

- ตั้งค่า `TRANSCRIBE_CONCURRENCY` (ค่าเริ่มต้น 1) เพื่อกำหนดจำนวนงานถอดเสียงที่ทำพร้อมกันได้สูงสุดในเซิร์ฟเวอร์เดี่ยว
  ```bash
  export TRANSCRIBE_CONCURRENCY=2
  ```
- เมื่อคิวเต็ม คำขอใหม่จะรอคิวโดยอัตโนมัติ; ฝั่ง client ที่ใช้ endpoint สตรีมจะได้รับอีเวนต์ `{"event":"queued", ...}` ซึ่งบอกตำแหน่งคิวและ `job_id`
- เมื่อถึงคิวแล้ว แอปจะเริ่มประมวลผลและระบุเวลาที่รอคิว (`wait_seconds`) ในผลลัพธ์สุดท้ายของทั้ง REST response และอีเวนต์ `done`
# DCT_Meeting_Report
