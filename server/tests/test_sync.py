from fastapi.testclient import TestClient
from exp.main import app

c = TestClient(app)


def ch(id, cents=100, t=1, deleted=False):
    return {"id": id, "cents": cents, "category": "food", "note": "n", "date": 1, "is_income": False, "updated_at": t, "deleted": deleted}


def sync(user, changes=(), since=0):
    r = c.post("/sync", headers={"X-User-Id": user}, json={"since": since, "changes": list(changes)})
    assert r.status_code == 200, r.text
    return r.json()


def test_two_devices_converge():
    a = sync("user-a", [ch("e1", 500, 1)])
    assert a["changes"][0]["cents"] == 500
    b = sync("user-a", [ch("e2", 700, 2)])           # device B pushes and pulls device A's row
    assert {x["id"] for x in b["changes"]} == {"e1", "e2"}
    again = sync("user-a", [], since=a["server_time"])  # device A pulls only what is newer than its cursor
    assert [x["id"] for x in again["changes"]] == ["e2"]
    assert sync("user-a", [], since=again["server_time"])["changes"] == []


def test_last_write_wins_and_stale_edit_ignored():
    sync("user-b", [ch("x", 100, t=10)])
    out = sync("user-b", [ch("x", 999, t=5)])        # older edit arrives late
    assert out["changes"][0]["cents"] == 100
    out = sync("user-b", [ch("x", 300, t=20)])
    assert [x["cents"] for x in out["changes"]] == [300]


def test_deletion_propagates():
    s = sync("user-c", [ch("d", 100, 1)])
    out = sync("user-c", [ch("d", 100, 2, deleted=True)], since=s["server_time"])
    assert out["changes"][0]["deleted"] is True


def test_users_are_isolated_and_validation():
    sync("user-d", [ch("private", 1, 1)])
    assert sync("user-e")["changes"] == []
    assert c.post("/sync", json={}).status_code == 400
    assert c.post("/sync", headers={"X-User-Id": "user-f"}, json={"changes": [ch("n", -5)]}).status_code == 422
