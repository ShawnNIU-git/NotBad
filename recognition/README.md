# 识别原型（路线图第 2 步）

App 开发之前，先在电脑上验证"切题 + 判错"能做到多准。这里有三个命令：

| 命令 | 作用 |
|---|---|
| `probe` | 用简单图形测试模型是否真能看图 |
| `analyze` | 识别试卷照片，输出每页 JSON、单题裁剪图、带框的标注图 |
| `evaluate` | 把模型输出和人工标注对比，算切题召回率、错题检测的精确率/召回率 |

## 安装

```bash
cd recognition
python3 -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]"
pytest            # 单元测试，不需要 API key
```

## 配置模型

所有配置走环境变量，换服务商不用改代码：

```bash
export NOTBAD_API_KEY=你的key
export NOTBAD_MODEL=kimi-k3                # 模型 ID，见 OpenCode Go 文档
export NOTBAD_API_STYLE=openai             # openai（Chat Completions）或 anthropic（Messages）
# 默认 NOTBAD_API_BASE=https://opencode.ai/inference/go
# 其他服务商：设置 NOTBAD_API_BASE，并用 NOTBAD_API_PATH 指定完整路径，例如
#   NOTBAD_API_BASE=https://dashscope.aliyuncs.com NOTBAD_API_PATH=/compatible-mode/v1/chat/completions
```

OpenCode Go 里不同模型走不同接口：GLM、Kimi、DeepSeek、MiMo 等用 `openai`；Claude Haiku、MiniMax、Qwen 用 `anthropic`。文档没写哪些模型支持图片，所以先跑 `probe`：

```bash
notbad-recog probe --model kimi-k3 --model glm-5.3 --model mimo-v2.6-pro -v
NOTBAD_API_STYLE=anthropic notbad-recog probe --model qwen3.8-max --model claude-haiku-5-5
```

3/3 才算支持看图；不支持的模型通常会报错或瞎猜。

## 准备评测集

1. 收集 100–200 张真实试卷照片，放进 `data/images/`（已被 `.gitignore` 排除）。多准备一些困难样本：阴影、折痕、倾斜、手指遮挡、带几何图的题、没有批改痕迹的卷子。
2. 拍照前或标注时**遮住姓名、学校、班级、考号**。
3. 每张图写一个同名标注 `data/labels/<图片名>.json`，格式见 [`data/example/page_example.json`](data/example/page_example.json)：
   - `bbox`：题目区域，0–1000 归一化坐标 `[x0, y0, x1, y1]`，左上角为原点。
   - `teacher_mark`：`correct` / `wrong` / `partial` / `none`。
   - `is_wrong`：这道题是否应进错题本（标准答案）。
   - 小题写成 `二.1`；`（2）`、`(2)`、`2` 评测时视为同一题号。

省时的标注方法：先跑一遍 `analyze`，把 `out/preds/*.json` 复制到 `data/labels/` 再人工修改，比从零开始快得多。

## 跑评测

```bash
notbad-recog analyze data/images -o out/kimi-k3 --model kimi-k3
notbad-recog evaluate data/labels out/kimi-k3/preds --per-page
```

输出示例：

```json
{
  "segmentation": {"recall": 0.93, "precision": 0.95, "mean_iou": 0.81, "iou_ge_0.5": 0.9},
  "teacher_mark_accuracy": 0.88,
  "wrong_detection": {"precision": 0.85, "recall": 0.9, "f1": 0.87}
}
```

怎么读这些指标：

- **错题召回率**最重要。漏掉的错题用户不会知道；误报可以在 App 里一键删掉。
- `segmentation.recall` 低说明切题漏题，`mean_iou` 低说明框不准，裁剪图会缺内容。
- 结果按 `out/<模型名>/` 分目录存，换模型或改 `prompts.py` 后重跑，横向对比。
- 打开 `out/.../overlay/` 看标注图（红框为判错，绿框为判对），定位出错原因。

## 关于 OpenCode Go 订阅

用它在电脑上做原型评测没问题，但**不要用它支撑上线后的 App**：

- 官方文档写明 Go 是为 OpenCode 和其他编程 agent 设计的，流量会被监控，非编程类的批量调用有被限流或封号的风险。
- 订阅只限单人工作区，按 5 小时、每周、每月的美元额度限流，撑不住多用户并发。
- 部分模型（Gemini / Muse Spark 的 Contributor 版本）的数据**可能被用于训练**。试卷照片涉及未成年人信息，评测时避开这些模型。

上线时换成按量计费的正式 API（国内如阿里云百炼的 Qwen-VL、智谱 GLM-V、豆包视觉，或 Claude、GPT 等），因为接口格式兼容，改环境变量即可。评测集也正好用来挑选性价比最高的模型。
