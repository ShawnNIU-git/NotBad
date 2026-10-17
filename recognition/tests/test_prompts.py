from pathlib import Path

from notbad_recog.prompts import PROMPTS_DIR, SOLVE_PROMPT, SYSTEM_PROMPT

IOS_PROMPTS = Path(__file__).resolve().parents[2] / "ios" / "NotBadCore" / "Sources" / "NotBadCore" / "Resources" / "prompts"


def test_prompts_loaded():
    assert "bbox" in SYSTEM_PROMPT and "title" in SYSTEM_PROMPT
    assert "answer" in SOLVE_PROMPT


def test_ios_copy_matches_shared():
    """iOS 端打包的是 shared/prompts 的副本，改了提示词要运行 scripts/sync_prompts.sh。"""
    shared = sorted(PROMPTS_DIR.glob("*.md"))
    assert shared
    for path in shared:
        copy = IOS_PROMPTS / path.name
        assert copy.exists(), f"缺少 {copy}，请运行 scripts/sync_prompts.sh"
        assert copy.read_text(encoding="utf-8") == path.read_text(encoding="utf-8"), (
            f"{path.name} 与 iOS 副本不一致，请运行 scripts/sync_prompts.sh"
        )
