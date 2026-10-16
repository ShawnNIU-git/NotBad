import NotBadCore
import PhotosUI
import SwiftData
import SwiftUI

/// 新建试卷：扫描或从相册导入 → 逐页框选错题 → 保存并后台 OCR。
struct NewPaperView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var pages: [UIImage] = []
    @State private var boxesByPage: [[NormalizedBox]] = []
    @State private var currentPage = 0
    @State private var subject: Subject = .math
    @State private var title = ""

    @State private var showingScanner = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var totalBoxes: Int { boxesByPage.reduce(0) { $0 + $1.count } }

    var body: some View {
        NavigationStack {
            Group {
                if pages.isEmpty {
                    sourcePicker
                } else {
                    editor
                }
            }
            .navigationTitle(pages.isEmpty ? "添加试卷" : "框选错题")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                if !pages.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存 \(totalBoxes) 题") { save() }
                            .disabled(totalBoxes == 0)
                    }
                }
            }
            .fullScreenCover(isPresented: $showingScanner) {
                DocumentScannerView(
                    onFinish: { images in
                        showingScanner = false
                        addPages(images)
                    },
                    onCancel: { showingScanner = false }
                )
                .ignoresSafeArea()
            }
            .onChange(of: pickerItems) { _, items in
                Task { await loadPickedPhotos(items) }
            }
            .alert("出错了", isPresented: Binding(get: { errorMessage != nil },
                                                  set: { if !$0 { errorMessage = nil } })) {
                Button("好") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var sourcePicker: some View {
        VStack(spacing: 16) {
            Spacer()
            if DocumentScannerView.isSupported {
                Button {
                    showingScanner = true
                } label: {
                    Label("拍摄试卷", systemImage: "doc.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            PhotosPicker(selection: $pickerItems, maxSelectionCount: 10, matching: .images) {
                Label("从相册导入", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            if isLoading { ProgressView() }
            Text("照片只保存在本机。拍摄前可以先遮住姓名和学校。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(24)
    }

    private var editor: some View {
        VStack(spacing: 8) {
            HStack {
                Picker("学科", selection: $subject) {
                    ForEach(Subject.allCases) { Text($0.title).tag($0) }
                }
                TextField("试卷名称（可选）", text: $title)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal)

            CropSelectionView(image: pages[currentPage], boxes: $boxesByPage[currentPage])
                .padding(.horizontal, 4)

            HStack {
                Button {
                    currentPage -= 1
                } label: { Image(systemName: "chevron.left") }
                    .disabled(currentPage == 0)
                Spacer()
                Text("第 \(currentPage + 1)/\(pages.count) 页 · 本页 \(boxesByPage[currentPage].count) 题")
                    .font(.footnote)
                Spacer()
                Button("撤销") { _ = boxesByPage[currentPage].popLast() }
                    .disabled(boxesByPage[currentPage].isEmpty)
                Button {
                    currentPage += 1
                } label: { Image(systemName: "chevron.right") }
                    .disabled(currentPage == pages.count - 1)
            }
            .padding(.horizontal)

            Text("在图上拖动框出错题，点框可删除")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
        }
    }

    private func addPages(_ images: [UIImage]) {
        let normalized = images.map { $0.normalizedForStorage() }
        pages.append(contentsOf: normalized)
        boxesByPage.append(contentsOf: normalized.map { _ in [] })
    }

    private func loadPickedPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        isLoading = true
        defer {
            isLoading = false
            pickerItems = []
        }
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                images.append(image)
            }
        }
        if images.isEmpty {
            errorMessage = "没有读取到图片"
        } else {
            addPages(images)
        }
    }

    private func save() {
        do {
            let pageFiles = try pages.map { try ImageStore.save($0) }
            let paper = Paper(subject: subject, title: title, pageFileNames: pageFiles)
            modelContext.insert(paper)

            var pending: [(Mistake, UIImage)] = []
            var number = 0
            for (pageIndex, boxes) in boxesByPage.enumerated() {
                for box in boxes {
                    number += 1
                    guard let crop = pages[pageIndex].cropped(to: box) else { continue }
                    let mistake = Mistake(subject: subject, questionNumber: "\(number)",
                                          cropFileName: try ImageStore.save(crop),
                                          pageFileName: pageFiles[pageIndex], box: box, source: .manual)
                    modelContext.insert(mistake)
                    mistake.paper = paper
                    pending.append((mistake, crop))
                }
            }
            try modelContext.save()
            recognizeText(for: pending)
            dismiss()
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    /// 保存后在后台逐题 OCR，识别完自动填入题干。
    private func recognizeText(for items: [(Mistake, UIImage)]) {
        Task { @MainActor in
            for (mistake, crop) in items {
                if let text = try? await TextRecognizer.recognize(crop), mistake.recognizedText.isEmpty {
                    mistake.recognizedText = text
                }
            }
        }
    }
}
