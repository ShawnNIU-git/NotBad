import Foundation

/// 老师批改痕迹。
public enum TeacherMark: String, Codable, Sendable, CaseIterable {
    case correct, wrong, partial, none

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self).lowercased()
        self = TeacherMark(rawValue: raw) ?? .none
    }
}

/// 识别出的一道题。字段与识别原型的 JSON 格式（recognition/notbad_recog/schema.py）一致。
public struct RecognizedQuestion: Codable, Equatable, Sendable {
    public var number: String
    public var bbox: NormalizedBox
    public var text: String
    public var hasFigure: Bool
    public var studentAnswer: String
    public var teacherMark: TeacherMark
    public var isWrong: Bool
    public var confidence: Double
    public var knowledgePoints: [String]

    public init(number: String, bbox: NormalizedBox, text: String = "", hasFigure: Bool = false,
                studentAnswer: String = "", teacherMark: TeacherMark = .none,
                isWrong: Bool = false, confidence: Double = 0, knowledgePoints: [String] = []) {
        self.number = number
        self.bbox = bbox
        self.text = text
        self.hasFigure = hasFigure
        self.studentAnswer = studentAnswer
        self.teacherMark = teacherMark
        self.isWrong = isWrong
        self.confidence = confidence
        self.knowledgePoints = knowledgePoints
    }

    enum CodingKeys: String, CodingKey {
        case number, bbox, text
        case hasFigure = "has_figure"
        case studentAnswer = "student_answer"
        case teacherMark = "teacher_mark"
        case isWrong = "is_wrong"
        case confidence
        case knowledgePoints = "knowledge_points"
    }

    // 模型输出常缺字段，缺了就用默认值
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let number: String
        if let s = try? c.decode(String.self, forKey: .number) {
            number = s
        } else if let n = try? c.decode(Int.self, forKey: .number) {
            number = String(n)
        } else {
            number = ""
        }
        self.init(
            number: number.trimmingCharacters(in: .whitespaces),
            bbox: try c.decodeIfPresent(NormalizedBox.self, forKey: .bbox) ?? NormalizedBox(x0: 0, y0: 0, x1: 0, y1: 0),
            text: try c.decodeIfPresent(String.self, forKey: .text) ?? "",
            hasFigure: try c.decodeIfPresent(Bool.self, forKey: .hasFigure) ?? false,
            studentAnswer: try c.decodeIfPresent(String.self, forKey: .studentAnswer) ?? "",
            teacherMark: try c.decodeIfPresent(TeacherMark.self, forKey: .teacherMark) ?? .none,
            isWrong: try c.decodeIfPresent(Bool.self, forKey: .isWrong) ?? false,
            confidence: try c.decodeIfPresent(Double.self, forKey: .confidence) ?? 0,
            knowledgePoints: decodeStringList(c, .knowledgePoints)
        )
    }
}

/// 模型偶尔把列表写成字符串或混入数字，宽松解析，取不到就返回空。
func decodeStringList<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> [String] {
    if let list = try? c.decodeIfPresent([String].self, forKey: key) {
        return list.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    return []
}

/// 一页试卷的识别结果。
public struct RecognizedPage: Codable, Equatable, Sendable {
    public var subject: String
    /// 试卷标题，识别不到为空
    public var title: String
    /// 单元测试/期中/期末/作业/练习/其他
    public var paperType: String
    public var grade: String
    public var questions: [RecognizedQuestion]
    public var notes: String

    public init(subject: String = "", title: String = "", paperType: String = "", grade: String = "",
                questions: [RecognizedQuestion] = [], notes: String = "") {
        self.subject = subject
        self.title = title
        self.paperType = paperType
        self.grade = grade
        self.questions = questions
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case subject, title, grade, questions, notes
        case paperType = "paper_type"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func string(_ key: CodingKeys) -> String {
            ((try? c.decodeIfPresent(String.self, forKey: key)) ?? nil)?.trimmingCharacters(in: .whitespaces) ?? ""
        }
        self.init(
            subject: string(.subject),
            title: string(.title),
            paperType: string(.paperType),
            grade: string(.grade),
            questions: try c.decodeIfPresent([RecognizedQuestion].self, forKey: .questions) ?? [],
            notes: string(.notes)
        )
    }

    public var wrongQuestions: [RecognizedQuestion] { questions.filter(\.isWrong) }
}

/// 一道题的标准答案与解析。字段与 recognition/notbad_recog/schema.py 的 Solution 一致。
public struct Solution: Codable, Equatable, Sendable {
    public var answer: String
    public var explanation: String
    public var knowledgePoints: [String]
    public var commonMistake: String
    public var confidence: Double

    public init(answer: String = "", explanation: String = "", knowledgePoints: [String] = [],
                commonMistake: String = "", confidence: Double = 0) {
        self.answer = answer
        self.explanation = explanation
        self.knowledgePoints = knowledgePoints
        self.commonMistake = commonMistake
        self.confidence = confidence
    }

    enum CodingKeys: String, CodingKey {
        case answer, explanation, confidence
        case knowledgePoints = "knowledge_points"
        case commonMistake = "common_mistake"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            answer: (try? c.decodeIfPresent(String.self, forKey: .answer) ?? "") ?? "",
            explanation: (try? c.decodeIfPresent(String.self, forKey: .explanation) ?? "") ?? "",
            knowledgePoints: decodeStringList(c, .knowledgePoints),
            commonMistake: (try? c.decodeIfPresent(String.self, forKey: .commonMistake) ?? "") ?? "",
            confidence: (try? c.decodeIfPresent(Double.self, forKey: .confidence) ?? 0) ?? 0
        )
    }
}

public enum RecognitionParseError: Error, Equatable {
    case noJSONObject
}

public enum RecognitionParser {
    /// 从模型回复中取出 JSON 对象，兼容 ```json 代码块和前后多余文字。
    public static func extractJSON(from text: String) throws -> Data {
        var body = Substring(text)
        if let fenceStart = body.range(of: "```") {
            var rest = body[fenceStart.upperBound...]
            if rest.hasPrefix("json") { rest = rest.dropFirst(4) }
            if let fenceEnd = rest.range(of: "```") {
                body = rest[..<fenceEnd.lowerBound]
            }
        }
        guard let start = body.firstIndex(of: "{"),
              let end = body.lastIndex(of: "}"),
              start < end else {
            throw RecognitionParseError.noJSONObject
        }
        return Data(body[start...end].utf8)
    }

    public static func parsePage(from text: String) throws -> RecognizedPage {
        try JSONDecoder().decode(RecognizedPage.self, from: extractJSON(from: text))
    }

    public static func parseSolution(from text: String) throws -> Solution {
        try JSONDecoder().decode(Solution.self, from: extractJSON(from: text))
    }
}
