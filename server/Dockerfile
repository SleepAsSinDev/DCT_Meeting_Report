FROM python:3.11-slim

# FFmpeg for wide audio format support
RUN apt-get update && apt-get install -y ffmpeg && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt /app/
RUN pip install --no-cache-dir -r requirements.txt
COPY . /app

ENV WHISPER_MODEL=small
ENV WHISPER_COMPUTE=int8
ENV PORT=8000

EXPOSE 8000
CMD ["python", "main.py"]
