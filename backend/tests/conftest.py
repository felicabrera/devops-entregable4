import os
import sys
from pathlib import Path

import fakeredis
import pytest
from fastapi.testclient import TestClient

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
os.environ["APP_VERSION"] = "test"
os.environ.pop("REDIS_URL", None)

import main  # noqa: E402


@pytest.fixture(params=["file", "redis"])
def client(request, tmp_path, monkeypatch):
    # Cada test corre contra los dos almacenamientos, siempre vacios
    monkeypatch.setattr(main, "DATA_DIR", tmp_path)
    monkeypatch.setattr(main, "NOTES_FILE", tmp_path / "notes.json")
    if request.param == "file":
        monkeypatch.setattr(main, "store", main.FileStore())
    else:
        fake = fakeredis.FakeRedis(decode_responses=True)
        monkeypatch.setattr(main, "store", main.RedisStore(fake))
    with TestClient(main.app) as c:
        yield c
