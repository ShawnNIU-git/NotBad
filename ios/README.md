# iOS App

SwiftUI + SwiftData，最低 iOS 17。错题和照片只存在本机。

## 功能

1. **拍照即识别**：拍摄（系统文档扫描，自动找边、矫正、多页连拍）或从相册导入后，每页自动交给大模型识别：
   - 切出每道题，判断哪些做错了（看老师的红叉、扣分，或模型自己判断）；
   - 识别学科、试卷标题、类型（单元测试/期中/期末/作业/练习）、年级，识别不到就留空；
   - 题干转成文字，公式转成 LaTeX，并标出知识点。
2. **确认页**：错题已经用红框标好，把握不大的用橙框。点灰框（判对的题）可改为错题，点红框可取消，拖动可以补框。可以选择新建试卷，或把页面追加到已有试卷。
3. **自动生成答案**：保存后在后台逐题生成标准答案、分步解析和易错提醒，标注"AI 生成，仅供参考"，可以一键"采用为我的订正"或重新生成。退出 App 也不会丢，下次打开继续。
4. **错题本 / 试卷 / 复习**：按学科筛选错题；按试卷浏览原卷和错题，随时"添加一页"；复习时先自己做，再看答案，自评"不会 / 模糊 / 会了"，按间隔重复安排下次复习。
5. **公式显示**：打包了离线的 KaTeX，题干和解析里的 `$...$` 公式正常显示。

## 识别方式（设置页）

| 方式 | 说明 |
|---|---|
| 会员服务 | App 连我们的中转后端 [`server/`](../server/README.md)，由后端带我们的 key 转发给模型服务商 |
| 自备 API key | 用户填自己的服务商、key 和模型，App 直连服务商；key 存在钥匙串 |
| 不使用 | 不联网，手动框选错题，本机识别文字，不生成答案 |

设置页的"测试连接"会发一张红色圆形的测试图，确认模型真的能看图。

## 在 Mac 上运行

```bash
brew install xcodegen
cd ios
xcodegen            # 生成 NotBad.xcodeproj（不进仓库）
open NotBad.xcodeproj
```

在 Xcode 的 Signing & Capabilities 里选你的 Team，并把 Bundle ID 改成自己的（`project.yml` 里的 `com.example.notbad`）。免费 Apple ID 就能装到自己手机上（7 天后要重新安装）。

### 联调会员模式

1. 按 [`server/README.md`](../server/README.md) 在 Mac 上启动中转服务（填你的 OpenCode Go key 和会员 token）。
2. App → 设置 → 会员服务：
   - 模拟器填 `http://localhost:8000`；
   - 真机（和 Mac 同一 Wi‑Fi）填 `http://<Mac 的局域网 IP>:8000`，第一次连接时允许"本地网络"权限。
3. 点"测试连接"，看到剩余额度就通了。

### 联调自备 key 模式

App → 设置 → 自备 API key → 服务商选"OpenCode Go"，填 key 和模型 ID（先用 `notbad-recog probe` 找出能看图的模型），点"测试连接"。

模拟器没有文档扫描，用"从相册导入"（可以先把试卷照片拖进模拟器）。

## 代码结构

```
ios/
├── project.yml                     XcodeGen 配置
├── NotBadCore/                     纯 Swift 核心库，可在 Linux/macOS 上 `swift test`
│   └── Sources/NotBadCore/
│       ├── RecognitionResult.swift 识别结果和答案的 JSON 格式（与 Python 端一致）
│       ├── Services/               识别服务：DirectLLMService（直连）、CloudService（会员）、提示词
│       ├── Resources/prompts/      shared/prompts 的副本（scripts/sync_prompts.sh 同步）
│       ├── NormalizedBox.swift     0-1000 归一化框
│       ├── ReviewScheduler.swift   间隔重复
│       └── Catalog.swift           学科、错因、试卷类型、答案状态
└── NotBad/
    ├── Models/Models.swift         SwiftData：Paper、Mistake、ReviewLog
    ├── Services/                   ImageStore、KeychainStore、ServiceSettings、AnswerGenerator、TextRecognizer
    ├── Resources/KaTeX/            离线公式渲染
    └── Features/
        ├── Capture/                拍照/导入、自动识别、确认页（CaptureViewModel）
        ├── Mistakes/               错题列表与详情（含 AI 答案）
        ├── Papers/                 试卷列表与详情
        ├── Review/                 复习
        ├── Settings/               识别方式设置
        └── Shared/                 StoredImageView、MathText
```

## 测试

```bash
cd ios/NotBadCore && swift test
```

CI 会在 macOS 上跑核心库测试并编译整个 App。界面部分没有自动化测试，需要在模拟器或真机上手动验证。
