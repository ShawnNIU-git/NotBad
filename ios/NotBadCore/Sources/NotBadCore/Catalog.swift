import Foundation

/// 学科。MVP 先聚焦数学，其他学科只做归档。
public enum Subject: String, Codable, Sendable, CaseIterable, Identifiable {
    case math, chinese, english, physics, chemistry, other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .math: "数学"
        case .chinese: "语文"
        case .english: "英语"
        case .physics: "物理"
        case .chemistry: "化学"
        case .other: "其他"
        }
    }

    /// 识别模型返回的是中文学科名。
    public init(title: String) {
        self = Subject.allCases.first { $0.title == title } ?? .other
    }
}

/// 错因标签。
public enum MistakeCause: String, Codable, Sendable, CaseIterable, Identifiable {
    case concept, calculation, misread, careless, method, time

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .concept: "概念不清"
        case .calculation: "计算错误"
        case .misread: "审题不清"
        case .careless: "粗心"
        case .method: "方法不会"
        case .time: "时间不够"
        }
    }
}

/// 错题来源。
public enum MistakeSource: String, Codable, Sendable {
    case manual        // 学生手动框选
    case teacherMark   // 识别老师批改痕迹
    case aiGraded      // AI 判题
}
