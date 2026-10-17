import NotBadCore
import SwiftData
import SwiftUI

/// 按试卷浏览。
struct PaperListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Paper.createdAt, order: .reverse) private var papers: [Paper]
    @State private var showingNewPaper = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(papers) { paper in
                    NavigationLink(value: paper) {
                        PaperRow(paper: paper)
                    }
                }
                .onDelete(perform: delete)
            }
            .navigationTitle("试卷")
            .navigationDestination(for: Paper.self) { PaperDetailView(paper: $0) }
            .navigationDestination(for: Mistake.self) { MistakeDetailView(mistake: $0) }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewPaper = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .overlay {
                if papers.isEmpty {
                    ContentUnavailableView("还没有试卷", systemImage: "doc.on.doc",
                                           description: Text("点右上角 + 拍摄或导入试卷。"))
                }
            }
            .sheet(isPresented: $showingNewPaper) { NewPaperView() }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            PaperDetailView.deleteFiles(of: papers[index])
            modelContext.delete(papers[index])
        }
    }
}

private struct PaperRow: View {
    let paper: Paper

    var body: some View {
        HStack(spacing: 12) {
            if let first = paper.pageFileNames.first {
                StoredImageView(fileName: first, contentMode: .fill)
                    .frame(width: 48, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(paper.displayTitle).font(.subheadline).lineLimit(2)
                Text([paper.subject.title, paper.grade, paper.paperType].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(paper.pageFileNames.count) 页 · \(paper.mistakes.count) 道错题")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
