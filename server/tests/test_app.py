import io
from datetime import date

import pytest
from fastapi.testclient import TestClient
from PIL import Image

from notbad_recog.schema import PageResult, Solution
from notbad_server.app import create_app
from notbad_server.quota import DailyQuota
from notbad_server.settings import Settings

AUTH = {"Authorization": "Bearer t1"}


class FakeClient:
    def __init__(self, fail=None):
        self.fail = fail
        self.calls = []

    def analyze_page(self, img, model=None):
        self.calls.append(("analyze", img.size, model))
        if self.fail:
            raise self.fail
        return PageResult.from_dict({"subject": "数学", "title": "单元测试", "questions": [
            {"number": "1", "bbox": [0, 0, 500, 500], "is_wrong": True}]}), "raw"

    def solve_question(self, img, text="", subject="", student_answer="", model=None):
        self.calls.append(("solve", text, subject, student_answer, model))
        return Solution(answer="11", explanation="先乘后加", confidence=0.9), "raw"


def jpeg_bytes(size=(64, 48)):
    buf = io.BytesIO()
    Image.new("RGB", size, "white").save(buf, format="JPEG")
    return buf.getvalue()


def make(fake=None, **kw):
    settings = Settings(member_tokens=frozenset({"t1"}), analyze_model="vision", solve_model="solver", **kw)
    fake = fake or FakeClient()
    return TestClient(create_app(settings, client_factory=lambda: fake)), fake


def test_requires_member_token():
    client, _ = make()
    assert client.get("/v1/me").status_code == 401
    assert client.get("/v1/me", headers={"Authorization": "Bearer nope"}).status_code == 401
    assert client.get("/healthz").json() == {"ok": True}


def test_analyze_returns_page_and_counts_quota():
    client, fake = make()
    resp = client.post("/v1/pages/analyze", headers=AUTH, files={"image": ("p.jpg", jpeg_bytes(), "image/jpeg")})
    assert resp.status_code == 200
    body = resp.json()
    assert body["title"] == "单元测试"
    assert body["questions"][0]["is_wrong"] is True
    assert fake.calls == [("analyze", (64, 48), "vision")]
    assert client.get("/v1/me", headers=AUTH).json() == {"daily_limit": 200, "used_today": 1, "remaining": 199}


def test_solve_passes_fields_and_model():
    client, fake = make()
    resp = client.post("/v1/questions/solve", headers=AUTH,
                       files={"image": ("q.jpg", jpeg_bytes(), "image/jpeg")},
                       data={"text": "3+4×2=", "subject": "数学", "student_answer": "14"})
    assert resp.status_code == 200
    assert resp.json()["answer"] == "11"
    assert fake.calls == [("solve", "3+4×2=", "数学", "14", "solver")]


def test_quota_exceeded_returns_402():
    client, _ = make(daily_limit=1)
    files = {"image": ("p.jpg", jpeg_bytes(), "image/jpeg")}
    assert client.post("/v1/pages/analyze", headers=AUTH, files=files).status_code == 200
    assert client.post("/v1/pages/analyze", headers=AUTH, files=files).status_code == 402


@pytest.mark.parametrize("error", [ValueError("bad json"), RuntimeError("HTTP 500")])
def test_upstream_failure_returns_502_and_refunds(error):
    client, _ = make(FakeClient(fail=error))
    resp = client.post("/v1/pages/analyze", headers=AUTH, files={"image": ("p.jpg", jpeg_bytes(), "image/jpeg")})
    assert resp.status_code == 502
    assert client.get("/v1/me", headers=AUTH).json()["used_today"] == 0


def test_rejects_bad_and_oversized_images():
    client, _ = make(max_upload_bytes=100)
    resp = client.post("/v1/pages/analyze", headers=AUTH, files={"image": ("p.jpg", jpeg_bytes((400, 400)), "image/jpeg")})
    assert resp.status_code == 413
    client, _ = make()
    resp = client.post("/v1/pages/analyze", headers=AUTH, files={"image": ("p.jpg", b"not an image", "image/jpeg")})
    assert resp.status_code == 400


def test_daily_quota_resets_next_day():
    today = [date(2026, 10, 17)]
    quota = DailyQuota(1, today=lambda: today[0])
    assert quota.try_consume("a")
    assert not quota.try_consume("a")
    today[0] = date(2026, 10, 18)
    assert quota.try_consume("a")
    assert quota.used("a") == 1
