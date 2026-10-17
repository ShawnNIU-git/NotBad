import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 识别服务：会员模式走我们的中转后端，自备 key 模式直连服务商。两者返回同样的数据。
public protocol RecognitionService: Sendable {
    /// 识别一页试卷。jpeg 为已转正、已压缩的整页图片。
    func analyzePage(jpeg: Data) async throws -> RecognizedPage
    /// 为一道题生成标准答案和解析。
    func solve(questionJPEG: Data, text: String, subject: String, studentAnswer: String) async throws -> Solution
}

public enum RecognitionError: Error, Equatable, LocalizedError {
    case notConfigured
    case unauthorized
    case quotaExceeded
    case http(status: Int, message: String)
    case invalidResponse(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured: "还没有配置识别服务，请到设置里选择会员服务或填写 API key。"
        case .unauthorized: "凭证无效：请检查会员 token 或 API key。"
        case .quotaExceeded: "今日识别额度已用完，明天再试。"
        case let .http(status, message): "服务出错（\(status)）：\(message)"
        case let .invalidResponse(detail): "模型回复无法解析：\(detail)"
        }
    }
}

/// 根据 HTTP 状态码把错误统一映射。
func checkStatus(_ response: HTTPURLResponse, data: Data) throws {
    switch response.statusCode {
    case 200..<300: return
    case 401, 403: throw RecognitionError.unauthorized
    case 402, 429: throw RecognitionError.quotaExceeded
    default:
        let body = String(decoding: data.prefix(300), as: UTF8.self)
        // FastAPI 的错误格式是 {"detail": "..."}
        let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
        throw RecognitionError.http(status: response.statusCode, message: detail ?? body)
    }
}
