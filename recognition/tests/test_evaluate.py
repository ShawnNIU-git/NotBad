import json

import pytest

from notbad_recog.evaluate import compare_page, evaluate_dirs, iou, normalize_number
from notbad_recog.schema import PageResult


def page(*questions):
    return PageResult.from_dict({"questions": list(questions)})


def q(number, bbox=(0, 0, 100, 100), wrong=False, mark="none"):
    return {"number": number, "bbox": list(bbox), "is_wrong": wrong, "teacher_mark": mark}


@pytest.mark.parametrize(
    "raw, expected",
    [("（2）", "2"), ("(2)", "2"), (" 3 ", "3"), ("二、1", "二.1"), ("二．1", "二.1"), ("１２", "12")],
)
def test_normalize_number(raw, expected):
    assert normalize_number(raw) == expected


def test_iou():
    assert iou([0, 0, 10, 10], [0, 0, 10, 10]) == 1
    assert iou([0, 0, 10, 10], [20, 20, 30, 30]) == 0
    assert iou([0, 0, 10, 10], [5, 0, 15, 10]) == pytest.approx(50 / 150)


def test_compare_page_counts():
    gt = page(q("1"), q("2", wrong=True, mark="wrong"), q("3", wrong=True), q("4"))
    pred = page(
        q("1", wrong=True),  # 误报
        q("(2)", wrong=True, mark="wrong"),  # 命中
        # 第 3 题没切出来 -> 漏报
        q("4"),
        q("5", wrong=True),  # 多切的题判为错 -> 误报
    )
    c = compare_page(gt, pred)
    assert (c.gt_questions, c.pred_questions, c.matched) == (4, 4, 3)
    assert (c.wrong_tp, c.wrong_fp, c.wrong_fn) == (1, 2, 1)
    assert c.mark_correct == 3
    assert c.iou_ge_50 == 3


def test_evaluate_dirs(tmp_path):
    labels, preds = tmp_path / "labels", tmp_path / "preds"
    labels.mkdir()
    preds.mkdir()
    (labels / "p1.json").write_text(json.dumps({"questions": [q("1", wrong=True), q("2")]}))
    (labels / "p2.json").write_text(json.dumps({"questions": [q("1", wrong=True)]}))
    (preds / "p1.json").write_text(json.dumps({"questions": [q("1", wrong=True), q("2")]}))

    summary = evaluate_dirs(labels, preds).summary()
    assert summary["missing_preds"] == ["p2"]
    assert summary["segmentation"]["recall"] == pytest.approx(2 / 3, abs=1e-4)
    assert summary["wrong_detection"]["recall"] == 0.5
    assert summary["wrong_detection"]["precision"] == 1.0
