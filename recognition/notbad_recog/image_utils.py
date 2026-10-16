"""图片读取、缩放、编码与裁剪。"""

from __future__ import annotations

import base64
import io
from pathlib import Path

from PIL import Image, ImageOps

# bbox 统一用 0-1000 的归一化坐标 [x0, y0, x1, y1]，与图片实际分辨率无关
BBOX_SCALE = 1000


def load_image(path: str | Path) -> Image.Image:
    """读取图片并按 EXIF 方向转正（手机照片常带旋转标记）。"""
    img = Image.open(path)
    img = ImageOps.exif_transpose(img)
    return img.convert("RGB")


def resize_max_side(img: Image.Image, max_side: int) -> Image.Image:
    w, h = img.size
    scale = max_side / max(w, h)
    if scale >= 1:
        return img
    return img.resize((round(w * scale), round(h * scale)), Image.LANCZOS)


def to_jpeg_base64(img: Image.Image, quality: int = 90) -> str:
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=quality)
    return base64.b64encode(buf.getvalue()).decode("ascii")


def bbox_to_pixels(bbox: list[float], size: tuple[int, int]) -> tuple[int, int, int, int]:
    w, h = size
    x0, y0, x1, y1 = bbox
    left = max(0, min(w, round(x0 / BBOX_SCALE * w)))
    top = max(0, min(h, round(y0 / BBOX_SCALE * h)))
    right = max(0, min(w, round(x1 / BBOX_SCALE * w)))
    bottom = max(0, min(h, round(y1 / BBOX_SCALE * h)))
    return left, top, right, bottom


def crop_bbox(img: Image.Image, bbox: list[float], pad: float = 10) -> Image.Image:
    """按归一化 bbox 裁剪，四周留一点余量（pad 也是 0-1000 单位）。"""
    padded = [bbox[0] - pad, bbox[1] - pad, bbox[2] + pad, bbox[3] + pad]
    return img.crop(bbox_to_pixels(padded, img.size))
