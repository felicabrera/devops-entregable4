import json
import os
import threading
import time
from datetime import UTC, datetime
from pathlib import Path

from fastapi import FastAPI, HTTPException, Request, Response
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    Counter,
    Gauge,
    Histogram,
    generate_latest,
)
from pydantic import BaseModel, Field

DATA_DIR = Path(os.environ.get("DATA_DIR", Path(__file__).parent / "data"))
NOTES_FILE = DATA_DIR / "notes.json"

API_TITLE = os.environ.get("API_TITLE", "Notes API")
WELCOME_MESSAGE = os.environ.get("WELCOME_MESSAGE", "Notes API is enabled and working")
HEALTH_PARAM = os.environ.get("HEALTH_PARAM", "default")
APP_VERSION = os.environ.get("APP_VERSION", "dev")
APP_ENV = os.environ.get("APP_ENV", "local")
MAX_NOTE_LENGTH = int(os.environ.get("MAX_NOTE_LENGTH", "500"))

_lock = threading.Lock()

app = FastAPI(title=API_TITLE, version=APP_VERSION)

NOTES_CREATED_TOTAL = Counter("notes_created_total", "Notas creadas desde que arranco el proceso")
NOTES_DELETED_TOTAL = Counter("notes_deleted_total", "Notas borradas desde que arranco el proceso")
NOTES_TOTAL = Gauge("notes_total", "Cantidad de notas guardadas actualmente")
HTTP_REQUEST_DURATION = Histogram(
    "http_request_duration_seconds",
    "Duracion de las llamadas HTTP por endpoint",
    ["method", "endpoint", "status"],
)


class NoteIn(BaseModel):
    text: str = Field(min_length=1, max_length=MAX_NOTE_LENGTH)


def _load_notes() -> list[dict]:
    if not NOTES_FILE.exists():
        return []
    with NOTES_FILE.open("r", encoding="utf-8") as f:
        return json.load(f)


def _save_notes(notes: list[dict]) -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    tmp_file = NOTES_FILE.with_suffix(".tmp")
    with tmp_file.open("w", encoding="utf-8") as f:
        json.dump(notes, f, ensure_ascii=False, indent=2)
    tmp_file.replace(NOTES_FILE)


def _next_id(notes: list[dict]) -> int:
    return max((n["id"] for n in notes), default=0) + 1


@app.middleware("http")
async def track_requests(request: Request, call_next):
    start = time.perf_counter()
    status = 500
    try:
        response = await call_next(request)
        status = response.status_code
        return response
    finally:
        route = request.scope.get("route")
        endpoint = route.path if route else "unmatched"
        if endpoint != "/metrics":
            HTTP_REQUEST_DURATION.labels(request.method, endpoint, str(status)).observe(
                time.perf_counter() - start
            )


@app.get("/metrics", include_in_schema=False)
def metrics():
    with _lock:
        NOTES_TOTAL.set(len(_load_notes()))
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.get("/")
def root():
    return {"message": WELCOME_MESSAGE, "version": APP_VERSION, "env": APP_ENV}


@app.get("/health")
def health():
    return {
        "status": "ok",
        "health_param": HEALTH_PARAM,
        "version": APP_VERSION,
        "env": APP_ENV,
    }


@app.post("/notes", status_code=201)
def create_note(payload: NoteIn):
    with _lock:
        notes = _load_notes()
        entry = {
            "id": _next_id(notes),
            "text": payload.text,
            "created_at": datetime.now(UTC).isoformat(),
        }
        notes.append(entry)
        _save_notes(notes)
        NOTES_TOTAL.set(len(notes))
    NOTES_CREATED_TOTAL.inc()
    return entry


@app.post("/add/{note}", status_code=201)
def add_note(note: str):
    # Compatibilidad con la version anterior de la API (entregables 1 a 3)
    return create_note(NoteIn(text=note))


@app.get("/notes")
def list_notes():
    with _lock:
        notes = _load_notes()
    return {"notes": notes}


@app.get("/list")
def list_notes_legacy():
    return list_notes()


@app.get("/notes/{note_id}")
def get_note(note_id: int):
    with _lock:
        notes = _load_notes()
    for note in notes:
        if note["id"] == note_id:
            return note
    raise HTTPException(status_code=404, detail="Nota no encontrada")


@app.delete("/notes/{note_id}", status_code=204)
def delete_note(note_id: int):
    with _lock:
        notes = _load_notes()
        remaining = [n for n in notes if n["id"] != note_id]
        if len(remaining) == len(notes):
            raise HTTPException(status_code=404, detail="Nota no encontrada")
        _save_notes(remaining)
        NOTES_TOTAL.set(len(remaining))
    NOTES_DELETED_TOTAL.inc()
    return Response(status_code=204)


@app.get("/stats")
def stats():
    with _lock:
        notes = _load_notes()
    return {"total_notes": len(notes), "version": APP_VERSION, "env": APP_ENV}
