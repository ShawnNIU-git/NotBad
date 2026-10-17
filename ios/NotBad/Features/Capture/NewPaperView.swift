import NotBadCore
import PhotosUI
import SwiftData
import SwiftUI

/// 添加试卷：拍照或导入 → 模型自动识别错题和试卷信息 → 确认（可勾选、补框）→ 保存。
/// 保存后在后台识别文字（手动框）并生成答案。
struct NewPaperView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Paper.createdAt, order: .reverse) private var papers: [Paper]

    @State private var model: CaptureViewModel
    @State private var showingScanner = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isLoadingPhotos = false
    @State private var errorMessage: String?

    /// existingPaper 不为空时，新页面直接追加到这份试卷。
    init(existingPaper: Paper? = nil) {
        _model = State(initialValue: CaptureViewModel(targetPaper: existingPaper))
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.pages.isEmpty {
                    sourcePicker
                } else {
                    confirmation
                }
            }
            .navigationTitle(model.pages.isEmpty ? "添加试卷" : "确认错题")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                if !model.pages.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存 \(model.selectedCount) 题", action: save)
                            .disabled(model.selectedCount == 0 || model.isAnalyzing)
                    }
                }
            }
            .fullScreenCover(isPresented: $showingScanner) {
                DocumentScannerView(
                    onFinish: { images in
                        showingScanner = false
                        model.addPages(images)
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

    // MARK: - 选择来源

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
            if isLoadingPhotos { ProgressView() }

            Text(model.usesModel
                 ? "拍好后会自动找出错题，你只需要确认。拍照前建议遮住姓名和学校。"
                 : "当前未开启自动识别（可在设置里开启），需要手动框选错题。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(24)
    }

    // MARK: - 确认页

    private var confirmation: some View {
        VStack(spacing: 8) {
            paperInfo
            pageView
            pageControls
        }
    }

    private var paperInfo: some View {
        VStack(spacing: 6) {
            Picker("保存到", selection: $model.targetPaper) {
                Text("新建试卷").tag(Paper?.none)
                ForEach(papers.prefix(20)) { paper in
                    Text(paper.displayTitle).tag(Paper?.some(paper))
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Picker("学科", selection: edited(\.subject)) {
                    ForEach(Subject.allCases) { Text($0.title).tag($0) }
                }
                Picker("类型", selection: edited(\.paperType)) {
                    Text("类型").tag("")
                    ForEach(PaperType.all, id: \.self) { Text($0).tag($0) }
                }
                TextField("年级", text: edited(\.grade))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 80)
            }
            TextField("试卷标题（识别不到可留空）", text: edited(\.title))
                .textFieldStyle(.roundedBorder)
        }
        .padding(.horizontal)
        .onChange(of: model.targetPaper) { _, _ in model.targetPaperChanged() }
    }

    /// 用户手动改过的试卷信息，之后的页面识别结果不再覆盖。
    private func edited<T>(_ keyPath: ReferenceWritableKeyPath<CaptureViewModel, T>) -> Binding<T> {
        Binding(get: { model[keyPath: keyPath] },
                set: { model[keyPath: keyPath] = $0; model.markPaperInfoEdited() })
    }

    @ViewBuilder
    private var pageView: some View {
        let index = model.currentPage
        ZStack {
            CropSelectionView(image: model.pages[index].image, boxes: $model.pages[index].boxes)
                .padding(.horizontal, 4)
            switch model.pages[index].status {
            case .analyzing:
                VStack(spacing: 8) {
                    ProgressView()
                    Text("正在识别错题…").font(.footnote)
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            case let .failed(message):
                VStack(spacing: 8) {
                    Text("识别失败：\(message)").font(.footnote).multilineTextAlignment(.center)
                    Button("重试") { model.retry(pageAt: index) }
                    Text("也可以直接在图上手动框选").font(.caption).foregroundStyle(.secondary)
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding()
            case .done, .manual:
                EmptyView()
            }
        }
    }

    private var pageControls: some View {
        VStack(spacing: 4) {
            HStack {
                Button {
                    model.currentPage -= 1
                } label: { Image(systemName: "chevron.left") }
                    .disabled(model.currentPage == 0)
                Spacer()
                Text("第 \(model.currentPage + 1)/\(model.pages.count) 页 · 本页 \(model.pages[model.currentPage].boxes.filter(\.isSelected).count) 道错题")
                    .font(.footnote)
                Spacer()
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 10, matching: .images) {
                    Image(systemName: "plus.rectangle.on.rectangle")
                }
                Button {
                    model.currentPage += 1
                } label: { Image(systemName: "chevron.right") }
                    .disabled(model.currentPage == model.pages.count - 1)
            }
            .padding(.horizontal)

            Text(model.usesModel
                 ? "红框会保存为错题，橙框请确认；点灰框改为错题，点红框取消；拖动可补框"
                 : "在图上拖动框出错题，点框可删除")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .padding(.bottom, 4)
        }
    }

    // MARK: - 动作

    private func loadPickedPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        isLoadingPhotos = true
        defer {
            isLoadingPhotos = false
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
            model.addPages(images)
        }
    }

    private func save() {
        do {
            let created = try model.save(context: modelContext)
            recognizeTextLocally(for: created.filter { $0.0.recognizedText.isEmpty })
            AnswerGenerator.shared.run(context: modelContext)
            dismiss()
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    /// 手动框的题没有模型识别的文字，用本机 OCR 补上。
    private func recognizeTextLocally(for items: [(Mistake, UIImage)]) {
        guard !items.isEmpty else { return }
        Task { @MainActor in
            for (mistake, crop) in items {
                if let text = try? await TextRecognizer.recognize(crop), mistake.recognizedText.isEmpty {
                    mistake.recognizedText = text
                }
            }
        }
    }
}
