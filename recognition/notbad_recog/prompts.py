"""给视觉模型的提示词。改提示词后要重新跑评测，对比准确率。

系统提示词放在仓库的 shared/prompts/ 下，Python 和 iOS App 共用同一份。
部署时可用环境变量 NOTBAD_PROMPTS_DIR 指定目录。
"""

import os
from pathlib import Path

PROMPTS_DIR = Path(
    os.environ.get("NOTBAD_PROMPTS_DIR", Path(__file__).resolve().parents[2] / "shared" / "prompts")
)


def load_prompt(name: str) -> str:
    return (PROMPTS_DIR / f"{name}.md").read_text(encoding="utf-8")


SYSTEM_PROMPT = load_prompt("analyze_page")
SOLVE_PROMPT = load_prompt("solve_question")

USER_PROMPT = "请分析这张试卷照片，按要求输出 JSON。"

PROBE_PROMPT = "图片里有一个彩色几何图形。请只回答它的颜色和形状，例如“红色圆形”。"


def solve_user_prompt(text: str, subject: str = "", student_answer: str = "") -> str:
    """解题请求的用户消息。与 iOS 端 Prompts.solveUserPrompt 保持一致。"""
    lines = []
    if subject:
        lines.append(f"学科：{subject}")
    lines.append(f"识别出的题干：{text or '（未识别，请看图片）'}")
    if student_answer:
        lines.append(f"学生的错误答案：{student_answer}")
    lines.append("请按要求输出 JSON。")
    return "\n".join(lines)
