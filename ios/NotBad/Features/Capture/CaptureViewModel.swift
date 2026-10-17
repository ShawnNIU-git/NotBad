import NotBadCore
import SwiftData
import SwiftUI

/// 确认页上的一个题目框：模型识别出来的，或用户手动画的。
struct DraftBox: Identifiable, Equatable {
    let id = UUID()
    var box: NormalizedBox
    /// 是否作为错题保存
    var isSelected: Bool
    /// 模型识别结果；手动画的框为 nil
    var question: RecognizedQuestion?

    var isManual: Bool { question == nil }
    /// 模型判为错题但把握不大，界面上提示用户确认
    var needsReview: Bool { (question?.isWrong ?? false) && (question?.confidence ?? 1) < 0.6 }
}

/// 一页试卷的处理状态。
struct PageDraft: Identifiable {
    enum Status: Equatable {
        case analyzing
        case done
        case failed(String)
        case manual  // 未配置识别服务
    }

    let id = UUID()
    let image: UIImage
    var status: Status
    var boxes: [DraftBox] = []
}

@MainActor
@Observable
final class CaptureViewModel {
    var pages: [PageDraft] = []
    var currentPage = 0

    // 试卷信息：自动识别填入，用户可改
    var subject: Subject = .math
    var title = ""
    var paperType = ""
    var grade = ""
    /// 追加到哪份已有试卷；nil 表示新建
    var targetPaper: Paper?
    private var paperInfoEdited = false

    private let service: RecognitionService?

    init(service: RecognitionService? = ServiceProvider.current(), targetPaper: Paper? = nil) {
        self.service = service
        self.targetPaper = targetPaper
        if let targetPaper {
            subject = targetPaper.subject
            title = targetPaper.title
            paperType = targetPaper.paperType
            grade = targetPaper.grade
            paperInfoEdited = true
        }
    }

    var usesModel: Bool { service != nil }
    var isAnalyzing: Bool { pages.contains { $0.status == .analyzing } }
    var selectedCount: Int { pages.reduce(0) { $0 + $1.boxes.filter(\.isSelected).count } }

    func markPaperInfoEdited() { paperInfoEdited = true }

    /// 用户在"保存到"里选了一份已有试卷：沿用那份试卷的信息。
    func targetPaperChanged() {
        guard let paper = targetPaper else { return }
        subject = paper.subject
        title = paper.title
        paperType = paper.paperType
        grade = paper.grade
        paperInfoEdited = true
    }

    func addPages(_ images: [UIImage]) {
        let start = pages.count
        for image in images {
            pages.append(PageDraft(image: image.normalizedForStorage(), status: usesModel ? .analyzing : .manual))
        }
        if pages.count > start { currentPage = start }
        for index in start..<pages.count { analyze(pageAt: index) }
    }

    func retry(pageAt index: Int) {
        pages[index].status = .analyzing
        analyze(pageAt: index)
    }

    private func analyze(pageAt index: Int) {
        guard let service else { return }
        let id = pages[index].id
        guard let jpeg = pages[index].image.jpegForUpload() else {
            pages[index].status = .failed("图片处理失败")
            return
        }
        Task {
            do {
                let result = try await service.analyzePage(jpeg: jpeg)
                apply(result, toPage: id)
            } catch {
                if let i = pages.firstIndex(where: { $0.id == id }) {
                    pages[i].status = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func apply(_ result: RecognizedPage, toPage id: UUID) {
        guard let i = pages.firstIndex(where: { $0.id == id }) else { return }
        let detected = result.questions
            .filter { $0.bbox.isUsable(minSide: 5) }
            .map { DraftBox(box: $0.bbox, isSelected: $0.isWrong, question: $0) }
        // 保留用户在识别完成前手动画的框
        pages[i].boxes = detected + pages[i].boxes.filter(\.isManual)
        pages[i].status = .done

        // 用第一页识别到的信息填试卷信息；用户改过或追加到已有试卷时不覆盖
        guard !paperInfoEdited else { return }
        if !result.subject.isEmpty { subject = Subject(title: result.subject) }
        if title.isEmpty { title = result.title }
        if paperType.isEmpty { paperType = result.paperType }
        if grade.isEmpty { grade = result.grade }
    }

    /// 保存试卷和选中的错题，返回新建的错题（用于后续识别文字和生成答案）。
    func save(context: ModelContext) throws -> [(Mistake, UIImage)] {
        let pageFiles = try pages.map { try ImageStore.save($0.image) }
        let paper: Paper
        if let targetPaper {
            paper = targetPaper
            paper.pageFileNames.append(contentsOf: pageFiles)
        } else {
            paper = Paper(subject: subject, title: title.trimmingCharacters(in: .whitespaces), pageFileNames: pageFiles)
            context.insert(paper)
        }
        paper.subject = subject
        paper.title = title.trimmingCharacters(in: .whitespaces)
        paper.paperType = paperType
        paper.grade = grade

        var created: [(Mistake, UIImage)] = []
        var manualNumber = paper.mistakes.count
        for (pageIndex, page) in pages.enumerated() {
            for draft in page.boxes where draft.isSelected {
                guard let crop = page.image.cropped(to: draft.box) else { continue }
                let question = draft.question
                manualNumber += 1
                let mistake = Mistake(
                    subject: subject,
                    questionNumber: question?.number.isEmpty == false ? question!.number : "\(manualNumber)",
                    cropFileName: try ImageStore.save(crop),
                    pageFileName: pageFiles[pageIndex],
                    box: draft.box,
                    source: question.map(MistakeSource.init(question:)) ?? .manual
                )
                if let question {
                    mistake.recognizedText = question.text
                    mistake.studentAnswer = question.studentAnswer
                    mistake.teacherMarkRaw = question.teacherMark.rawValue
                    mistake.confidence = question.confidence
                    mistake.knowledgePoints = question.knowledgePoints
                }
                mistake.answerStatus = usesModel ? .pending : .none
                context.insert(mistake)
                mistake.paper = paper
                created.append((mistake, crop))
            }
        }
        try context.save()
        return created
    }
}
