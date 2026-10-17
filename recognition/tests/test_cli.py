import json

from PIL import Image

from notbad_recog import cli
from notbad_recog.client import VisionClient
from notbad_recog.schema import PageResult


def test_analyze_writes_outputs(tmp_path, monkeypatch):
    monkeypatch.setenv("NOTBAD_API_KEY", "k")
    monkeypatch.setenv("NOTBAD_MODEL", "m")
    result = PageResult.from_dict(
        {"questions": [{"number": "二(1)", "bbox": [0, 0, 500, 500], "is_wrong": True}]}
    )
    monkeypatch.setattr(VisionClient, "analyze_page", lambda self, img: (result, "raw"))

    images = tmp_path / "images"
    images.mkdir()
    Image.new("RGB", (200, 200), "white").save(images / "page1.jpg")
    out = tmp_path / "out"

    assert cli.main(["analyze", str(images), "-o", str(out)]) == 0
    pred = json.loads((out / "preds" / "page1.json").read_text(encoding="utf-8"))
    assert pred["questions"][0]["number"] == "二(1)"
    assert (out / "raw" / "page1.txt").read_text(encoding="utf-8") == "raw"
    assert [p.name for p in (out / "crops" / "page1").iterdir()] == ["00_二_1_.jpg"]
    assert (out / "overlay" / "page1.jpg").exists()


def test_solve_reads_analyze_output(tmp_path, monkeypatch):
    from notbad_recog.schema import Solution

    monkeypatch.setenv("NOTBAD_API_KEY", "k")
    monkeypatch.setenv("NOTBAD_MODEL", "m")
    out = tmp_path / "out"
    (out / "preds").mkdir(parents=True)
    (out / "crops" / "p1").mkdir(parents=True)
    page = {"subject": "数学", "questions": [
        {"number": "1", "bbox": [0, 0, 10, 10], "is_wrong": True, "text": "1+1="},
        {"number": "2", "bbox": [0, 0, 10, 10], "is_wrong": False},
    ]}
    (out / "preds" / "p1.json").write_text(json.dumps(page), encoding="utf-8")
    for name in ("00_1.jpg", "01_2.jpg"):
        Image.new("RGB", (20, 20)).save(out / "crops" / "p1" / name)

    calls = []

    def fake_solve(self, img, text="", subject="", student_answer="", model=None):
        calls.append((text, subject))
        return Solution(answer="2", confidence=1.0), "raw"

    monkeypatch.setattr(VisionClient, "solve_question", fake_solve)

    assert cli.main(["solve", str(out)]) == 0
    assert calls == [("1+1=", "数学")]  # 只解错题
    solutions = json.loads((out / "solutions" / "p1.json").read_text(encoding="utf-8"))
    assert solutions["1"]["answer"] == "2"
