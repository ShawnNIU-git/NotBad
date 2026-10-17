# 中转后端（会员模式）

这是一个**不跑模型**的小服务：App 把照片发给它，它带上我们自己的 API key 转发给模型服务商（开发期用 OpenCode Go，上线换按量计费的 API），再把结果返回给 App。顺便做会员鉴权和每日限额。

用户选"自备 API key"时，App 直接连服务商，不经过这里。

识别、解析和提示词全部复用 `recognition/`（`notbad_recog` 包）和 `shared/prompts/`。在这里改提示词立即生效，App 不用重新发版。

## 在 Mac 上运行

```bash
cd NotBad
python3 -m venv .venv && source .venv/bin/activate
pip install -e ./recognition -e "./server[dev]"

export NOTBAD_API_KEY=你的服务商key
export NOTBAD_MODEL=kimi-k3                 # 先用 notbad-recog probe 找出能看图的模型
export NOTBAD_API_STYLE=openai              # 或 anthropic，见 recognition/README.md
export NOTBAD_SOLVE_MODEL=deepseek-v4-pro   # 可选：解题用另一个模型，默认同 NOTBAD_MODEL
export NOTBAD_MEMBER_TOKENS=dev-token-1     # 会员 token，逗号分隔
export NOTBAD_DAILY_LIMIT=200               # 每个 token 每日调用上限

uvicorn --factory notbad_server.app:app_factory --host 0.0.0.0 --port 8000
```

- iOS 模拟器：App 设置里的服务地址填 `http://localhost:8000`。
- 真机：iPhone 和 Mac 连同一个 Wi‑Fi，填 `http://<Mac 的局域网 IP>:8000`（系统设置 → Wi‑Fi → 详细信息里能看到 IP）。
- 浏览器打开 `http://localhost:8000/docs` 可以直接试接口。

注意：解题模型的输入也带图片，所以 `NOTBAD_SOLVE_MODEL` 也必须能看图。

## 接口

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/v1/pages/analyze` | multipart：`image`。返回 PageResult JSON |
| POST | `/v1/questions/solve` | multipart：`image`，表单字段 `text`、`subject`、`student_answer`。返回 Solution JSON |
| GET | `/v1/me` | 今日额度 |

都需要请求头 `Authorization: Bearer <token>`。错误码：401 凭证无效，402 额度用完，413 图片太大，502 模型服务出错（不扣额度）。

## 测试

```bash
cd server && pytest
```

## 上线前要做的

- 模型换成按量计费的正式 API（OpenCode Go 订阅不允许这样转售）。
- 会员 token 换成登录 + App Store 订阅（StoreKit 2，服务端验证收据），额度存数据库或 Redis（现在存在内存里，重启清零）。
- 部署到国内云（轻量服务器 + Docker，或阿里云函数计算），开 HTTPS。
- 服务端不保存图片、日志不打印题目内容，这一点要写进隐私政策。
