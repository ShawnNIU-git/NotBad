"""对比模型输出与人工标注，计算切题和判错的准确率。

题目按题号匹配。错题检测最关心召回率（漏掉的错题用户不会发现），
误报可以靠手动修正界面补救，代价较小。
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from pathlib import Path

from .schema import PageResult, Question


_NUMBER_TABLE = str.maketrans("（）．。、，０１２３４５６７８９", "()....0123456789")


def normalize_number(number: str) -> str:
    """统一题号写法：全角转半角，、。．统一为点，去掉空白和括号。

    "（2）" 和 "(2)" 和 "2" 视为同一题；"二、1" 和 "二.1" 视为同一题。
    """
    s = number.translate(_NUMBER_TABLE)
    s = re.sub(r"[\s()]", "", s)
    return re.sub(r"\.+", ".", s).strip(".")


def iou(a: list[float], b: list[float]) -> float:
    ix = max(0.0, min(a[2], b[2]) - max(a[0], b[0]))
    iy = max(0.0, min(a[3], b[3]) - max(a[1], b[1]))
    inter = ix * iy
    area_a = (a[2] - a[0]) * (a[3] - a[1])
    area_b = (b[2] - b[0]) * (b[3] - b[1])
    union = area_a + area_b - inter
    return inter / union if union > 0 else 0.0


@dataclass
class Counts:
    gt_questions: int = 0
    pred_questions: int = 0
    matched: int = 0
    iou_sum: float = 0.0
    iou_ge_50: int = 0
    mark_correct: int = 0
    wrong_tp: int = 0
    wrong_fp: int = 0
    wrong_fn: int = 0

    def add(self, other: "Counts") -> None:
        for name in self.__dataclass_fields__:
            setattr(self, name, getattr(self, name) + getattr(other, name))


@dataclass
class Report:
    total: Counts = field(default_factory=Counts)
    pages: dict[str, Counts] = field(default_factory=dict)
    missing_preds: list[str] = field(default_factory=list)

    def summary(self) -> dict:
        c = self.total
        precision = _ratio(c.wrong_tp, c.wrong_tp + c.wrong_fp)
        recall = _ratio(c.wrong_tp, c.wrong_tp + c.wrong_fn)
        f1 = _ratio(2 * precision * recall, precision + recall)
        return {
            "pages": len(self.pages),
            "missing_preds": self.missing_preds,
            "segmentation": {
                "gt_questions": c.gt_questions,
                "pred_questions": c.pred_questions,
                "recall": _ratio(c.matched, c.gt_questions),
                "precision": _ratio(c.matched, c.pred_questions),
                "mean_iou": _ratio(c.iou_sum, c.matched),
                "iou_ge_0.5": _ratio(c.iou_ge_50, c.matched),
            },
            "teacher_mark_accuracy": _ratio(c.mark_correct, c.matched),
            "wrong_detection": {
                "tp": c.wrong_tp,
                "fp": c.wrong_fp,
                "fn": c.wrong_fn,
                "precision": precision,
                "recall": recall,
                "f1": f1,
            },
        }


def _ratio(num: float, den: float) -> float:
    return round(num / den, 4) if den else 0.0


def compare_page(gt: PageResult, pred: PageResult) -> Counts:
    c = Counts(gt_questions=len(gt.questions), pred_questions=len(pred.questions))
    pred_by_num: dict[str, Question] = {}
    for q in pred.questions:
        pred_by_num.setdefault(normalize_number(q.number), q)

    used: set[str] = set()
    for g in gt.questions:
        key = normalize_number(g.number)
        p = pred_by_num.get(key)
        if p is not None and key not in used:
            used.add(key)
            c.matched += 1
            score = iou(g.bbox, p.bbox)
            c.iou_sum += score
            c.iou_ge_50 += score >= 0.5
            c.mark_correct += g.teacher_mark == p.teacher_mark
            pred_wrong = p.is_wrong
        else:
            pred_wrong = False  # 没切出来的题等于没检测到
        if g.is_wrong and pred_wrong:
            c.wrong_tp += 1
        elif g.is_wrong:
            c.wrong_fn += 1
        elif pred_wrong:
            c.wrong_fp += 1

    # 模型多切出来、标注里没有的题，如果判为错题就算误报
    for key, p in pred_by_num.items():
        if key not in used and p.is_wrong:
            c.wrong_fp += 1
    return c


def load_page(path: Path) -> PageResult:
    return PageResult.from_dict(json.loads(path.read_text(encoding="utf-8")))


def evaluate_dirs(labels_dir: Path, preds_dir: Path) -> Report:
    report = Report()
    for label_path in sorted(labels_dir.glob("*.json")):
        pred_path = preds_dir / label_path.name
        gt = load_page(label_path)
        if pred_path.exists():
            pred = load_page(pred_path)
        else:
            report.missing_preds.append(label_path.stem)
            pred = PageResult()
        counts = compare_page(gt, pred)
        report.pages[label_path.stem] = counts
        report.total.add(counts)
    return report
