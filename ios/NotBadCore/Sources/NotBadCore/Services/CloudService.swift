import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 会员模式：调用我们的中转后端（server/），由后端带我们的 key 转发给服务商。
public struct CloudService: RecognitionService {
    /// 后端根地址，如 http://192.168.1.5:8000
    public let baseURL: URL
    public let token: String
    let transport: HTTPTransport

    public init(baseURL: URL, token: String, transport: HTTPTransport = URLSessionTransport()) {
        self.baseURL = baseURL
        self.token = token
        self.transport = transport
    }

    public struct Quota: Codable, Equatable, Sendable {
        public var dailyLimit: Int
        public var usedToday: Int
        public var remaining: Int

        enum CodingKeys: String, CodingKey {
            case dailyLimit = "daily_limit"
            case usedToday = "used_today"
            case remaining
        }
    }

    public func analyzePage(jpeg: Data) async throws -> RecognizedPage {
        var body = MultipartBody()
        body.addFile("image", filename: "page.jpg", mimeType: "image/jpeg", data: jpeg)
        return try await post("v1/pages/analyze", body: body, as: RecognizedPage.self)
    }

    public func solve(questionJPEG: Data, text: String, subject: String, studentAnswer: String) async throws -> Solution {
        var body = MultipartBody()
        body.addFile("image", filename: "question.jpg", mimeType: "image/jpeg", data: questionJPEG)
        body.addField("text", text)
        body.addField("subject", subject)
        body.addField("student_answer", studentAnswer)
        return try await post("v1/questions/solve", body: body, as: Solution.self)
    }

    public func quota() async throws -> Quota {
        var request = authorized(URLRequest(url: baseURL.appendingPathComponent("v1/me")))
        request.timeoutInterval = 15
        return try await decode(Quota.self, from: request)
    }

    private func post<T: Decodable>(_ path: String, body: MultipartBody, as type: T.Type) async throws -> T {
        var request = authorized(URLRequest(url: baseURL.appendingPathComponent(path)))
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue(body.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = body.finalized()
        return try await decode(type, from: request)
    }

    private func authorized(_ request: URLRequest) -> URLRequest {
        var request = request
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func decode<T: Decodable>(_ type: T.Type, from request: URLRequest) async throws -> T {
        guard !token.isEmpty else { throw RecognitionError.notConfigured }
        let (data, response) = try await transport.send(request)
        try checkStatus(response, data: data)
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw RecognitionError.invalidResponse(String(decoding: data.prefix(200), as: UTF8.self))
        }
    }
}
