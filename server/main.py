import os, json as _json, tempfile as _tf, threading, subprocess, asyncio, time
from collections import deque
from itertools import count
from typing import Dict, List, Optional
from fastapi import FastAPI, UploadFile, File, Form, Request, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from starlette.responses import StreamingResponse
from faster_whisper import WhisperModel

try:
    from pyannote.audio import Pipeline as _DiarizationPipeline
except ImportError:
    _DiarizationPipeline = None

try:
    import torch as _torch
except ImportError:
    _torch = None

_MODEL_SIZE_ENV = os.getenv("WHISPER_MODEL")

# Allow overriding host/port/ffmpeg via env without relying on CLI arguments.
HOST_DEFAULT = (
    os.getenv("MEETING_SERVER_HOST")
    or os.getenv("WHISPER_HOST")
    or os.getenv("HOST")
    or "127.0.0.1"
)
PORT_DEFAULT = int(
    os.getenv("MEETING_SERVER_PORT")
    or os.getenv("WHISPER_PORT")
    or os.getenv("PORT")
    or "8000"
)

_FFMPEG_ENV = (
    os.getenv("MEETING_SERVER_FFMPEG")
    or os.getenv("FFMPEG_BIN")
    or os.getenv("FFMPEG_PATH")
    or "ffmpeg"
)

# -------- Defaults (Thai + accuracy-first, but tunable) --------
COMPUTE_TYPE = os.getenv("WHISPER_COMPUTE", "int8")          # CPU:int8  | GPU:float16|float32
LANGUAGE_DEFAULT = os.getenv("WHISPER_LANG", "th")           # default Thai
QUALITY_DEFAULT = os.getenv("WHISPER_QUALITY", "accurate")   # accurate | balanced | fast | hyperfast
CPU_THREADS_DEFAULT = int(os.getenv("WHISPER_CPU_THREADS", str(os.cpu_count() or 4)))
NUM_WORKERS_DEFAULT = int(os.getenv("WHISPER_NUM_WORKERS", "1"))
TRANSCRIBE_CONCURRENCY = max(
    1, int(os.getenv("TRANSCRIBE_CONCURRENCY", "1"))
)


def _is_path_like(value: str) -> bool:
    if not value:
        return False
    tokens = (os.sep, os.altsep or "", "/", "\\")
    return value.startswith(("./", "../", "~")) or any(sep in value for sep in tokens if sep)


def _resolve_relative_to_here(raw: str) -> str:
    raw = os.path.expanduser(raw)
    if os.path.isabs(raw):
        return os.path.abspath(raw)
    base_dir = os.path.dirname(os.path.abspath(__file__))
    return os.path.abspath(os.path.join(base_dir, raw))


def _normalize_model_name_raw(name: str) -> str:
    if _is_path_like(name):
        return _resolve_relative_to_here(name)
    lowered = name.strip().lower()
    return "large-v3" if lowered == "large" else lowered


MODEL_SIZE_DEFAULT = _normalize_model_name_raw(_MODEL_SIZE_ENV)
FFMPEG_BIN = (
    _resolve_relative_to_here(_FFMPEG_ENV)
    if _is_path_like(_FFMPEG_ENV)
    else _FFMPEG_ENV
)

DIARIZATION_MODEL_DEFAULT = os.getenv(
    "DIARIZATION_MODEL", "pyannote/speaker-diarization-3.1"
)
DIARIZATION_DEFAULT_ENABLED = (
    os.getenv("DIARIZATION_DEFAULT", "false").strip().lower() == "true"
)
DIARIZATION_DEVICE_ENV = os.getenv("DIARIZATION_DEVICE")
DIARIZATION_AUTH_TOKEN = (
    os.getenv("DIARIZATION_AUTH_TOKEN")
    or os.getenv("HUGGINGFACE_TOKEN")
    or os.getenv("HF_TOKEN")
    or os.getenv("HUGGINGFACEHUB_API_TOKEN")
)


class _JobTicket:
    __slots__ = (
        "job_id",
        "position",
        "_event",
        "_queue",
        "_active",
        "wait_started",
        "wait_seconds",
    )

    def __init__(self, queue: "_JobQueue", job_id: int, event: asyncio.Event, position: int, active: bool):
        self._queue = queue
        self.job_id = job_id
        self.position = position  # number of jobs ahead at enqueue time
        self._event = event
        self._active = active
        self.wait_started = time.time()
        self.wait_seconds = 0.0

    async def wait_until_ready(self) -> None:
        try:
            await self._event.wait()
        except Exception:
            raise
        finally:
            if not self._active and self._event.is_set():
                self._active = True
        if self._active:
            self.wait_seconds = max(0.0, time.time() - self.wait_started)

    async def release(self) -> None:
        await self._queue._release(self)


class _JobQueue:
    def __init__(self, capacity: int):
        self.capacity = max(1, capacity)
        self._available = self.capacity
        self._lock = asyncio.Lock()
        self._waiters: deque = deque()
        self._counter = count(1)

    async def enqueue(self) -> _JobTicket:
        job_id = next(self._counter)
        event = asyncio.Event()
        async with self._lock:
            if self._available > 0:
                self._available -= 1
                event.set()
                position = 0
                active = True
            else:
                position = len(self._waiters)
                self._waiters.append((job_id, event))
                active = False
        return _JobTicket(self, job_id, event, position, active)

    async def _release(self, ticket: _JobTicket) -> None:
        async with self._lock:
            if ticket._active:
                if self._waiters:
                    _, event = self._waiters.popleft()
                    event.set()
                else:
                    self._available = min(self.capacity, self._available + 1)
            else:
                # remove from waiters if still queued
                for idx, (wait_job_id, event) in enumerate(self._waiters):
                    if wait_job_id == ticket.job_id:
                        del self._waiters[idx]
                        break

    async def stats(self) -> Dict[str, int]:
        async with self._lock:
            return {
                "capacity": self.capacity,
                "active": self.capacity - self._available,
                "waiting": len(self._waiters),
            }


_JOB_QUEUE = _JobQueue(TRANSCRIBE_CONCURRENCY)

def _normalize_model_name(name: Optional[str]) -> str:
    if not name:
        return MODEL_SIZE_DEFAULT
    return _normalize_model_name_raw(name.strip())

def _normalize_language(lang: str) -> str:
    if not lang:
        return LANGUAGE_DEFAULT
    l = lang.strip().lower()
    if l in ("thai", "th-th", "th"):
        return "th"
    if l in ("auto", "detect"):
        return "auto"
    return l

def _normalize_quality(q: str) -> str:
    return (q or QUALITY_DEFAULT).strip().lower()

app = FastAPI(title="Meeting Minutes App")
app.add_middleware(
    CORSMiddleware, allow_origins=["*"], allow_credentials=True,
    allow_methods=["*"], allow_headers=["*"],
)

# Lazy cache models (respect CPU threads/workers so we can tune speed)
_models_lock = threading.Lock()
_models: Dict[str, WhisperModel] = {}

_diarization_lock = threading.Lock()
_diarization_pipelines: Dict[str, object] = {}

def _get_model(name: str) -> WhisperModel:
    key = _normalize_model_name(name) + f"|t{CPU_THREADS_DEFAULT}|w{NUM_WORKERS_DEFAULT}|{COMPUTE_TYPE}"
    with _models_lock:
        m = _models.get(key)
        if m is None:
            m = WhisperModel(
                _normalize_model_name(name),
                device="auto",
                compute_type=COMPUTE_TYPE,
                cpu_threads=CPU_THREADS_DEFAULT,
                num_workers=NUM_WORKERS_DEFAULT,
            )
            _models[key] = m
        return m

# Best-effort preload default
try:
    _get_model(MODEL_SIZE_DEFAULT)
except Exception as e:
    print("[WARN] preload failed:", e)

class Segment(BaseModel):
    start: float
    end: float
    text: str
    speaker: Optional[str] = None

def _choose_params(quality: str):
    q = _normalize_quality(quality)
    if q == "accurate":
        return dict(beam_size=8, vad_filter=True, temperature=0.0, best_of=1)
    if q == "balanced":
        return dict(beam_size=5, vad_filter=True, temperature=0.0, best_of=1)
    if q == "fast":
        return dict(beam_size=1, vad_filter=True, temperature=0.0, best_of=1)
    # hyperfast -> fastest (no VAD, greedy)
    return dict(beam_size=1, vad_filter=False, temperature=0.0, best_of=1)

def _maybe_preprocess(path_in: str, enable: bool, quick: bool=False) -> str:
    if not enable:
        return path_in
    out = path_in + ".norm.wav"
    try:
        if quick:
            # Faster: only resample/mono
            cmd = [
                FFMPEG_BIN,
                "-y",
                "-hide_banner",
                "-loglevel",
                "error",
                "-i",
                path_in,
                "-ac",
                "1",
                "-ar",
                "16000",
                out,
            ]
        else:
            # Higher accuracy: normalize + filters
            cmd = [
                FFMPEG_BIN,
                "-y",
                "-hide_banner",
                "-loglevel",
                "error",
                "-i",
                path_in,
                "-ac",
                "1",
                "-ar",
                "16000",
                "-af",
                "highpass=f=100,lowpass=f=8000,loudnorm=I=-16:TP=-1.5:LRA=11",
                out,
            ]
        subprocess.run(cmd, check=True)
        return out
    except Exception:
        return path_in

def _get_diarization_pipeline(model_name: str):
    if _DiarizationPipeline is None:
        raise RuntimeError("pyannote.audio is not installed")
    if not DIARIZATION_AUTH_TOKEN:
        raise RuntimeError(
            "missing DIARIZATION_AUTH_TOKEN (or HF_TOKEN/HUGGINGFACE_TOKEN)"
        )
    with _diarization_lock:
        pipeline = _diarization_pipelines.get(model_name)
        if pipeline is None:
            pipeline = _DiarizationPipeline.from_pretrained(
                model_name, use_auth_token=DIARIZATION_AUTH_TOKEN
            )
            device = DIARIZATION_DEVICE_ENV
            if device:
                pipeline.to(device)
            elif _torch is not None and _torch.cuda.is_available():
                pipeline.to("cuda")
            _diarization_pipelines[model_name] = pipeline
        return pipeline

def _run_diarization(
    wav_path: str, model_name: Optional[str] = None
) -> Dict[str, object]:
    model = model_name or DIARIZATION_MODEL_DEFAULT
    try:
        pipeline = _get_diarization_pipeline(model)
    except Exception as exc:  # pragma: no cover - runtime dependent
        return {
            "applied": False,
            "reason": str(exc),
            "segments": [],
            "model": model,
        }
    try:
        diarization = pipeline(wav_path)
    except Exception as exc:  # pragma: no cover - runtime dependent
        return {
            "applied": False,
            "reason": str(exc),
            "segments": [],
            "model": model,
        }
    speaker_segments = []
    for turn, _, speaker in diarization.itertracks(yield_label=True):
        speaker_segments.append(
            {
                "start": float(turn.start),
                "end": float(turn.end),
                "speaker": str(speaker),
            }
        )
    return {
        "applied": True,
        "reason": None,
        "segments": speaker_segments,
        "model": model,
    }

def _assign_speakers_to_segments(
    segments: List[Segment], speaker_segments: List[Dict[str, object]]
) -> None:
    if not segments or not speaker_segments:
        return
    for seg in segments:
        best_label = None
        best_overlap = 0.0
        for entry in speaker_segments:
            try:
                s0 = float(entry.get("start", 0.0))
                e0 = float(entry.get("end", 0.0))
            except Exception:
                continue
            overlap = max(0.0, min(seg.end, e0) - max(seg.start, s0))
            if overlap > best_overlap:
                best_overlap = overlap
                best_label = str(entry.get("speaker", ""))
        if best_label:
            seg.speaker = best_label

@app.get("/healthz")
async def healthz():
    queue_stats = await _JOB_QUEUE.stats()
    return {
        "ok": True,
        "default_model": _normalize_model_name(MODEL_SIZE_DEFAULT),
        "default_language": LANGUAGE_DEFAULT,
        "default_quality": QUALITY_DEFAULT,
        "host": HOST_DEFAULT,
        "port": PORT_DEFAULT,
        "cpu_threads": CPU_THREADS_DEFAULT,
        "num_workers": NUM_WORKERS_DEFAULT,
        "compute": COMPUTE_TYPE,
        "loaded_models": list(_models.keys()),
        "ffmpeg": FFMPEG_BIN,
        "queue": queue_stats,
        "max_concurrency": TRANSCRIBE_CONCURRENCY,
    }

@app.post("/transcribe")
async def transcribe(
    file: UploadFile = File(...),
    language: str = Form(LANGUAGE_DEFAULT),
    model_size: str = Form(MODEL_SIZE_DEFAULT),
    quality: str = Form(QUALITY_DEFAULT),
    initial_prompt: Optional[str] = Form(None),
    diarize: bool = Form(DIARIZATION_DEFAULT_ENABLED),
    preprocess: bool = Form(False),
    fast_preprocess: bool = Form(False),
):
    model_size = _normalize_model_name(model_size)
    language = _normalize_language(language)
    params = _choose_params(quality)
    model = _get_model(model_size)

    suffix = os.path.splitext(file.filename or '')[-1] or '.bin'
    data = await file.read()
    with _tf.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        tmp.write(data)
        tmp_path = tmp.name

    wav_path = _maybe_preprocess(tmp_path, preprocess, quick=fast_preprocess)

    diarization_meta = {
        "requested": diarize,
        "applied": False,
        "reason": None,
        "segments": [],
        "model": DIARIZATION_MODEL_DEFAULT,
    }

    ticket = await _JOB_QUEUE.enqueue()
    try:
        await ticket.wait_until_ready()
        segments_gen, info = model.transcribe(
            wav_path,
            language=None if language == "auto" else language,
            initial_prompt=initial_prompt,
            **params,
        )
        segments = []
        text_parts = []
        for seg in segments_gen:
            segments.append(Segment(start=seg.start, end=seg.end, text=seg.text))
            text_parts.append(seg.text)
        if diarize:
            diarization_result = _run_diarization(
                wav_path, os.getenv("DIARIZATION_MODEL", DIARIZATION_MODEL_DEFAULT)
            )
            diarization_meta.update(diarization_result)
            if diarization_result.get("applied"):
                _assign_speakers_to_segments(segments, diarization_result["segments"])
        speakers = sorted(
            {seg.speaker for seg in segments if getattr(seg, "speaker", None)}
        )
        return {
            "text": " ".join(text_parts).strip(),
            "language": getattr(info, "language", language),
            "segments": [s.model_dump() for s in segments],
            "duration_sec": float(getattr(info, "duration", 0.0) or 0.0),
            "model": f"faster-whisper-{model_size}({COMPUTE_TYPE})",
            "quality": _normalize_quality(quality),
            "cpu_threads": CPU_THREADS_DEFAULT,
            "num_workers": NUM_WORKERS_DEFAULT,
            "preprocess": preprocess,
            "fast_preprocess": fast_preprocess,
            "speakers": speakers,
            "speaker_segments": diarization_meta["segments"]
            if diarization_meta.get("applied")
            else [],
            "diarization": diarization_meta,
            "queue": {
                "job_id": ticket.job_id,
                "wait_seconds": round(ticket.wait_seconds, 3),
                "position_on_enqueue": ticket.position,
            },
        }
    finally:
        await ticket.release()
        try: os.remove(tmp_path)
        except Exception: pass
        if wav_path != tmp_path:
            try: os.remove(wav_path)
            except Exception: pass

@app.post("/transcribe_stream")
async def transcribe_stream(
    file: UploadFile = File(...),
    language: str = Form(LANGUAGE_DEFAULT),
    model_size: str = Form(MODEL_SIZE_DEFAULT),
    quality: str = Form(QUALITY_DEFAULT),
    initial_prompt: Optional[str] = Form(None),
    diarize: bool = Form(DIARIZATION_DEFAULT_ENABLED),
    preprocess: bool = Form(False),
    fast_preprocess: bool = Form(False),
):
    model_size = _normalize_model_name(model_size)
    language = _normalize_language(language)
    params = _choose_params(quality)
    model = _get_model(model_size)

    suffix = os.path.splitext(file.filename or '')[-1] or '.bin'
    data = await file.read()
    with _tf.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        tmp.write(data)
        tmp_path = tmp.name

    wav_path = _maybe_preprocess(tmp_path, preprocess, quick=fast_preprocess)

    ticket = await _JOB_QUEUE.enqueue()

    async def gen():
        try:
            if ticket.position > 0:
                yield (
                    _json.dumps(
                        {
                            "event": "queued",
                            "job_id": ticket.job_id,
                            "position": ticket.position,
                        }
                    )
                    + "\n"
                ).encode("utf-8")
            await ticket.wait_until_ready()
            yield (
                _json.dumps({"event": "progress", "progress": 0.0, "partial_text": ""})
                + "\n"
            ).encode("utf-8")
            segments_gen, info = model.transcribe(
                wav_path,
                language=None if language == "auto" else language,
                initial_prompt=initial_prompt,
                **params,
            )
            full_text = []
            duration = float(getattr(info, "duration", 0.0) or 0.0)
            collected_segments: List[Segment] = []
            for seg in segments_gen:
                collected_segment = Segment(
                    start=seg.start, end=seg.end, text=seg.text
                )
                collected_segments.append(collected_segment)
                full_text.append(seg.text)
                progress = (seg.end / duration * 100.0) if duration > 0 else 0.0
                yield (
                    _json.dumps(
                        {
                            "event": "progress",
                            "progress": round(progress, 2),
                            "partial_text": seg.text,
                        }
                    )
                    + "\n"
                ).encode("utf-8")
            diarization_meta = {
                "requested": diarize,
                "applied": False,
                "reason": None,
                "segments": [],
                "model": DIARIZATION_MODEL_DEFAULT,
            }
            if diarize:
                diarization_result = _run_diarization(
                    wav_path, os.getenv("DIARIZATION_MODEL", DIARIZATION_MODEL_DEFAULT)
                )
                diarization_meta.update(diarization_result)
                if diarization_result.get("applied"):
                    _assign_speakers_to_segments(
                        collected_segments, diarization_result["segments"]
                    )
            speakers = sorted(
                {
                    seg.speaker
                    for seg in collected_segments
                    if getattr(seg, "speaker", None)
                }
            )
            yield (
                _json.dumps(
                    {
                        "event": "done",
                        "text": " ".join(full_text).strip(),
                        "language": getattr(info, "language", "auto"),
                        "duration_sec": duration,
                        "model": f"faster-whisper-{model_size}({COMPUTE_TYPE})",
                        "quality": _normalize_quality(quality),
                        "cpu_threads": CPU_THREADS_DEFAULT,
                        "num_workers": NUM_WORKERS_DEFAULT,
                        "preprocess": preprocess,
                        "fast_preprocess": fast_preprocess,
                        "segments": [s.model_dump() for s in collected_segments],
                        "speakers": speakers,
                        "speaker_segments": diarization_meta["segments"]
                        if diarization_meta.get("applied")
                        else [],
                        "diarization": diarization_meta,
                        "queue": {
                            "job_id": ticket.job_id,
                            "wait_seconds": round(ticket.wait_seconds, 3),
                            "position_on_enqueue": ticket.position,
                        },
                    }
                )
                + "\n"
            ).encode("utf-8")
        finally:
            await ticket.release()
            try:
                os.remove(tmp_path)
            except Exception:
                pass
            if wav_path != tmp_path:
                try:
                    os.remove(wav_path)
                except Exception:
                    pass

    return StreamingResponse(gen(), media_type="application/x-ndjson")


@app.post("/transcribe_stream_upload")
async def transcribe_stream_upload(
    request: Request,
    language: str = Query(LANGUAGE_DEFAULT),
    model_size: str = Query(MODEL_SIZE_DEFAULT),
    quality: str = Query(QUALITY_DEFAULT),
    initial_prompt: Optional[str] = Query(None),
    diarize: bool = Query(DIARIZATION_DEFAULT_ENABLED),
    preprocess: bool = Query(False),
    fast_preprocess: bool = Query(False),
):
    model_size = _normalize_model_name(model_size)
    language = _normalize_language(language)
    params = _choose_params(quality)
    model = _get_model(model_size)

    with _tf.NamedTemporaryFile(delete=False, suffix=".bin") as tmp:
        tmp_path = tmp.name

    with open(tmp_path, "wb") as f:
        async for chunk in request.stream():
            if chunk:
                f.write(chunk)

    wav_path = _maybe_preprocess(tmp_path, preprocess, quick=fast_preprocess)

    ticket = await _JOB_QUEUE.enqueue()

    async def gen():
        try:
            if ticket.position > 0:
                yield (
                    _json.dumps(
                        {
                            "event": "queued",
                            "job_id": ticket.job_id,
                            "position": ticket.position,
                        }
                    )
                    + "\n"
                ).encode("utf-8")
            await ticket.wait_until_ready()
            yield (
                _json.dumps({"event": "progress", "progress": 0.0, "partial_text": ""})
                + "\n"
            ).encode("utf-8")
            segments_gen, info = model.transcribe(
                wav_path,
                language=None if language == "auto" else language,
                initial_prompt=initial_prompt,
                **params,
            )
            collected = []
            collected_segments: List[Segment] = []
            duration = float(getattr(info, "duration", 0.0) or 0.0)
            for seg in segments_gen:
                collected.append(seg.text)
                collected_segments.append(
                    Segment(start=seg.start, end=seg.end, text=seg.text)
                )
                progress = (seg.end / duration * 100.0) if duration > 0 else 0.0
                yield (
                    _json.dumps(
                        {
                            "event": "progress",
                            "progress": round(progress, 2),
                            "partial_text": seg.text,
                        }
                    )
                    + "\n"
                ).encode("utf-8")
            diarization_meta = {
                "requested": diarize,
                "applied": False,
                "reason": None,
                "segments": [],
                "model": DIARIZATION_MODEL_DEFAULT,
            }
            if diarize:
                diarization_result = _run_diarization(
                    wav_path, os.getenv("DIARIZATION_MODEL", DIARIZATION_MODEL_DEFAULT)
                )
                diarization_meta.update(diarization_result)
                if diarization_result.get("applied"):
                    _assign_speakers_to_segments(
                        collected_segments, diarization_result["segments"]
                    )
            speakers = sorted(
                {
                    seg.speaker
                    for seg in collected_segments
                    if getattr(seg, "speaker", None)
                }
            )
            yield (
                _json.dumps(
                    {
                        "event": "done",
                        "text": " ".join(collected).strip(),
                        "language": getattr(info, "language", "auto"),
                        "duration_sec": duration,
                        "model": f"faster-whisper-{model_size}({COMPUTE_TYPE})",
                        "quality": _normalize_quality(quality),
                        "cpu_threads": CPU_THREADS_DEFAULT,
                        "num_workers": NUM_WORKERS_DEFAULT,
                        "preprocess": preprocess,
                        "fast_preprocess": fast_preprocess,
                        "segments": [s.model_dump() for s in collected_segments],
                        "speakers": list(speakers),
                        "speaker_segments": diarization_meta["segments"]
                        if diarization_meta.get("applied")
                        else [],
                        "diarization": diarization_meta,
                        "queue": {
                            "job_id": ticket.job_id,
                            "wait_seconds": round(ticket.wait_seconds, 3),
                            "position_on_enqueue": ticket.position,
                        },
                    }
                )
                + "\n"
            ).encode("utf-8")
        finally:
            await ticket.release()
            try:
                os.remove(tmp_path)
            except Exception:
                pass
            if wav_path != tmp_path:
                try:
                    os.remove(wav_path)
                except Exception:
                    pass

    return StreamingResponse(gen(), media_type="application/x-ndjson")

@app.post("/summarize")
async def summarize(req: Request):
    body = await req.json()
    transcript = body.get("transcript", "")
    style = body.get("style", "thai-formal")
    sections = body.get("sections", [])

    report = f"# สรุปรายงาน ({style})\n\n"
    if sections:
        for sec in sections:
            report += f"## {sec}\n- {transcript[:100]}...\n"
    else:
        report += transcript
    return {"report_markdown": report}

if __name__ == "__main__":
    import uvicorn

    uvicorn.run("main:app", host=HOST_DEFAULT, port=PORT_DEFAULT)
