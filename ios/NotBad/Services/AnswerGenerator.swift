import NotBadCore
import SwiftData
import UIKit

/// 在后台为错题生成标准答案。
/// 保存错题后、App 启动时、回到前台时都会调用 run()；状态存在 Mistake 上，中途退出也不会丢。
@MainActor
final class AnswerGenerator {
    static let shared = AnswerGenerator()

    private var isRunning = false
    private let maxConcurrent = 2

    /// 处理所有排队中的错题。重复调用是安全的。
    func run(context: ModelContext) {
        guard !isRunning, let service = ServiceProvider.current() else { return }
        isRunning = true
        Task {
            defer { isRunning = false }
            // 上次被打断、停在"生成中"的，重新排队
            for mistake in fetch(.generating, context: context) { mistake.answerStatus = .pending }

            while true {
                let batch = Array(fetch(.pending, context: context).prefix(maxConcurrent))
                if batch.isEmpty { break }
                await withTaskGroup(of: Void.self) { group in
                    for mistake in batch {
                        mistake.answerStatus = .generating
                        group.addTask { await self.generate(for: mistake, service: service) }
                    }
                }
                try? context.save()
            }
        }
    }

    /// 重新生成一道题（详情页的"重新生成"按钮）。
    func regenerate(_ mistake: Mistake, context: ModelContext) {
        mistake.answerStatus = .pending
        mistake.answerError = ""
        run(context: context)
    }

    private func generate(for mistake: Mistake, service: RecognitionService) async {
        guard let image = ImageStore.load(mistake.cropFileName),
              let jpeg = image.jpegForUpload(maxSide: 1600) else {
            mistake.answerStatus = .failed
            mistake.answerError = "找不到题目图片"
            return
        }
        do {
            let solution = try await service.solve(questionJPEG: jpeg, text: mistake.recognizedText,
                                                   subject: mistake.subject.title,
                                                   studentAnswer: mistake.studentAnswer)
            mistake.apply(solution)
        } catch {
            mistake.answerStatus = .failed
            mistake.answerError = error.localizedDescription
        }
    }

    private func fetch(_ status: AnswerStatus, context: ModelContext) -> [Mistake] {
        let raw = status.rawValue
        let descriptor = FetchDescriptor<Mistake>(
            predicate: #Predicate { $0.answerStatusRaw == raw },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}
