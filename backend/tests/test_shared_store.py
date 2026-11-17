"""Varias replicas del backend comparten el mismo Redis: ven las mismas notas y no repiten ids."""

import fakeredis
from fastapi.testclient import TestClient

import main


def test_two_replicas_share_state():
    server = fakeredis.FakeServer()
    replica_a = main.RedisStore(fakeredis.FakeRedis(server=server, decode_responses=True))
    replica_b = main.RedisStore(fakeredis.FakeRedis(server=server, decode_responses=True))

    ids = [replica_a.create("a")["id"], replica_b.create("b")["id"], replica_a.create("c")["id"]]
    assert ids == [1, 2, 3]
    assert replica_a.count() == replica_b.count() == 3
    assert replica_b.get(1)["text"] == "a"

    assert replica_b.delete(1)
    assert replica_a.get(1) is None
    assert not replica_a.delete(1)
    assert replica_b.create("d")["id"] == 4


class _BrokenStore(main.FileStore):
    def ping(self) -> None:
        raise ConnectionError("sin conexion")

    def count(self) -> int:
        raise ConnectionError("sin conexion")


def test_ready_fails_without_storage_but_health_and_metrics_answer(monkeypatch):
    monkeypatch.setattr(main, "store", _BrokenStore())
    with TestClient(main.app) as c:
        assert c.get("/ready").status_code == 503
        assert c.get("/health").status_code == 200
        assert c.get("/metrics").status_code == 200
