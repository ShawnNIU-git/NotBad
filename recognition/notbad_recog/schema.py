"""识别结果的数据结构，以及从模型输出中解析 JSON。

模型输出与人工标注共用同一个格式，评测时直接对比。
"""

from __future__ import annotations

import json
import re
from dataclasses import asdict, dataclass, field

# 老师批改痕迹
MARKS = ("correct", "wrong", "partial", "none")


@dataclass
class Question:
    number: str  # 题号，如 "3" "二.1" "(2)"，按原卷书写
    bbox: list[float]  # [x0, y0, x1, y1]，0-1000 归一化坐标
    text: str = ""  # 题干，公式用 LaTeX（$...$）
    has_figure: bool = False  # 是否含几何图、图表等
    student_answer: str = ""
    teacher_mark: str = "none"  # 见 MARKS
    is_wrong: bool = False  # 最终判定：是否应进入错题本
    confidence: float = 0.0  # 模型对 is_wrong 的置信度 0-1
    knowledge_points: list[str] = field(default_factory=list)


@dataclass
class PageResult:
    subject: str = ""
    title: str = ""  # 试卷标题，识别不到为空
    paper_type: str = ""  # 单元测试/期中/期末/作业/练习/其他
    grade: str = ""
    questions: list[Question] = field(default_factory=list)
    notes: str = ""

    def to_dict(self) -> dict:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict) -> "PageResult":
        questions = [_parse_question(q) for q in data.get("questions", [])]
        return cls(
            subject=str(data.get("subject", "")),
            title=str(data.get("title", "") or "").strip(),
            paper_type=str(data.get("paper_type", "") or ""),
            grade=str(data.get("grade", "") or ""),
            questions=questions,
            notes=str(data.get("notes", "")),
        )


def _parse_question(q: dict) -> Question:
    bbox = q.get("bbox") or [0, 0, 0, 0]
    if len(bbox) != 4:
        raise ValueError(f"bbox 需要 4 个数: {bbox}")
    x0, y0, x1, y1 = (float(v) for v in bbox)
    mark = str(q.get("teacher_mark", "none")).lower()
    if mark not in MARKS:
        mark = "none"
    return Question(
        number=str(q.get("number", "")).strip(),
        bbox=[min(x0, x1), min(y0, y1), max(x0, x1), max(y0, y1)],
        text=str(q.get("text", "")),
        has_figure=bool(q.get("has_figure", False)),
        student_answer=str(q.get("student_answer", "")),
        teacher_mark=mark,
        is_wrong=bool(q.get("is_wrong", False)),
        confidence=float(q.get("confidence", 0.0)),
        knowledge_points=_str_list(q.get("knowledge_points")),
    )


def _str_list(value) -> list[str]:
    if not isinstance(value, list):
        return []
    return [str(v).strip() for v in value if str(v).strip()]


@dataclass
class Solution:
    """一道题的标准答案与解析。"""

    answer: str = ""
    explanation: str = ""
    knowledge_points: list[str] = field(default_factory=list)
    common_mistake: str = ""
    confidence: float = 0.0

    def to_dict(self) -> dict:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict) -> "Solution":
        return cls(
            answer=str(data.get("answer", "")),
            explanation=str(data.get("explanation", "")),
            knowledge_points=_str_list(data.get("knowledge_points")),
            common_mistake=str(data.get("common_mistake", "")),
            confidence=float(data.get("confidence", 0.0)),
        )


_FENCE_RE = re.compile(r"```(?:json)?\s*(.*?)```", re.DOTALL)


def extract_json(text: str) -> dict:
    """从模型回复中取出 JSON 对象，兼容 ```json 代码块和前后多余文字。"""
    m = _FENCE_RE.search(text)
    if m:
        text = m.group(1)
    start, end = text.find("{"), text.rfind("}")
    if start == -1 or end <= start:
        raise ValueError("模型回复中没有找到 JSON 对象")
    return json.loads(text[start : end + 1])


def parse_model_output(text: str) -> PageResult:
    return PageResult.from_dict(extract_json(text))


def parse_solution(text: str) -> Solution:
    return Solution.from_dict(extract_json(text))
