"""从环境变量读取模型服务配置。

默认指向 OpenCode Go 的 OpenAI 兼容接口，但任何 OpenAI Chat Completions
或 Anthropic Messages 格式的服务都可以用，换服务商只需改环境变量。
"""

from __future__ import annotations

import os
from dataclasses import dataclass

DEFAULT_BASE_URL = "https://opencode.ai/inference/go"

# 不同 API 风格对应的路径（拼在 base_url 后面）
API_PATHS = {
    "openai": "/openai/v1/chat/completions",
    "anthropic": "/anthropic/v1/messages",
}


@dataclass(frozen=True)
class Config:
    api_key: str
    model: str
    base_url: str = DEFAULT_BASE_URL
    api_style: str = "openai"  # "openai" 或 "anthropic"
    path: str | None = None  # 覆盖默认路径，用于非 OpenCode 的服务商
    timeout: float = 120.0
    max_image_side: int = 2048

    @property
    def endpoint(self) -> str:
        path = self.path if self.path is not None else API_PATHS[self.api_style]
        return self.base_url.rstrip("/") + path

    @classmethod
    def from_env(cls, model: str | None = None) -> "Config":
        api_key = os.environ.get("NOTBAD_API_KEY", "")
        if not api_key:
            raise SystemExit("缺少环境变量 NOTBAD_API_KEY")
        model = model or os.environ.get("NOTBAD_MODEL", "")
        if not model:
            raise SystemExit("缺少模型名：设置 NOTBAD_MODEL 或使用 --model")
        api_style = os.environ.get("NOTBAD_API_STYLE", "openai")
        if api_style not in API_PATHS:
            raise SystemExit(f"NOTBAD_API_STYLE 只能是 {sorted(API_PATHS)}")
        return cls(
            api_key=api_key,
            model=model,
            base_url=os.environ.get("NOTBAD_API_BASE", DEFAULT_BASE_URL),
            api_style=api_style,
            path=os.environ.get("NOTBAD_API_PATH") or None,
            timeout=float(os.environ.get("NOTBAD_TIMEOUT", "120")),
            max_image_side=int(os.environ.get("NOTBAD_MAX_IMAGE_SIDE", "2048")),
        )
