import NotBadCore
import SwiftData
import SwiftUI

struct MistakeListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Mistake.createdAt, order: .reverse) private var mistakes: [Mistake]

    @State private var subjectFilter: Subject?
    @State private var showingNewPaper = false

    private var filtered: [Mistake] {
        guard let subjectFilter else { return mistakes }
        return mistakes.filter { $0.subject == subjectFilter }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { mistake in
                    NavigationLink(value: mistake) {
                        MistakeRow(mistake: mistake)
                    }
                }
                .onDelete(perform: delete)
            }
            .navigationTitle(subjectFilter?.title ?? "错题本")
            .navigationDestination(for: Mistake.self) { MistakeDetailView(mistake: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("学科", selection: $subjectFilter) {
                            Text("全部").tag(Subject?.none)
                            ForEach(Subject.allCases) { Text($0.title).tag(Subject?.some($0)) }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewPaper = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .overlay {
                if filtered.isEmpty {
                    ContentUnavailableView {
                        Label("还没有错题", systemImage: "doc.text.magnifyingglass")
                    } description: {
                        Text("点右上角 + 拍摄或导入试卷，框出做错的题。")
                    }
                }
            }
            .sheet(isPresented: $showingNewPaper) {
                NewPaperView()
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let mistake = filtered[index]
            ImageStore.delete(mistake.cropFileName)
            // 原图属于试卷，删除试卷时才删
            modelContext.delete(mistake)
        }
    }
}

private struct MistakeRow: View {
    let mistake: Mistake

    var body: some View {
        HStack(spacing: 12) {
            StoredImageView(fileName: mistake.cropFileName, contentMode: .fill)
                .frame(width: 72, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 4) {
                Text(mistake.recognizedText.isEmpty ? "第 \(mistake.questionNumber) 题" : MathText.plain(mistake.recognizedText))
                    .lineLimit(2)
                    .font(.subheadline)
                HStack(spacing: 6) {
                    Text(mistake.subject.title)
                    if mistake.answerStatus == .pending || mistake.answerStatus == .generating {
                        Image(systemName: "hourglass")
                    } else if mistake.answerStatus == .done {
                        Image(systemName: "lightbulb")
                    }
                    ForEach(MistakeCause.allCases.filter(mistake.causes.contains)) { cause in
                        Text(cause.title)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Text("下次复习：\(mistake.reviewDue.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
