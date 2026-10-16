"""命令行入口。

  notbad-recog probe    --model kimi-k3 --model qwen3.8-max   测试哪些模型能看图
  notbad-recog analyze  data/images/*.jpg -o out              识别试卷，输出 JSON、切题图和标注图
  notbad-recog evaluate data/labels out/preds                  对比标注，算准确率
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
from pathlib import Path

from PIL import Image, ImageDraw

from .config import Config
from .evaluate import evaluate_dirs
from .image_utils import bbox_to_pixels, crop_bbox, load_image
from .prompts import PROBE_PROMPT
from .schema import PageResult

IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".webp"}  # iPhone 的 HEIC 需先导出为 JPEG

PROBE_SHAPES = [("红色", "red", "ellipse"), ("蓝色", "blue", "rectangle"), ("绿色", "green", "triangle")]


def _probe_image(color: str, shape: str) -> Image.Image:
    img = Image.new("RGB", (400, 400), "white")
    draw = ImageDraw.Draw(img)
    if shape == "ellipse":
        draw.ellipse((100, 100, 300, 300), fill=color)
    elif shape == "rectangle":
        draw.rectangle((100, 120, 300, 280), fill=color)
    else:
        draw.polygon([(200, 80), (320, 320), (80, 320)], fill=color)
    return img


def cmd_probe(args: argparse.Namespace) -> int:
    """用简单图形测试模型是否真的接收了图片（不支持看图的模型会瞎猜或报错）。"""
    from .client import VisionClient

    models = args.model or [None]
    for model in models:
        config = Config.from_env(model)
        client = VisionClient(config)
        hits = 0
        details = []
        for zh_color, color, shape in PROBE_SHAPES:
            try:
                answer = client.ask(_probe_image(color, shape), PROBE_PROMPT, max_tokens=256).strip()
            except Exception as e:  # noqa: BLE001 - 探测时任何失败都只记录
                answer = f"<错误> {e}"
            hits += zh_color in answer
            details.append(f"    期望 {zh_color}: {answer[:80]!r}")
        verdict = "支持看图" if hits == len(PROBE_SHAPES) else "可能不支持看图"
        print(f"{config.model}: {hits}/{len(PROBE_SHAPES)} {verdict}")
        if args.verbose or hits < len(PROBE_SHAPES):
            print("\n".join(details))
    return 0


def _safe_name(number: str, index: int) -> str:
    name = re.sub(r"[^\w.\-]", "_", number) or "q"
    return f"{index:02d}_{name}"


def _draw_overlay(img: Image.Image, result: PageResult) -> Image.Image:
    out = img.copy()
    draw = ImageDraw.Draw(out)
    width = max(2, img.size[0] // 400)
    for q in result.questions:
        box = bbox_to_pixels(q.bbox, img.size)
        color = "red" if q.is_wrong else "green"
        draw.rectangle(box, outline=color, width=width)
        draw.text((box[0] + 4, box[1] + 4), f"{q.number} {q.teacher_mark} {q.confidence:.2f}", fill=color)
    return out


def _collect_images(paths: list[str]) -> list[Path]:
    images: list[Path] = []
    for p in map(Path, paths):
        if p.is_dir():
            images.extend(sorted(f for f in p.iterdir() if f.suffix.lower() in IMAGE_SUFFIXES))
        else:
            images.append(p)
    return images


def cmd_analyze(args: argparse.Namespace) -> int:
    from .client import VisionClient

    config = Config.from_env(args.model)
    client = VisionClient(config)
    out = Path(args.out)
    preds_dir, raw_dir = out / "preds", out / "raw"
    crops_dir, overlay_dir = out / "crops", out / "overlay"
    for d in (preds_dir, raw_dir, crops_dir, overlay_dir):
        d.mkdir(parents=True, exist_ok=True)

    images = _collect_images(args.images)
    failures = 0
    for path in images:
        pred_path = preds_dir / f"{path.stem}.json"
        if pred_path.exists() and not args.force:
            print(f"跳过 {path.name}（已有结果，--force 重跑）")
            continue
        img = load_image(path)
        start = time.monotonic()
        try:
            result, raw = client.analyze_page(img)
        except Exception as e:  # noqa: BLE001 - 单页失败不影响其他页
            failures += 1
            print(f"失败 {path.name}: {e}", file=sys.stderr)
            continue
        elapsed = time.monotonic() - start
        (raw_dir / f"{path.stem}.txt").write_text(raw, encoding="utf-8")
        pred_path.write_text(json.dumps(result.to_dict(), ensure_ascii=False, indent=2), encoding="utf-8")

        page_crops = crops_dir / path.stem
        page_crops.mkdir(exist_ok=True)
        for i, q in enumerate(result.questions):
            crop_bbox(img, q.bbox).save(page_crops / f"{_safe_name(q.number, i)}.jpg", quality=90)
        _draw_overlay(img, result).save(overlay_dir / f"{path.stem}.jpg", quality=85)

        n_wrong = sum(q.is_wrong for q in result.questions)
        print(f"{path.name}: {len(result.questions)} 题, {n_wrong} 道错题, {elapsed:.1f}s")
    return 1 if failures else 0


def cmd_evaluate(args: argparse.Namespace) -> int:
    report = evaluate_dirs(Path(args.labels), Path(args.preds))
    summary = report.summary()
    if args.per_page:
        summary["per_page"] = {
            name: {
                "gt": c.gt_questions,
                "pred": c.pred_questions,
                "matched": c.matched,
                "wrong_tp": c.wrong_tp,
                "wrong_fp": c.wrong_fp,
                "wrong_fn": c.wrong_fn,
            }
            for name, c in report.pages.items()
        }
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="notbad-recog", description="试卷切题与判错原型")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("probe", help="测试模型能否看图")
    p.add_argument("--model", action="append", help="可重复，测试多个模型；默认用 NOTBAD_MODEL")
    p.add_argument("-v", "--verbose", action="store_true")
    p.set_defaults(func=cmd_probe)

    p = sub.add_parser("analyze", help="识别试卷照片")
    p.add_argument("images", nargs="+", help="图片文件或目录")
    p.add_argument("-o", "--out", default="out")
    p.add_argument("--model")
    p.add_argument("--force", action="store_true", help="覆盖已有结果")
    p.set_defaults(func=cmd_analyze)

    p = sub.add_parser("evaluate", help="对比标注计算准确率")
    p.add_argument("labels", help="标注 JSON 目录")
    p.add_argument("preds", help="模型输出 JSON 目录（analyze 的 out/preds）")
    p.add_argument("--per-page", action="store_true")
    p.set_defaults(func=cmd_evaluate)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
