def test_root_and_health(client):
    assert client.get("/").json()["version"] == "test"
    health = client.get("/health").json()
    assert health["status"] == "ok"


def test_create_list_get_delete(client):
    created = client.post("/notes", json={"text": "hola"})
    assert created.status_code == 201
    note = created.json()
    assert note["id"] == 1 and note["text"] == "hola"

    assert client.get("/notes").json()["notes"] == [note]
    assert client.get("/notes/1").json() == note
    assert client.get("/stats").json()["total_notes"] == 1

    assert client.delete("/notes/1").status_code == 204
    assert client.get("/notes/1").status_code == 404
    assert client.delete("/notes/1").status_code == 404
    assert client.get("/stats").json()["total_notes"] == 0


def test_next_id_is_max_plus_one(client):
    client.post("/notes", json={"text": "a"})
    client.post("/notes", json={"text": "b"})
    client.delete("/notes/1")
    third = client.post("/notes", json={"text": "c"}).json()
    assert third["id"] == 3


def test_validation(client):
    assert client.post("/notes", json={"text": ""}).status_code == 422
    assert client.post("/notes", json={"text": "x" * 501}).status_code == 422
    assert client.post("/notes", json={}).status_code == 422


def test_legacy_endpoints(client):
    assert client.post("/add/legacy").status_code == 201
    assert client.get("/list").json()["notes"][0]["text"] == "legacy"


def _metric(body: str, name: str) -> float:
    for line in body.splitlines():
        if line.startswith(name + " "):
            return float(line.split()[1])
    raise AssertionError(f"metric {name} not found")


def test_metrics(client):
    before = _metric(client.get("/metrics").text, "notes_created_total")
    client.post("/notes", json={"text": "m"})
    client.get("/notes")
    body = client.get("/metrics").text
    assert _metric(body, "notes_created_total") == before + 1
    assert _metric(body, "notes_total") == 1
    sample = 'http_request_duration_seconds_count{endpoint="/notes",method="GET",status="200"}'
    assert sample in body
    assert 'endpoint="/metrics"' not in body
