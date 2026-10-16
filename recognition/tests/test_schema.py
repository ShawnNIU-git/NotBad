import pytest

from notbad_recog.schema import extract_json, parse_model_output


def test_extract_json_from_fenced_block():
    text = '好的，结果如下：\n```json\n{"subject": "数学", "questions": []}\n```\n以上。'
    assert extract_json(text) == {"subject": "数学", "questions": []}


def test_extract_json_with_surrounding_text():
    assert extract_json('结果 {"a": 1} 完') == {"a": 1}


def test_extract_json_missing_raises():
    with pytest.raises(ValueError):
        extract_json("无法识别")


def test_parse_normalizes_fields():
    text = """{"subject": "数学", "questions": [
      {"number": " 3 ", "bbox": [500, 400, 100, 200], "teacher_mark": "WRONG",
       "is_wrong": true, "confidence": 0.8},
      {"number": "4", "bbox": [0, 0, 10, 10], "teacher_mark": "checkmark"}
    ]}"""
    result = parse_model_output(text)
    q3, q4 = result.questions
    assert q3.number == "3"
    assert q3.bbox == [100, 200, 500, 400]  # 坐标顺序被纠正
    assert q3.teacher_mark == "wrong"
    assert q3.is_wrong and q3.confidence == 0.8
    assert q4.teacher_mark == "none"  # 未知标记降级为 none
    assert not q4.is_wrong


def test_bad_bbox_raises():
    with pytest.raises(ValueError):
        parse_model_output('{"questions": [{"number": "1", "bbox": [1, 2, 3]}]}')
