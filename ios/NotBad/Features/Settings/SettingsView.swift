import NotBadCore
import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.mode) private var mode: ServiceMode = .manual
    @AppStorage(SettingsKey.serverURL) private var serverURL = ""
    @AppStorage(SettingsKey.presetID) private var presetID = ProviderPreset.all[0].id
    @AppStorage(SettingsKey.endpoint) private var endpoint = ProviderPreset.all[0].endpoint
    @AppStorage(SettingsKey.apiStyle) private var apiStyle: APIStyle = ProviderPreset.all[0].apiStyle
    @AppStorage(SettingsKey.analyzeModel) private var analyzeModel = ""
    @AppStorage(SettingsKey.solveModel) private var solveModel = ""

    @State private var memberToken = KeychainStore.get(SettingsKey.memberToken)
    @State private var apiKey = KeychainStore.get(SettingsKey.apiKey)
    @State private var testResult: String?
    @State private var isTesting = false

    private static let customPresetID = "custom"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("识别方式", selection: $mode) {
                        ForEach(ServiceMode.allCases) { Text($0.title).tag($0) }
                    }
                } footer: {
                    Text(modeFooter)
                }

                switch mode {
                case .member: memberSection
                case .ownKey: ownKeySection
                case .manual: EmptyView()
                }

                if mode != .manual {
                    Section {
                        Button(isTesting ? "测试中…" : "测试连接", action: testConnection)
                            .disabled(isTesting)
                        if let testResult {
                            Text(testResult).font(.footnote)
                        }
                    }
                }

                Section("隐私") {
                    Text("错题和照片只保存在本机。识别时会把试卷照片发送给所选的模型服务；拍照前建议遮住姓名、学校等信息。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .onChange(of: memberToken) { _, value in KeychainStore.set(value, for: SettingsKey.memberToken) }
            .onChange(of: apiKey) { _, value in KeychainStore.set(value, for: SettingsKey.apiKey) }
            .onChange(of: mode) { _, _ in testResult = nil }
        }
    }

    private var modeFooter: String {
        switch mode {
        case .member: "由我们提供识别服务，拍照后自动找出错题并生成答案。"
        case .ownKey: "使用你自己的模型服务和 API key，App 直接连接服务商。模型必须支持图片输入。"
        case .manual: "不联网。需要手动框选错题，题目文字用本机识别，不生成答案。"
        }
    }

    private var memberSection: some View {
        Section {
            TextField("服务地址，如 http://192.168.1.5:8000", text: $serverURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("会员凭证", text: $memberToken)
        } header: {
            Text("会员服务")
        } footer: {
            Text("开发阶段：在 Mac 上启动 server/ 中转服务，填 Mac 的局域网地址和 NOTBAD_MEMBER_TOKENS 里的凭证。")
        }
    }

    private var ownKeySection: some View {
        Section {
            Picker("服务商", selection: $presetID) {
                ForEach(ProviderPreset.all) { Text($0.name).tag($0.id) }
                Text("自定义").tag(Self.customPresetID)
            }
            .onChange(of: presetID) { _, id in
                guard let preset = ProviderPreset.all.first(where: { $0.id == id }) else { return }
                endpoint = preset.endpoint
                apiStyle = preset.apiStyle
            }
            if presetID == Self.customPresetID {
                TextField("接口地址（完整 URL）", text: $endpoint)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Picker("接口格式", selection: $apiStyle) {
                    ForEach(APIStyle.allCases) { Text($0.title).tag($0) }
                }
            }
            SecureField("API key", text: $apiKey)
            TextField("识别模型，如 kimi-k3", text: $analyzeModel)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("解题模型（可选，默认同上）", text: $solveModel)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text("自备 API key")
        } footer: {
            Text("API key 只保存在本机钥匙串里。两个模型都需要能看图；解题可以选推理更强的模型。")
        }
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        Task {
            defer { isTesting = false }
            switch mode {
            case .member:
                guard let service = ServiceProvider.memberService() else {
                    testResult = "请先填写服务地址和会员凭证"
                    return
                }
                do {
                    let quota = try await service.quota()
                    testResult = "连接成功，今日剩余 \(quota.remaining)/\(quota.dailyLimit) 次"
                } catch {
                    testResult = "连接失败：\(error.localizedDescription)"
                }
            case .ownKey:
                guard let service = ServiceProvider.current() as? DirectLLMService else {
                    testResult = "请先填写接口地址、API key 和识别模型"
                    return
                }
                testResult = await Self.probe(service)
            case .manual:
                break
            }
        }
    }

    /// 画一个红色圆形让模型描述，确认模型真的能看图。
    private static func probe(_ service: DirectLLMService) async -> String {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200)).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
            UIColor.red.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 50, y: 50, width: 100, height: 100))
        }
        guard let jpeg = image.jpegData(compressionQuality: 0.8) else { return "生成测试图片失败" }
        do {
            let answer = try await service.ask(jpeg: jpeg, user: Prompts.probeUser, maxTokens: 100)
            if answer.contains("红") {
                return "连接成功，模型能看图（回答：\(answer.prefix(30))）"
            }
            return "连接成功，但模型可能不支持图片（回答：\(answer.prefix(30))），请换一个模型"
        } catch {
            return "连接失败：\(error.localizedDescription)"
        }
    }
}
