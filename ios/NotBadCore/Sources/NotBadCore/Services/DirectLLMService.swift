import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 模型接口格式。
public enum APIStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    case openai     // OpenAI Chat Completions 兼容格式（多数国内服务商都支持）
    case anthropic  // Anthropic Messages 格式

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .openai: "OpenAI 兼容"
        case .anthropic: "Anthropic"
        }
    }
}

/// 自备 key 模式的配置。
public struct DirectLLMConfig: Equatable, Sendable {
    /// 完整接口地址，如 https://opencode.ai/inference/go/openai/v1/chat/completions
    public var endpoint: URL
    public var apiStyle: APIStyle
    public var apiKey: String
    public var analyzeModel: String
    /// 为空时用 analyzeModel。解题输入也带图片，所以同样需要能看图的模型。
    public var solveModel: String

    public init(endpoint: URL, apiStyle: APIStyle, apiKey: String, analyzeModel: String, solveModel: String = "") {
        self.endpoint = endpoint
        self.apiStyle = apiStyle
        self.apiKey = apiKey
        self.analyzeModel = analyzeModel
        self.solveModel = solveModel
    }

    public var effectiveSolveModel: String { solveModel.isEmpty ? analyzeModel : solveModel }
}

/// 常见服务商的接口预设，方便用户在设置里直接选。
public struct ProviderPreset: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let endpoint: String
    public let apiStyle: APIStyle

    public static let all: [ProviderPreset] = [
        ProviderPreset(id: "opencode-go", name: "OpenCode Go（OpenAI 格式）",
                       endpoint: "https://opencode.ai/inference/go/openai/v1/chat/completions", apiStyle: .openai),
        ProviderPreset(id: "opencode-go-anthropic", name: "OpenCode Go（Anthropic 格式）",
                       endpoint: "https://opencode.ai/inference/go/anthropic/v1/messages", apiStyle: .anthropic),
        ProviderPreset(id: "dashscope", name: "阿里云百炼",
                       endpoint: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions", apiStyle: .openai),
        ProviderPreset(id: "zhipu", name: "智谱 BigModel",
                       endpoint: "https://open.bigmodel.cn/api/paas/v4/chat/completions", apiStyle: .openai),
        ProviderPreset(id: "anthropic", name: "Anthropic",
                       endpoint: "https://api.anthropic.com/v1/messages", apiStyle: .anthropic),
        ProviderPreset(id: "openai", name: "OpenAI",
                       endpoint: "https://api.openai.com/v1/chat/completions", apiStyle: .openai),
    ]
}

/// App 直连服务商。请求格式与 recognition/notbad_recog/client.py 一致。
public struct DirectLLMService: RecognitionService {
    public let config: DirectLLMConfig
    let transport: HTTPTransport

    public init(config: DirectLLMConfig, transport: HTTPTransport = URLSessionTransport()) {
        self.config = config
        self.transport = transport
    }

    public func analyzePage(jpeg: Data) async throws -> RecognizedPage {
        let text = try await ask(jpeg: jpeg, user: Prompts.analyzeUser, system: Prompts.analyzeSystem,
                                 model: config.analyzeModel, maxTokens: 8192)
        do {
            return try RecognitionParser.parsePage(from: text)
        } catch {
            throw RecognitionError.invalidResponse(String(text.prefix(200)))
        }
    }

    public func solve(questionJPEG: Data, text: String, subject: String, studentAnswer: String) async throws -> Solution {
        let user = Prompts.solveUser(text: text, subject: subject, studentAnswer: studentAnswer)
        let reply = try await ask(jpeg: questionJPEG, user: user, system: Prompts.solveSystem,
                                  model: config.effectiveSolveModel, maxTokens: 4096)
        do {
            return try RecognitionParser.parseSolution(from: reply)
        } catch {
            throw RecognitionError.invalidResponse(String(reply.prefix(200)))
        }
    }

    /// 发一张图和一段文字，返回模型的文本回复。设置页的"测试连接"也用它。
    public func ask(jpeg: Data, user: String, system: String = "", model: String? = nil,
                    maxTokens: Int = 1024) async throws -> String {
        guard !config.apiKey.isEmpty, !config.analyzeModel.isEmpty else { throw RecognitionError.notConfigured }
        let request = try makeRequest(jpeg: jpeg, user: user, system: system,
                                      model: model ?? config.analyzeModel, maxTokens: maxTokens)
        let (data, response) = try await transport.send(request)
        try checkStatus(response, data: data)
        return try Self.extractText(style: config.apiStyle, data: data)
    }

    func makeRequest(jpeg: Data, user: String, system: String, model: String, maxTokens: Int) throws -> URLRequest {
        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("notbad-ios/0.1", forHTTPHeaderField: "User-Agent")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "x-opencode-session")
        switch config.apiStyle {
        case .anthropic:
            request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .openai:
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: Self.payload(
            style: config.apiStyle, system: system, user: user,
            imageBase64: jpeg.base64EncodedString(), model: model, maxTokens: maxTokens))
        return request
    }

    static func payload(style: APIStyle, system: String, user: String, imageBase64: String,
                        model: String, maxTokens: Int) -> [String: Any] {
        switch style {
        case .anthropic:
            var body: [String: Any] = [
                "model": model,
                "max_tokens": maxTokens,
                "messages": [[
                    "role": "user",
                    "content": [
                        ["type": "image",
                         "source": ["type": "base64", "media_type": "image/jpeg", "data": imageBase64]],
                        ["type": "text", "text": user],
                    ],
                ]],
            ]
            if !system.isEmpty { body["system"] = system }
            return body
        case .openai:
            var messages: [[String: Any]] = []
            if !system.isEmpty { messages.append(["role": "system", "content": system]) }
            messages.append([
                "role": "user",
                "content": [
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(imageBase64)"]],
                    ["type": "text", "text": user],
                ],
            ])
            return ["model": model, "max_tokens": maxTokens, "temperature": 0, "messages": messages]
        }
    }

    static func extractText(style: APIStyle, data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RecognitionError.invalidResponse("回复不是 JSON")
        }
        switch style {
        case .anthropic:
            let blocks = json["content"] as? [[String: Any]] ?? []
            return blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
        case .openai:
            guard let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any] else {
                throw RecognitionError.invalidResponse("缺少 choices")
            }
            if let text = message["content"] as? String { return text }
            // 部分服务商返回分段内容
            let parts = message["content"] as? [[String: Any]] ?? []
            return parts.compactMap { $0["text"] as? String }.joined()
        }
    }
}
