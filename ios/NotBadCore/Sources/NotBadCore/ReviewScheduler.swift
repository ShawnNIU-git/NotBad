import Foundation

/// 复习时学生的自评。
public enum ReviewGrade: String, Codable, Sendable, CaseIterable {
    case forgot      // 不会
    case fuzzy       // 模糊
    case remembered  // 会了

    public var title: String {
        switch self {
        case .forgot: "不会"
        case .fuzzy: "模糊"
        case .remembered: "会了"
        }
    }
}

/// 一道错题的复习进度。
public struct ReviewState: Codable, Equatable, Sendable {
    public var intervalDays: Int
    public var ease: Double
    /// 连续答"会了"的次数，答"不会"清零
    public var repetitions: Int
    public var lapses: Int
    public var due: Date

    public init(intervalDays: Int, ease: Double, repetitions: Int, lapses: Int, due: Date) {
        self.intervalDays = intervalDays
        self.ease = ease
        self.repetitions = repetitions
        self.lapses = lapses
        self.due = due
    }
}

/// 简化版 SM-2 间隔重复：
/// - 会了：间隔 1 天 → 3 天 → 上次间隔 × 难度系数
/// - 模糊：间隔 × 1.2，难度系数下调
/// - 不会：明天再来，难度系数下调
public struct ReviewScheduler: Sendable {
    public static let defaultEase = 2.5
    public static let minEase = 1.3
    public static let maxIntervalDays = 180
    /// 间隔达到这个天数且连续答对 3 次以上，视为已掌握
    public static let masteredIntervalDays = 30

    public var calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// 新错题当天就进入复习队列。
    public func initialState(createdAt: Date) -> ReviewState {
        ReviewState(intervalDays: 0, ease: Self.defaultEase, repetitions: 0, lapses: 0,
                    due: calendar.startOfDay(for: createdAt))
    }

    public func next(after state: ReviewState, grade: ReviewGrade, now: Date) -> ReviewState {
        var s = state
        switch grade {
        case .forgot:
            s.repetitions = 0
            s.lapses += 1
            s.ease = max(Self.minEase, s.ease - 0.2)
            s.intervalDays = 1
        case .fuzzy:
            s.ease = max(Self.minEase, s.ease - 0.15)
            s.intervalDays = max(1, Int((Double(s.intervalDays) * 1.2).rounded()))
        case .remembered:
            s.repetitions += 1
            switch s.repetitions {
            case 1: s.intervalDays = 1
            case 2: s.intervalDays = 3
            default: s.intervalDays = max(s.intervalDays + 1, Int((Double(s.intervalDays) * s.ease).rounded()))
            }
        }
        s.intervalDays = min(s.intervalDays, Self.maxIntervalDays)
        let today = calendar.startOfDay(for: now)
        s.due = calendar.date(byAdding: .day, value: s.intervalDays, to: today) ?? today
        return s
    }

    public func isDue(_ state: ReviewState, now: Date) -> Bool {
        state.due <= now
    }

    public func isMastered(_ state: ReviewState) -> Bool {
        state.repetitions >= 3 && state.intervalDays >= Self.masteredIntervalDays
    }
}
