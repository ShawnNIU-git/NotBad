"""服务端配置，全部来自环境变量。

模型服务商的配置（NOTBAD_API_KEY、NOTBAD_API_BASE 等）沿用识别原型的同名变量，
见 recognition/notbad_recog/config.py。
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field


@dataclass(frozen=True)
class Settings:
    # 会员 token，逗号分隔。以后接入登录和订阅后换成数据库
    member_tokens: frozenset[str] = field(default_factory=frozenset)
    # 每个 token 每天最多调用次数（识别一页和解一道题各算一次）
    daily_limit: int = 200
    analyze_model: str = ""
    solve_model: str = ""
    max_upload_bytes: int = 10 * 1024 * 1024

    @classmethod
    def from_env(cls) -> "Settings":
        tokens = {t.strip() for t in os.environ.get("NOTBAD_MEMBER_TOKENS", "").split(",") if t.strip()}
        default_model = os.environ.get("NOTBAD_MODEL", "")
        return cls(
            member_tokens=frozenset(tokens),
            daily_limit=int(os.environ.get("NOTBAD_DAILY_LIMIT", "200")),
            analyze_model=os.environ.get("NOTBAD_ANALYZE_MODEL", default_model),
            solve_model=os.environ.get("NOTBAD_SOLVE_MODEL", default_model),
            max_upload_bytes=int(os.environ.get("NOTBAD_MAX_UPLOAD_MB", "10")) * 1024 * 1024,
        )
