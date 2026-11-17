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
# Con REDIS_URL definida las notas se guardan en Redis, compartido por todas las replicas.
# Sin ella se usa el archivo JSON local (desarrollo y tests), valido solo con una replica.
REDIS_URL = os.environ.get("REDIS_URL", "")

API_TITLE = os.environ.get("API_TITLE", "Notes API")
WELCOME_MESSAGE = os.environ.get("WELCOME_MESSAGE", "Notes API is enabled and working")
HEALTH_PARAM = os.environ.get("HEALTH_PARAM", "default")
APP_VERSION = os.environ.get("APP_VERSION", "dev")
APP_ENV = os.environ.get("APP_ENV", "local")
MAX_NOTE_LENGTH = int(os.environ.get("MAX_NOTE_LENGTH", "500"))

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


def _newest_first(notes: list[dict]) -> list[dict]:
    # Los ids son crecientes en ambos almacenamientos: el mayor es la nota mas reciente
    return sorted(notes, key=lambda n: n["id"], reverse=True)


class FileStore:
    """Archivo JSON local. Las rutas se leen del modulo para que los tests puedan redirigirlas."""

    def __init__(self) -> None:
        self._lock = threading.Lock()

    def _load(self) -> list[dict]:
        if not NOTES_FILE.exists():
            return []
        with NOTES_FILE.open("r", encoding="utf-8") as f:
            return json.load(f)

    def _save(self, notes: list[dict]) -> None:
        DATA_DIR.mkdir(parents=True, exist_ok=True)
        tmp_file = NOTES_FILE.with_suffix(".tmp")
        with tmp_file.open("w", encoding="utf-8") as f:
            json.dump(notes, f, ensure_ascii=False, indent=2)
        tmp_file.replace(NOTES_FILE)

    def ping(self) -> None:
        DATA_DIR.mkdir(parents=True, exist_ok=True)

    def list(self) -> list[dict]:
        with self._lock:
            return self._load()

    def get(self, note_id: int) -> dict | None:
        return next((n for n in self.list() if n["id"] == note_id), None)

    def create(self, text: str) -> dict:
        with self._lock:
            notes = self._load()
            entry = {
                "id": max((n["id"] for n in notes), default=0) + 1,
                "text": text,
                "created_at": datetime.now(UTC).isoformat(),
            }
            notes.append(entry)
            self._save(notes)
        return entry

    def delete(self, note_id: int) -> bool:
        with self._lock:
            notes = self._load()
            remaining = [n for n in notes if n["id"] != note_id]
            if len(remaining) == len(notes):
                return False
            self._save(remaining)
        return True

    def count(self) -> int:
        return len(self.list())


class RedisStore:
    """Hash notes (id -> JSON) y contador atomico notes:next_id, seguros entre replicas."""

    HASH = "notes"
    SEQ = "notes:next_id"

    def __init__(self, client) -> None:
        self._r = client

    def ping(self) -> None:
        self._r.ping()

    def list(self) -> list[dict]:
        return [json.loads(v) for v in self._r.hvals(self.HASH)]

    def get(self, note_id: int) -> dict | None:
        raw = self._r.hget(self.HASH, str(note_id))
        return json.loads(raw) if raw else None

    def create(self, text: str) -> dict:
        entry = {
            "id": int(self._r.incr(self.SEQ)),
            "text": text,
            "created_at": datetime.now(UTC).isoformat(),
        }
        self._r.hset(self.HASH, str(entry["id"]), json.dumps(entry, ensure_ascii=False))
        return entry

    def delete(self, note_id: int) -> bool:
        return self._r.hdel(self.HASH, str(note_id)) == 1

    def count(self) -> int:
        return int(self._r.hlen(self.HASH))


def _build_store():
    if not REDIS_URL:
        return FileStore()
    import redis

    client = redis.Redis.from_url(
        REDIS_URL,
        decode_responses=True,
        socket_timeout=2,
        socket_connect_timeout=2,
        health_check_interval=30,
    )
    return RedisStore(client)


store = _build_store()


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
    try:
        NOTES_TOTAL.set(store.count())
    except Exception:  # noqa: S110 - las metricas se sirven aunque falle el almacenamiento
        pass
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.get("/")
def root():
    return {"message": WELCOME_MESSAGE, "version": APP_VERSION, "env": APP_ENV}


@app.get("/health")
def health():
    # Liveness: solo indica que el proceso responde, no depende del almacenamiento
    return {
        "status": "ok",
        "health_param": HEALTH_PARAM,
        "version": APP_VERSION,
        "env": APP_ENV,
    }


@app.get("/ready")
def ready():
    # Readiness: el pod recibe trafico solo si puede leer y escribir notas
    try:
        store.ping()
    except Exception as exc:
        raise HTTPException(status_code=503, detail="Almacenamiento no disponible") from exc
    return {"status": "ready", "storage": "redis" if isinstance(store, RedisStore) else "file"}


@app.post("/notes", status_code=201)
def create_note(payload: NoteIn):
    entry = store.create(payload.text)
    NOTES_CREATED_TOTAL.inc()
    return entry


@app.post("/add/{note}", status_code=201)
def add_note(note: str):
    # Compatibilidad con la version anterior de la API (entregables 1 a 3)
    return create_note(NoteIn(text=note))


@app.get("/notes")
def list_notes():
    return {"notes": _newest_first(store.list())}


@app.get("/list")
def list_notes_legacy():
    return list_notes()


@app.get("/notes/{note_id}")
def get_note(note_id: int):
    note = store.get(note_id)
    if note is None:
        raise HTTPException(status_code=404, detail="Nota no encontrada")
    return note


@app.delete("/notes/{note_id}", status_code=204)
def delete_note(note_id: int):
    if not store.delete(note_id):
        raise HTTPException(status_code=404, detail="Nota no encontrada")
    NOTES_DELETED_TOTAL.inc()
    return Response(status_code=204)


@app.get("/stats")
def stats():
    return {"total_notes": store.count(), "version": APP_VERSION, "env": APP_ENV}
