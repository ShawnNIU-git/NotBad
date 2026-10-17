"""调用视觉模型。支持 OpenAI Chat Completions 和 Anthropic Messages 两种格式。"""

from __future__ import annotations

import uuid

import httpx
from PIL import Image

from . import __version__
from .config import Config
from .image_utils import resize_max_side, to_jpeg_base64
from .prompts import SOLVE_PROMPT, SYSTEM_PROMPT, USER_PROMPT, solve_user_prompt
from .schema import PageResult, Solution, parse_model_output, parse_solution


class VisionClient:
    def __init__(self, config: Config, http: httpx.Client | None = None):
        self.config = config
        self.http = http or httpx.Client(timeout=config.timeout)

    def _headers(self) -> dict[str, str]:
        headers = {
            "Content-Type": "application/json",
            "User-Agent": f"notbad-recog/{__version__}",
            # OpenCode 用它做路由和缓存，每次请求用独立 ID
            "x-opencode-session": str(uuid.uuid4()),
        }
        if self.config.api_style == "anthropic":
            headers["x-api-key"] = self.config.api_key
            headers["anthropic-version"] = "2023-06-01"
        else:
            headers["Authorization"] = f"Bearer {self.config.api_key}"
        return headers

    def _payload(self, system: str, user: str, image_b64: str, max_tokens: int, model: str) -> dict:
        if self.config.api_style == "anthropic":
            return {
                "model": model,
                "max_tokens": max_tokens,
                "system": system,
                "messages": [
                    {
                        "role": "user",
                        "content": [
                            {
                                "type": "image",
                                "source": {
                                    "type": "base64",
                                    "media_type": "image/jpeg",
                                    "data": image_b64,
                                },
                            },
                            {"type": "text", "text": user},
                        ],
                    }
                ],
            }
        messages = []
        if system:
            messages.append({"role": "system", "content": system})
        messages.append(
            {
                "role": "user",
                "content": [
                    {
                        "type": "image_url",
                        "image_url": {"url": f"data:image/jpeg;base64,{image_b64}"},
                    },
                    {"type": "text", "text": user},
                ],
            }
        )
        return {
            "model": model,
            "max_tokens": max_tokens,
            "temperature": 0,
            "messages": messages,
        }

    @staticmethod
    def _extract_text(api_style: str, data: dict) -> str:
        if api_style == "anthropic":
            return "".join(b.get("text", "") for b in data.get("content", []) if b.get("type") == "text")
        content = data["choices"][0]["message"].get("content") or ""
        if isinstance(content, list):  # 部分服务商返回分段内容
            content = "".join(part.get("text", "") for part in content)
        return content

    def ask(self, img: Image.Image, user: str, system: str = "", max_tokens: int = 4096,
            model: str | None = None) -> str:
        """发送一张图和一段文字，返回模型的原始文本回复。model 为空时用配置里的模型。"""
        img = resize_max_side(img, self.config.max_image_side)
        payload = self._payload(system, user, to_jpeg_base64(img), max_tokens, model or self.config.model)
        resp = self.http.post(self.config.endpoint, headers=self._headers(), json=payload)
        if resp.status_code >= 400:
            raise RuntimeError(f"HTTP {resp.status_code}: {resp.text[:500]}")
        return self._extract_text(self.config.api_style, resp.json())

    def analyze_page(self, img: Image.Image, model: str | None = None) -> tuple[PageResult, str]:
        """分析一页试卷，返回 (解析后的结果, 原始回复)。原始回复用于排查解析失败。"""
        raw = self.ask(img, USER_PROMPT, SYSTEM_PROMPT, max_tokens=8192, model=model)
        return parse_model_output(raw), raw

    def solve_question(self, img: Image.Image, text: str = "", subject: str = "",
                       student_answer: str = "", model: str | None = None) -> tuple[Solution, str]:
        """为一道题生成标准答案和解析，返回 (解析后的结果, 原始回复)。"""
        user = solve_user_prompt(text, subject, student_answer)
        raw = self.ask(img, user, SOLVE_PROMPT, max_tokens=4096, model=model)
        return parse_solution(raw), raw
