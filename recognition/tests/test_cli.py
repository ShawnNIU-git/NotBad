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
