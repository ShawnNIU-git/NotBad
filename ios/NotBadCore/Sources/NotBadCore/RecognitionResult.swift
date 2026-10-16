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

    public init(number: String, bbox: NormalizedBox, text: String = "", hasFigure: Bool = false,
                studentAnswer: String = "", teacherMark: TeacherMark = .none,
                isWrong: Bool = false, confidence: Double = 0) {
        self.number = number
        self.bbox = bbox
        self.text = text
        self.hasFigure = hasFigure
        self.studentAnswer = studentAnswer
        self.teacherMark = teacherMark
        self.isWrong = isWrong
        self.confidence = confidence
    }

    enum CodingKeys: String, CodingKey {
        case number, bbox, text
        case hasFigure = "has_figure"
        case studentAnswer = "student_answer"
        case teacherMark = "teacher_mark"
        case isWrong = "is_wrong"
        case confidence
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
            confidence: try c.decodeIfPresent(Double.self, forKey: .confidence) ?? 0
        )
    }
}

/// 一页试卷的识别结果。
public struct RecognizedPage: Codable, Equatable, Sendable {
    public var subject: String
    public var questions: [RecognizedQuestion]
    public var notes: String

    public init(subject: String = "", questions: [RecognizedQuestion] = [], notes: String = "") {
        self.subject = subject
        self.questions = questions
        self.notes = notes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            subject: try c.decodeIfPresent(String.self, forKey: .subject) ?? "",
            questions: try c.decodeIfPresent([RecognizedQuestion].self, forKey: .questions) ?? [],
            notes: try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        )
    }

    public var wrongQuestions: [RecognizedQuestion] { questions.filter(\.isWrong) }
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
}
