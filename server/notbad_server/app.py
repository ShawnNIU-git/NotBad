"""HTTP 接口。

  POST /v1/pages/analyze     上传一页试卷照片，返回识别结果（PageResult）
  POST /v1/questions/solve   上传一道题的裁剪图和题干，返回答案（Solution）
  GET  /v1/me                查看今日剩余额度

请求头带 Authorization: Bearer <会员 token>。服务端不保存图片，也不记录题目内容。
"""

# 注意：不要加 from __future__ import annotations，FastAPI 要在运行时解析闭包里的 Depends。
import io
import logging
from typing import Annotated, Callable

from fastapi import Depends, FastAPI, File, Form, Header, HTTPException, UploadFile

from notbad_recog.client import VisionClient
from notbad_recog.config import Config
from notbad_recog.image_utils import load_image

from .quota import DailyQuota
from .settings import Settings

log = logging.getLogger("notbad_server")


def create_app(settings: Settings | None = None,
               client_factory: Callable[[], VisionClient] | None = None) -> FastAPI:
    settings = settings or Settings.from_env()
    quota = DailyQuota(settings.daily_limit)
    _client: list[VisionClient] = []

    def get_client() -> VisionClient:
        # 延迟创建，缺配置时启动不报错，调用时才报
        if not _client:
            _client.append(client_factory() if client_factory else VisionClient(Config.from_env(settings.analyze_model)))
        return _client[0]

    app = FastAPI(title="NotBad", version="0.1.0")

    def member_token(authorization: Annotated[str | None, Header()] = None) -> str:
        token = (authorization or "").removeprefix("Bearer ").strip()
        if not token or token not in settings.member_tokens:
            raise HTTPException(status_code=401, detail="会员凭证无效")
        return token

    def consume(token: str) -> None:
        if not quota.try_consume(token):
            raise HTTPException(status_code=402, detail="今日额度已用完")

    async def read_image(upload: UploadFile):
        data = await upload.read(settings.max_upload_bytes + 1)
        if len(data) > settings.max_upload_bytes:
            raise HTTPException(status_code=413, detail="图片太大")
        try:
            return load_image(io.BytesIO(data))
        except Exception:
            raise HTTPException(status_code=400, detail="无法读取图片") from None

    def call_upstream(token: str, fn):
        consume(token)
        try:
            return fn()
        except ValueError as e:  # 模型回复不是合法 JSON
            quota.refund(token)
            log.warning("模型回复解析失败: %s", e)
            raise HTTPException(status_code=502, detail="模型回复格式错误，请重试") from None
        except Exception as e:  # noqa: BLE001 - 上游网络或服务错误
            quota.refund(token)
            log.warning("上游调用失败: %s", str(e)[:200])
            raise HTTPException(status_code=502, detail="模型服务暂时不可用，请稍后重试") from None

    @app.get("/healthz")
    def healthz() -> dict:
        return {"ok": True}

    @app.get("/v1/me")
    def me(token: Annotated[str, Depends(member_token)]) -> dict:
        return {"daily_limit": quota.limit, "used_today": quota.used(token), "remaining": quota.remaining(token)}

    @app.post("/v1/pages/analyze")
    async def analyze(token: Annotated[str, Depends(member_token)],
                      image: Annotated[UploadFile, File()]) -> dict:
        img = await read_image(image)
        client = get_client()
        result, _ = await _run_sync(call_upstream, token,
                                    lambda: client.analyze_page(img, model=settings.analyze_model or None))
        return result.to_dict()

    @app.post("/v1/questions/solve")
    async def solve(token: Annotated[str, Depends(member_token)],
                    image: Annotated[UploadFile, File()],
                    text: Annotated[str, Form()] = "",
                    subject: Annotated[str, Form()] = "",
                    student_answer: Annotated[str, Form()] = "") -> dict:
        img = await read_image(image)
        client = get_client()
        solution, _ = await _run_sync(
            call_upstream, token,
            lambda: client.solve_question(img, text, subject, student_answer, model=settings.solve_model or None),
        )
        return solution.to_dict()

    return app


async def _run_sync(fn, *args):
    """模型调用是阻塞的 httpx 请求，放到线程池里跑，不卡事件循环。"""
    from starlette.concurrency import run_in_threadpool

    return await run_in_threadpool(fn, *args)


def app_factory() -> FastAPI:
    """uvicorn --factory notbad_server.app:app_factory"""
    logging.basicConfig(level=logging.INFO)
    return create_app()
