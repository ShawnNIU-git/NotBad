import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import NotBadCore

/// 记录请求并返回预设回复的假网络层。
final class FakeTransport: HTTPTransport, @unchecked Sendable {
    var requests: [URLRequest] = []
    var status = 200
    var body: Data

    init(json: Any, status: Int = 200) {
        self.body = try! JSONSerialization.data(withJSONObject: json)
        self.status = status
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (body, response)
    }

    var lastJSON: [String: Any] {
        try! JSONSerialization.jsonObject(with: requests.last!.httpBody!) as! [String: Any]
    }
}

let pageJSON = """
{"subject": "数学", "title": "第三单元测试", "paper_type": "单元测试", "grade": null,
 "questions": [{"number": "1", "bbox": [0, 0, 500, 200], "is_wrong": true, "knowledge_points": ["乘法"]}]}
"""

final class PromptTests: XCTestCase {
    func testBundledPromptsLoad() {
        XCTAssertTrue(Prompts.analyzeSystem.contains("bbox"))
        XCTAssertTrue(Prompts.analyzeSystem.contains("paper_type"))
        XCTAssertTrue(Prompts.solveSystem.contains("common_mistake"))
    }

    func testSolveUserMatchesPythonFormat() {
        XCTAssertEqual(Prompts.solveUser(text: "3+4×2=", subject: "数学", studentAnswer: "14"),
                       "学科：数学\n识别出的题干：3+4×2=\n学生的错误答案：14\n请按要求输出 JSON。")
        XCTAssertEqual(Prompts.solveUser(text: ""), "识别出的题干：（未识别，请看图片）\n请按要求输出 JSON。")
    }
}

final class ParsingExtensionTests: XCTestCase {
    func testPageInfoAndKnowledgePoints() throws {
        let page = try RecognitionParser.parsePage(from: pageJSON)
        XCTAssertEqual(page.title, "第三单元测试")
        XCTAssertEqual(page.paperType, "单元测试")
        XCTAssertEqual(page.grade, "")
        XCTAssertEqual(page.questions[0].knowledgePoints, ["乘法"])
    }

    func testSolutionIsLenient() throws {
        let s = try RecognitionParser.parseSolution(from: """
        ```json
        {"answer": "11", "explanation": "先乘后加", "knowledge_points": "运算顺序", "confidence": 0.9}
        ```
        """)
        XCTAssertEqual(s.answer, "11")
        XCTAssertEqual(s.knowledgePoints, [])
        XCTAssertEqual(s.commonMistake, "")
        XCTAssertEqual(s.confidence, 0.9)
    }
}

final class DirectLLMServiceTests: XCTestCase {
    func config(_ style: APIStyle) -> DirectLLMConfig {
        DirectLLMConfig(endpoint: URL(string: "https://example.com/v1/chat")!, apiStyle: style,
                        apiKey: "k", analyzeModel: "vision", solveModel: "solver")
    }

    func testOpenAIAnalyze() async throws {
        let fake = FakeTransport(json: ["choices": [["message": ["content": "```json\n\(pageJSON)\n```"]]]])
        let page = try await DirectLLMService(config: config(.openai), transport: fake).analyzePage(jpeg: Data([1, 2, 3]))

        XCTAssertEqual(page.title, "第三单元测试")
        let request = fake.requests[0]
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer k")
        let body = fake.lastJSON
        XCTAssertEqual(body["model"] as? String, "vision")
        let messages = body["messages"] as! [[String: Any]]
        XCTAssertEqual(messages[0]["role"] as? String, "system")
        let content = messages[1]["content"] as! [[String: Any]]
        let url = (content[0]["image_url"] as! [String: Any])["url"] as! String
        XCTAssertEqual(url, "data:image/jpeg;base64,AQID")
    }

    func testAnthropicSolveUsesSolveModel() async throws {
        let fake = FakeTransport(json: ["content": [["type": "text", "text": "{\"answer\": \"11\"}"]]])
        let service = DirectLLMService(config: config(.anthropic), transport: fake)
        let solution = try await service.solve(questionJPEG: Data([1]), text: "3+4×2=", subject: "数学", studentAnswer: "14")

        XCTAssertEqual(solution.answer, "11")
        XCTAssertEqual(fake.requests[0].value(forHTTPHeaderField: "x-api-key"), "k")
        let body = fake.lastJSON
        XCTAssertEqual(body["model"] as? String, "solver")
        XCTAssertTrue((body["system"] as? String)?.contains("标准答案") == true)
        let content = (body["messages"] as! [[String: Any]])[0]["content"] as! [[String: Any]]
        XCTAssertEqual(content[0]["type"] as? String, "image")
        XCTAssertTrue((content[1]["text"] as? String)?.contains("14") == true)
    }

    func testSolveModelFallsBackToAnalyzeModel() {
        var c = config(.openai)
        c.solveModel = ""
        XCTAssertEqual(c.effectiveSolveModel, "vision")
    }

    func testErrorsAreMapped() async {
        let unauthorized = FakeTransport(json: ["error": "bad key"], status: 401)
        do {
            _ = try await DirectLLMService(config: config(.openai), transport: unauthorized).analyzePage(jpeg: Data())
            XCTFail("应该抛错")
        } catch {
            XCTAssertEqual(error as? RecognitionError, .unauthorized)
        }

        let garbage = FakeTransport(json: ["choices": [["message": ["content": "看不清"]]]])
        do {
            _ = try await DirectLLMService(config: config(.openai), transport: garbage).analyzePage(jpeg: Data())
            XCTFail("应该抛错")
        } catch {
            guard case .invalidResponse = error as? RecognitionError else { return XCTFail("\(error)") }
        }

        var empty = config(.openai)
        empty.apiKey = ""
        do {
            _ = try await DirectLLMService(config: empty, transport: garbage).analyzePage(jpeg: Data())
            XCTFail("应该抛错")
        } catch {
            XCTAssertEqual(error as? RecognitionError, .notConfigured)
        }
    }
}

final class CloudServiceTests: XCTestCase {
    let base = URL(string: "http://192.168.1.5:8000")!

    func testAnalyzeSendsMultipartWithToken() async throws {
        let fake = FakeTransport(json: try JSONSerialization.jsonObject(with: Data(pageJSON.utf8)))
        let page = try await CloudService(baseURL: base, token: "t1", transport: fake).analyzePage(jpeg: Data("JPEG".utf8))

        XCTAssertEqual(page.questions.count, 1)
        let request = fake.requests[0]
        XCTAssertEqual(request.url?.absoluteString, "http://192.168.1.5:8000/v1/pages/analyze")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer t1")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")!.hasPrefix("multipart/form-data; boundary="))
        let body = String(decoding: request.httpBody!, as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"image\"; filename=\"page.jpg\""))
        XCTAssertTrue(body.contains("JPEG"))
    }

    func testSolveSendsFields() async throws {
        let fake = FakeTransport(json: ["answer": "11", "explanation": "先乘后加", "confidence": 0.9])
        let solution = try await CloudService(baseURL: base, token: "t1", transport: fake)
            .solve(questionJPEG: Data([1]), text: "3+4×2=", subject: "数学", studentAnswer: "14")
        XCTAssertEqual(solution.answer, "11")
        let body = String(decoding: fake.requests[0].httpBody!, as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"text\"\r\n\r\n3+4×2=\r\n"))
        XCTAssertTrue(body.contains("name=\"student_answer\"\r\n\r\n14\r\n"))
    }

    func testQuotaAndErrors() async throws {
        let fake = FakeTransport(json: ["daily_limit": 200, "used_today": 3, "remaining": 197])
        let quota = try await CloudService(baseURL: base, token: "t1", transport: fake).quota()
        XCTAssertEqual(quota, CloudService.Quota(dailyLimit: 200, usedToday: 3, remaining: 197))

        let exhausted = FakeTransport(json: ["detail": "今日额度已用完"], status: 402)
        do {
            _ = try await CloudService(baseURL: base, token: "t1", transport: exhausted).analyzePage(jpeg: Data())
            XCTFail("应该抛错")
        } catch {
            XCTAssertEqual(error as? RecognitionError, .quotaExceeded)
        }

        let upstream = FakeTransport(json: ["detail": "模型服务暂时不可用"], status: 502)
        do {
            _ = try await CloudService(baseURL: base, token: "t1", transport: upstream).analyzePage(jpeg: Data())
            XCTFail("应该抛错")
        } catch {
            XCTAssertEqual(error as? RecognitionError, .http(status: 502, message: "模型服务暂时不可用"))
        }
    }
}
