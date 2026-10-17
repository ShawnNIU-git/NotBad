import NotBadCore
import SwiftData
import SwiftUI

struct MistakeDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var mistake: Mistake
    @State private var isRecognizing = false
    @State private var isEditingText = false

    var body: some View {
        Form {
            Section {
                StoredImageView(fileName: mistake.cropFileName)
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets())
            }

            Section("基本信息") {
                Picker("学科", selection: $mistake.subject) {
                    ForEach(Subject.allCases) { Text($0.title).tag($0) }
                }
                LabeledContent("题号") {
                    TextField("题号", text: $mistake.questionNumber)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section {
                if isEditingText || mistake.recognizedText.isEmpty {
                    TextEditor(text: $mistake.recognizedText)
                        .frame(minHeight: 80)
                } else {
                    MathText(text: mistake.recognizedText)
                }
            } header: {
                HStack {
                    Text("题目")
                    Spacer()
                    Button(isEditingText ? "完成" : "编辑") { isEditingText.toggle() }
                        .font(.caption)
                    Button(isRecognizing ? "识别中…" : "本机识别", action: recognize)
                        .disabled(isRecognizing)
                        .font(.caption)
                }
            } footer: {
                Text("公式用 $...$ 表示。识别不准可以直接修改。")
            }

            Section("我的答案") {
                TextField("当时写的答案", text: $mistake.studentAnswer, axis: .vertical)
            }

            aiAnswerSection

            Section("正确答案与解析（我的订正）") {
                TextField("订正后的答案、解题思路", text: $mistake.correctAnswer, axis: .vertical)
            }
            Section("错因") {
                CauseTagsView(selection: $mistake.causes)
            }
            if !mistake.knowledgePoints.isEmpty {
                Section("知识点") {
                    Text(mistake.knowledgePoints.joined(separator: "、"))
                }
            }
            Section("笔记") {
                TextField("提醒自己的话", text: $mistake.note, axis: .vertical)
            }

            Section("复习") {
                LabeledContent("下次复习", value: mistake.reviewDue.formatted(date: .abbreviated, time: .omitted))
                LabeledContent("已复习", value: "\(mistake.logs.count) 次")
                LabeledContent("忘记", value: "\(mistake.reviewLapses) 次")
                ForEach(mistake.logs.sorted { $0.date > $1.date }.prefix(10)) { log in
                    LabeledContent(log.date.formatted(date: .abbreviated, time: .shortened), value: log.grade.title)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("第 \(mistake.questionNumber) 题")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var aiAnswerSection: some View {
        switch mistake.answerStatus {
        case .none:
            Section("标准答案") {
                Button("用 AI 生成答案") { AnswerGenerator.shared.regenerate(mistake, context: modelContext) }
                    .disabled(ServiceProvider.current() == nil)
                if ServiceProvider.current() == nil {
                    Text("需要先在设置里开启会员服务或填写 API key。").font(.footnote).foregroundStyle(.secondary)
                }
            }
        case .pending, .generating:
            Section("标准答案") {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(mistake.answerStatus == .pending ? "排队中…" : "正在生成答案…")
                        .foregroundStyle(.secondary)
                }
            }
        case .failed:
            Section("标准答案") {
                Text("生成失败：\(mistake.answerError)").font(.footnote).foregroundStyle(.red)
                Button("重试") { AnswerGenerator.shared.regenerate(mistake, context: modelContext) }
            }
        case .done:
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("答案").font(.caption).foregroundStyle(.secondary)
                    MathText(text: mistake.aiAnswer)
                    if !mistake.aiExplanation.isEmpty {
                        Text("解析").font(.caption).foregroundStyle(.secondary)
                        MathText(text: mistake.aiExplanation)
                    }
                    if !mistake.aiCommonMistake.isEmpty {
                        Text("易错提醒").font(.caption).foregroundStyle(.secondary)
                        MathText(text: mistake.aiCommonMistake)
                    }
                }
                HStack {
                    Button("采用为我的订正") {
                        mistake.correctAnswer = mistake.aiExplanation.isEmpty
                            ? mistake.aiAnswer : "\(mistake.aiAnswer)\n\(mistake.aiExplanation)"
                    }
                    .buttonStyle(.borderless)
                    Spacer()
                    Button("重新生成") { AnswerGenerator.shared.regenerate(mistake, context: modelContext) }
                        .buttonStyle(.borderless)
                }
                .font(.footnote)
            } header: {
                Text("标准答案（AI 生成）")
            } footer: {
                Text(mistake.aiConfidence < 0.6
                     ? "AI 对这道题把握不大，请对照课本或问老师确认。"
                     : "AI 生成，仅供参考。")
            }
        }
    }

    private func recognize() {
        guard let image = ImageStore.load(mistake.cropFileName) else { return }
        isRecognizing = true
        Task {
            if let text = try? await TextRecognizer.recognize(image) {
                mistake.recognizedText = text
            }
            isRecognizing = false
        }
    }
}

/// 错因多选标签。
struct CauseTagsView: View {
    @Binding var selection: Set<MistakeCause>

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84))], spacing: 8) {
            ForEach(MistakeCause.allCases) { cause in
                let selected = selection.contains(cause)
                Button {
                    if selected { selection.remove(cause) } else { selection.insert(cause) }
                } label: {
                    Text(cause.title)
                        .font(.footnote)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(selected ? Color.accentColor : Color.secondary.opacity(0.12))
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}
