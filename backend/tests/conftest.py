import os
import sys
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
os.environ["APP_VERSION"] = "test"

import main  # noqa: E402


@pytest.fixture()
def client(tmp_path, monkeypatch):
    # Cada test usa un directorio de datos propio y vacio
    monkeypatch.setattr(main, "DATA_DIR", tmp_path)
    monkeypatch.setattr(main, "NOTES_FILE", tmp_path / "notes.json")
    with TestClient(main.app) as c:
        yield c
