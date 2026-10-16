import Foundation
import NotBadCore
import SwiftData

/// 一次拍摄/导入的试卷，可包含多页。
@Model
final class Paper {
    var id: UUID
    var createdAt: Date
    var subjectRaw: String
    var title: String
    /// 每页原图在 ImageStore 中的文件名
    var pageFileNames: [String]

    @Relationship(deleteRule: .cascade, inverse: \Mistake.paper)
    var mistakes: [Mistake] = []

    init(subject: Subject, title: String, pageFileNames: [String], createdAt: Date = .now) {
        self.id = UUID()
        self.createdAt = createdAt
        self.subjectRaw = subject.rawValue
        self.title = title
        self.pageFileNames = pageFileNames
    }

    var subject: Subject {
        get { Subject(rawValue: subjectRaw) ?? .other }
        set { subjectRaw = newValue.rawValue }
    }
}

/// 一道错题。
@Model
final class Mistake {
    var id: UUID
    var createdAt: Date
    var subjectRaw: String
    var questionNumber: String
    /// 裁剪后的题目图片
    var cropFileName: String
    /// 来自哪一页原图，以及在原图中的位置（0-1000 归一化）
    var pageFileName: String?
    var boxX0: Double = 0
    var boxY0: Double = 0
    var boxX1: Double = 0
    var boxY1: Double = 0

    /// OCR 或模型识别出的题干，可手动修改
    var recognizedText: String = ""
    var studentAnswer: String = ""
    var correctAnswer: String = ""
    var note: String = ""
    var causeRaws: [String] = []
    var sourceRaw: String
    var confidence: Double = 1

    // 复习进度（ReviewState 拆成平铺字段，方便 SwiftData 排序和查询）
    var reviewDue: Date
    var reviewIntervalDays: Int = 0
    var reviewEase: Double = ReviewScheduler.defaultEase
    var reviewRepetitions: Int = 0
    var reviewLapses: Int = 0

    var paper: Paper?

    @Relationship(deleteRule: .cascade, inverse: \ReviewLog.mistake)
    var logs: [ReviewLog] = []

    init(subject: Subject, questionNumber: String, cropFileName: String,
         pageFileName: String?, box: NormalizedBox?, source: MistakeSource,
         scheduler: ReviewScheduler = ReviewScheduler(), createdAt: Date = .now) {
        self.id = UUID()
        self.createdAt = createdAt
        self.subjectRaw = subject.rawValue
        self.questionNumber = questionNumber
        self.cropFileName = cropFileName
        self.pageFileName = pageFileName
        self.sourceRaw = source.rawValue
        self.reviewDue = scheduler.initialState(createdAt: createdAt).due
        if let box {
            self.boxX0 = box.x0
            self.boxY0 = box.y0
            self.boxX1 = box.x1
            self.boxY1 = box.y1
        }
    }

    var subject: Subject {
        get { Subject(rawValue: subjectRaw) ?? .other }
        set { subjectRaw = newValue.rawValue }
    }

    var source: MistakeSource { MistakeSource(rawValue: sourceRaw) ?? .manual }

    var causes: Set<MistakeCause> {
        get { Set(causeRaws.compactMap(MistakeCause.init(rawValue:))) }
        set { causeRaws = MistakeCause.allCases.filter(newValue.contains).map(\.rawValue) }
    }

    var box: NormalizedBox {
        get { NormalizedBox(x0: boxX0, y0: boxY0, x1: boxX1, y1: boxY1) }
        set { (boxX0, boxY0, boxX1, boxY1) = (newValue.x0, newValue.y0, newValue.x1, newValue.y1) }
    }

    var reviewState: ReviewState {
        get {
            ReviewState(intervalDays: reviewIntervalDays, ease: reviewEase,
                        repetitions: reviewRepetitions, lapses: reviewLapses, due: reviewDue)
        }
        set {
            reviewIntervalDays = newValue.intervalDays
            reviewEase = newValue.ease
            reviewRepetitions = newValue.repetitions
            reviewLapses = newValue.lapses
            reviewDue = newValue.due
        }
    }
}

/// 一次复习记录。
@Model
final class ReviewLog {
    var date: Date
    var gradeRaw: String
    var mistake: Mistake?

    init(grade: ReviewGrade, date: Date = .now) {
        self.date = date
        self.gradeRaw = grade.rawValue
    }

    var grade: ReviewGrade { ReviewGrade(rawValue: gradeRaw) ?? .forgot }
}
