import SwiftUI

/// 异步加载 ImageStore 中的图片，避免列表滚动时卡主线程。
struct StoredImageView: View {
    let fileName: String
    var contentMode: ContentMode = .fit

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.1))
                    .overlay(ProgressView())
            }
        }
        .task(id: fileName) {
            let name = fileName
            image = await Task.detached(priority: .utility) { ImageStore.load(name) }.value
        }
    }
}
