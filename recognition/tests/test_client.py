import base64
import json

import httpx
from PIL import Image

from notbad_recog.client import VisionClient
from notbad_recog.config import Config

PAGE_JSON = {
    "subject": "数学",
    "questions": [{"number": "1", "bbox": [0, 0, 500, 200], "teacher_mark": "wrong", "is_wrong": True}],
}


def make_client(api_style, reply_body, captured):
    def handler(request: httpx.Request) -> httpx.Response:
        captured["url"] = str(request.url)
        captured["headers"] = request.headers
        captured["body"] = json.loads(request.content)
        return httpx.Response(200, json=reply_body)

    config = Config(api_key="k", model="m", api_style=api_style, max_image_side=100)
    return VisionClient(config, http=httpx.Client(transport=httpx.MockTransport(handler)))


def test_openai_style_request_and_parse():
    captured = {}
    reply = {"choices": [{"message": {"content": "```json\n" + json.dumps(PAGE_JSON) + "\n```"}}]}
    client = make_client("openai", reply, captured)

    result, _ = client.analyze_page(Image.new("RGB", (400, 300), "white"))

    assert captured["url"] == "https://opencode.ai/inference/go/openai/v1/chat/completions"
    assert captured["headers"]["authorization"] == "Bearer k"
    assert captured["headers"]["user-agent"].startswith("notbad-recog/")
    messages = captured["body"]["messages"]
    assert messages[0]["role"] == "system"
    image_url = messages[1]["content"][0]["image_url"]["url"]
    assert image_url.startswith("data:image/jpeg;base64,")
    # 图片被缩到 max_image_side 以内
    img_bytes = base64.b64decode(image_url.split(",", 1)[1])
    assert Image.open(__import__("io").BytesIO(img_bytes)).size == (100, 75)
    assert result.questions[0].is_wrong


def test_anthropic_style_request_and_parse():
    captured = {}
    reply = {"content": [{"type": "text", "text": json.dumps(PAGE_JSON)}]}
    client = make_client("anthropic", reply, captured)

    result, _ = client.analyze_page(Image.new("RGB", (50, 50), "white"))

    assert captured["url"].endswith("/anthropic/v1/messages")
    assert captured["headers"]["x-api-key"] == "k"
    assert "system" in captured["body"]
    assert captured["body"]["messages"][0]["content"][0]["type"] == "image"
    assert result.subject == "数学"


def test_solve_question_uses_solve_prompt_and_model_override():
    captured = {}
    reply = {"choices": [{"message": {"content": '{"answer": "11", "explanation": "先乘后加", "confidence": 0.95}'}}]}
    client = make_client("openai", reply, captured)

    solution, _ = client.solve_question(
        Image.new("RGB", (50, 50)), text="3+4×2=", subject="数学", student_answer="14", model="solver"
    )

    body = captured["body"]
    assert body["model"] == "solver"
    assert "标准答案" in body["messages"][0]["content"]
    user_text = body["messages"][1]["content"][1]["text"]
    assert "3+4×2=" in user_text and "14" in user_text and "数学" in user_text
    assert solution.answer == "11"
