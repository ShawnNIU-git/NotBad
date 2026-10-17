import NotBadCore
import SwiftData
import SwiftUI

struct PaperDetailView: View {
    @Bindable var paper: Paper
    @State private var showingAddPage = false
    @State private var viewingPage: String?

    private var sortedMistakes: [Mistake] {
        paper.mistakes.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        Form {
            Section("试卷信息") {
                TextField("标题", text: $paper.title)
                Picker("学科", selection: $paper.subject) {
                    ForEach(Subject.allCases) { Text($0.title).tag($0) }
                }
                Picker("类型", selection: $paper.paperType) {
                    Text("未设置").tag("")
                    ForEach(PaperType.all, id: \.self) { Text($0).tag($0) }
                }
                TextField("年级", text: $paper.grade)
            }

            Section("原卷（\(paper.pageFileNames.count) 页）") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(paper.pageFileNames, id: \.self) { name in
                            StoredImageView(fileName: name, contentMode: .fill)
                                .frame(width: 90, height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .onTapGesture { viewingPage = name }
                        }
                        Button {
                            showingAddPage = true
                        } label: {
                            VStack {
                                Image(systemName: "plus")
                                Text("添加一页").font(.caption)
                            }
                            .frame(width: 90, height: 120)
                            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("错题（\(paper.mistakes.count)）") {
                ForEach(sortedMistakes) { mistake in
                    NavigationLink(value: mistake) {
                        HStack {
                            Text(mistake.questionNumber).font(.headline).frame(minWidth: 32)
                            Text(mistake.recognizedText.isEmpty ? "（无文字）" : MathText.plain(mistake.recognizedText))
                                .lineLimit(2)
                                .font(.subheadline)
                        }
                    }
                }
            }
        }
        .navigationTitle(paper.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddPage) { NewPaperView(existingPaper: paper) }
        .fullScreenCover(item: Binding(get: { viewingPage.map(PageID.init) },
                                       set: { viewingPage = $0?.name })) { page in
            NavigationStack {
                ScrollView {
                    StoredImageView(fileName: page.name)
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { viewingPage = nil }
                    }
                }
            }
        }
    }

    /// 删除试卷时一起删掉原图和错题裁剪图。
    static func deleteFiles(of paper: Paper) {
        paper.pageFileNames.forEach { ImageStore.delete($0) }
        paper.mistakes.forEach { ImageStore.delete($0.cropFileName) }
    }
}

private struct PageID: Identifiable {
    let name: String
    var id: String { name }
}
