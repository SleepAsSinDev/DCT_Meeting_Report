# Streaming Upload Patch

สิ่งที่เพิ่ม:
- server: endpoint ใหม่ `/transcribe_stream_upload` รับร่างกาย HTTP แบบสตรีม (octet-stream) แล้วคืนผลเป็น NDJSON
- flutter: method ใหม่ `transcribeStreamUpload(...)` รองรับ `onSendProgress` เพื่อแสดงเปอร์เซ็นต์การอัปโหลด
- ตัวอย่างโค้ดการใช้งาน (ดู USAGE_patch_in_home_page.txt)

ข้อจำกัดสำคัญ:
- HTTP/1.1 ไม่รองรับการตอบกลับแบบสองทางในขณะที่ยังอัปโหลดอยู่ → เซิร์ฟเวอร์จะเริ่มสตรีมผล **หลังอัปโหลดจบ** เท่านั้น
- ถ้าอยากได้ "ถอดไป-ส่งผลไประหว่างอัปโหลด" จริง ๆ ต้องใช้ WebSocket หรือแยกเป็น upload-chunks + worker ประมวลผลเป็นช่วง ๆ

ถ้าต้องการ ผมสามารถอัปเกรดเป็น WebSocket endpoint `/ws/transcribe` ให้สตรีมไบต์แบบเรียลไทม์และส่งผลย่อยกลับได้
