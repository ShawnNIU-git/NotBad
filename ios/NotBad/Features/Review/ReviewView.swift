import NotBadCore
import SwiftData
import SwiftUI

/// 今日复习：逐题回忆，自评"不会 / 模糊 / 会了"，按间隔重复安排下次复习。
struct ReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Mistake.reviewDue) private var mistakes: [Mistake]

    @State private var revealed = false
    @State private var doneToday = 0

    private let scheduler = ReviewScheduler()

    private var dueMistakes: [Mistake] {
        let now = Date.now
        return mistakes.filter { scheduler.isDue($0.reviewState, now: now) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let mistake = dueMistakes.first {
                    card(for: mistake)
                } else {
                    ContentUnavailableView {
                        Label(doneToday > 0 ? "今天的复习完成了" : "暂时没有要复习的题",
                              systemImage: "checkmark.seal")
                    } description: {
                        Text(doneToday > 0 ? "本次复习了 \(doneToday) 题。" : "新加入的错题会出现在这里。")
                    }
                }
            }
            .navigationTitle("复习")
            .toolbar {
                if !dueMistakes.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Text("剩余 \(dueMistakes.count)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func card(for mistake: Mistake) -> some View {
        VStack(spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    StoredImageView(fileName: mistake.cropFileName)
                        .frame(maxWidth: .infinity)
                    Text("\(mistake.subject.title) · 第 \(mistake.questionNumber) 题")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !mistake.recognizedText.isEmpty {
                        MathText(text: mistake.recognizedText)
                    }
                    if revealed {
                        answerSection(for: mistake)
                    }
                }
                .padding()
            }

            if revealed {
                HStack(spacing: 12) {
                    ForEach(ReviewGrade.allCases, id: \.self) { grade in
                        Button(grade.title) { record(grade, for: mistake) }
                            .buttonStyle(.borderedProminent)
                            .tint(tint(for: grade))
                            .frame(maxWidth: .infinity)
                    }
                }
                .controlSize(.large)
                .padding(.horizontal)
            } else {
                Button("先自己做一遍，再看答案") { revealed = true }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
        }
        .padding(.bottom)
        .id(mistake.id)  // 换题时重置滚动位置
    }

    @ViewBuilder
    private func answerSection(for mistake: Mistake) -> some View {
        if !mistake.studentAnswer.isEmpty {
            LabeledText(title: "当时的答案", text: mistake.studentAnswer)
        }
        if let answer = mistake.displayAnswer {
            VStack(alignment: .leading, spacing: 4) {
                Text(answer.isAI ? "标准答案（AI 生成，仅供参考）" : "正确答案与解析")
                    .font(.caption).foregroundStyle(.secondary)
                MathText(text: answer.text)
            }
        } else {
            LabeledText(title: "正确答案与解析",
                        text: mistake.answerStatus == .pending || mistake.answerStatus == .generating
                            ? "答案正在生成中…" : "还没有答案，可在错题详情里补充。")
        }
        if !mistake.causes.isEmpty {
            LabeledText(title: "错因",
                        text: MistakeCause.allCases.filter(mistake.causes.contains).map(\.title).joined(separator: "、"))
        }
        if !mistake.note.isEmpty {
            LabeledText(title: "笔记", text: mistake.note)
        }
    }

    private func record(_ grade: ReviewGrade, for mistake: Mistake) {
        let now = Date.now
        mistake.reviewState = scheduler.next(after: mistake.reviewState, grade: grade, now: now)
        let log = ReviewLog(grade: grade, date: now)
        modelContext.insert(log)
        log.mistake = mistake
        doneToday += 1
        revealed = false
    }

    private func tint(for grade: ReviewGrade) -> Color {
        switch grade {
        case .forgot: .red
        case .fuzzy: .orange
        case .remembered: .green
        }
    }
}

private struct LabeledText: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
