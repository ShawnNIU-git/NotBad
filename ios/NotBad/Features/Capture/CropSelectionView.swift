import NotBadCore
import SwiftUI

/// 在试卷图片上手动框选错题：拖动画框，点框删除。
struct CropSelectionView: View {
    let image: UIImage
    @Binding var boxes: [NormalizedBox]

    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?

    var body: some View {
        GeometryReader { geo in
            let frame = fittedFrame(imageSize: image.size, in: geo.size)
            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)

                ForEach(Array(boxes.enumerated()), id: \.offset) { index, box in
                    let rect = viewRect(for: box, in: frame)
                    Rectangle()
                        .fill(Color.red.opacity(0.12))
                        .overlay(Rectangle().stroke(Color.red, lineWidth: 2))
                        .overlay(alignment: .topLeading) {
                            Text("\(index + 1)")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .background(Color.red)
                        }
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                        .onTapGesture { boxes.remove(at: index) }
                }

                if let start = dragStart, let current = dragCurrent {
                    let rect = CGRect(start: start, end: current)
                    Rectangle()
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 2, dash: [6]))
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        dragStart = value.startLocation
                        dragCurrent = value.location
                    }
                    .onEnded { value in
                        let box = normalizedBox(from: value.startLocation, to: value.location, in: frame)
                        if box.isUsable() { boxes.append(box) }
                        dragStart = nil
                        dragCurrent = nil
                    }
            )
        }
    }

    /// scaledToFit 后图片在视图中实际占据的区域。
    private func fittedFrame(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (container.width - size.width) / 2, y: (container.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    private func normalizedBox(from a: CGPoint, to b: CGPoint, in frame: CGRect) -> NormalizedBox {
        NormalizedBox(pixelX0: a.x - frame.minX, pixelY0: a.y - frame.minY,
                      pixelX1: b.x - frame.minX, pixelY1: b.y - frame.minY,
                      imageWidth: frame.width, imageHeight: frame.height)
    }

    private func viewRect(for box: NormalizedBox, in frame: CGRect) -> CGRect {
        let s = NormalizedBox.scale
        return CGRect(x: frame.minX + box.x0 / s * frame.width,
                      y: frame.minY + box.y0 / s * frame.height,
                      width: box.width / s * frame.width,
                      height: box.height / s * frame.height)
    }
}

private extension CGRect {
    init(start: CGPoint, end: CGPoint) {
        self.init(x: min(start.x, end.x), y: min(start.y, end.y),
                  width: abs(end.x - start.x), height: abs(end.y - start.y))
    }
}
