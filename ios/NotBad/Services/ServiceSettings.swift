import Foundation
import NotBadCore

/// 识别方式。
enum ServiceMode: String, CaseIterable, Identifiable {
    case member   // 会员服务：走我们的中转后端
    case ownKey   // 自备 API key：直连服务商
    case manual   // 不使用模型：手动框选 + 本机文字识别

    var id: String { rawValue }

    var title: String {
        switch self {
        case .member: "会员服务"
        case .ownKey: "自备 API key"
        case .manual: "不使用（手动框选）"
        }
    }
}

/// 设置项的存储位置。普通配置用 UserDefaults（视图里用 @AppStorage 读写），密钥用钥匙串。
enum SettingsKey {
    static let mode = "service.mode"
    static let serverURL = "member.serverURL"
    static let presetID = "ownKey.presetID"
    static let endpoint = "ownKey.endpoint"
    static let apiStyle = "ownKey.apiStyle"
    static let analyzeModel = "ownKey.analyzeModel"
    static let solveModel = "ownKey.solveModel"

    // 钥匙串账号
    static let memberToken = "member.token"
    static let apiKey = "ownKey.apiKey"
}

enum ServiceProvider {
    static var mode: ServiceMode {
        ServiceMode(rawValue: UserDefaults.standard.string(forKey: SettingsKey.mode) ?? "") ?? .manual
    }

    /// 当前可用的识别服务；手动模式或配置不完整时返回 nil。
    static func current() -> RecognitionService? {
        let defaults = UserDefaults.standard
        switch mode {
        case .manual:
            return nil
        case .member:
            return memberService()
        case .ownKey:
            let endpoint = defaults.string(forKey: SettingsKey.endpoint) ?? ""
            let model = defaults.string(forKey: SettingsKey.analyzeModel) ?? ""
            let key = KeychainStore.get(SettingsKey.apiKey)
            guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespaces)), url.scheme != nil,
                  !model.isEmpty, !key.isEmpty else { return nil }
            let style = APIStyle(rawValue: defaults.string(forKey: SettingsKey.apiStyle) ?? "") ?? .openai
            return DirectLLMService(config: DirectLLMConfig(
                endpoint: url, apiStyle: style, apiKey: key, analyzeModel: model,
                solveModel: defaults.string(forKey: SettingsKey.solveModel) ?? ""))
        }
    }

    static func memberService() -> CloudService? {
        let server = UserDefaults.standard.string(forKey: SettingsKey.serverURL) ?? ""
        let token = KeychainStore.get(SettingsKey.memberToken)
        guard let url = URL(string: server.trimmingCharacters(in: .whitespaces)), url.scheme != nil,
              !token.isEmpty else { return nil }
        return CloudService(baseURL: url, token: token)
    }
}
