import NotBadCore
import SwiftData
import SwiftUI

struct MistakeDetailView: View {
    @Bindable var mistake: Mistake
    @State private var isRecognizing = false

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
                TextEditor(text: $mistake.recognizedText)
                    .frame(minHeight: 80)
            } header: {
                HStack {
                    Text("题目文字")
                    Spacer()
                    Button(isRecognizing ? "识别中…" : "重新识别", action: recognize)
                        .disabled(isRecognizing)
                        .font(.caption)
                }
            } footer: {
                Text("本机文字识别，公式和手写可能不准，可直接修改。")
            }

            Section("我的答案") {
                TextField("当时写的答案", text: $mistake.studentAnswer, axis: .vertical)
            }
            Section("正确答案与解析") {
                TextField("订正后的答案、解题思路", text: $mistake.correctAnswer, axis: .vertical)
            }
            Section("错因") {
                CauseTagsView(selection: $mistake.causes)
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
