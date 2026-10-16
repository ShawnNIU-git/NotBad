# iOS App（路线图第 3 步：手动版 MVP）

SwiftUI + SwiftData，最低 iOS 17。所有数据只存在本机，不联网。

## 功能

1. **添加试卷**：系统文档扫描（自动找边、透视矫正、多页连拍），或从相册导入。
2. **框选错题**：在图上拖动画框，点框删除，可翻页。
3. **本地识别**：保存后在后台用 Apple Vision 识别题目文字，识别结果可以手动修改。
4. **错题本**：按学科筛选；每道题可填写当时的答案、正确答案与解析、错因标签和笔记。
5. **复习**：每天到期的题逐道出现，先自己做，再看答案，然后自评"不会 / 模糊 / 会了"，按间隔重复（简化 SM-2）安排下次复习。

## 在 Mac 上运行

```bash
brew install xcodegen
cd ios
xcodegen            # 生成 NotBad.xcodeproj（不进仓库）
open NotBad.xcodeproj
```

然后在 Xcode 的 Signing & Capabilities 里选你的 Team，并把 Bundle ID 改成自己的（`project.yml` 里的 `com.example.notbad`）。

- **模拟器**：没有文档扫描，用"从相册导入"。可以先把试卷照片拖进模拟器的相册。
- **真机**：免费 Apple ID 就能装到自己手机上（7 天后要重新安装）；上架 App Store 才需要付费开发者账号。

## 代码结构

```
ios/
├── project.yml              XcodeGen 配置
├── NotBadCore/              纯 Swift 核心库，不依赖 UIKit，可在 Linux/macOS 上 `swift test`
│   └── Sources/NotBadCore/
│       ├── NormalizedBox.swift      0-1000 归一化框，与识别原型的 bbox 一致
│       ├── RecognitionResult.swift  识别结果 JSON 解析（与 recognition/ 的格式一致）
│       ├── ReviewScheduler.swift    间隔重复算法
│       └── Catalog.swift            学科、错因、来源
└── NotBad/                  App
    ├── Models/Models.swift          SwiftData 模型：Paper、Mistake、ReviewLog
    ├── Services/                    ImageStore（图片文件）、TextRecognizer（Vision OCR）
    └── Features/
        ├── Capture/                 扫描、导入、框选
        ├── Mistakes/                错题列表与详情
        ├── Review/                  复习
        └── Shared/
```

图片存放在 `Application Support/Images/`，开启了文件保护（设备锁定时加密）；数据库只存文件名。

## 测试

```bash
cd ios/NotBadCore && swift test
```

CI（`.github/workflows/ci.yml`）会在 macOS 上跑核心库测试，并编译整个 App。

## 下一步

- 接入自动识别：识别原型选定模型后，加一个后端中转服务（API key 不能放在 App 里），App 上传整页图片，拿回 `RecognizedPage`，把 `isWrong` 的题预先框好，让用户确认或修改。`RecognitionParser` 已经能解析这种格式。
- 框选体验：双指缩放、拖动调整框的边。
- 导出 PDF 打印错题。
- 公式显示（SwiftMath 或 KaTeX）。
