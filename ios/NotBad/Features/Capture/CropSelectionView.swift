import NotBadCore
import SwiftUI

/// 确认页上的试卷图：
/// - 红框：要保存的错题（模型判错或用户选中）；橙框：模型判错但把握不大
/// - 灰色虚线框：模型识别出的其他题，点一下改为错题
/// - 拖动画新框补漏；点手动画的框删除
struct CropSelectionView: View {
    let image: UIImage
    @Binding var boxes: [DraftBox]

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

                // 未选中的画在下面，避免挡住错题框
                ForEach(boxes.filter { !$0.isSelected }) { draft in
                    boxView(draft, rect: viewRect(for: draft.box, in: frame))
                }
                ForEach(boxes.filter(\.isSelected)) { draft in
                    boxView(draft, rect: viewRect(for: draft.box, in: frame))
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
                        if box.isUsable() { boxes.append(DraftBox(box: box, isSelected: true)) }
                        dragStart = nil
                        dragCurrent = nil
                    }
            )
        }
    }

    private func boxView(_ draft: DraftBox, rect: CGRect) -> some View {
        let color: Color = draft.isSelected ? (draft.needsReview ? .orange : .red) : .gray
        return Rectangle()
            .fill(color.opacity(draft.isSelected ? 0.12 : 0.04))
            .overlay(
                Rectangle().stroke(color, style: StrokeStyle(lineWidth: draft.isSelected ? 2 : 1,
                                                             dash: draft.isSelected ? [] : [4]))
            )
            .overlay(alignment: .topLeading) {
                if let number = draft.question?.number, !number.isEmpty {
                    Text(number)
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3)
                        .background(color)
                }
            }
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
            .onTapGesture { toggle(draft) }
    }

    private func toggle(_ draft: DraftBox) {
        guard let index = boxes.firstIndex(where: { $0.id == draft.id }) else { return }
        if draft.isManual {
            boxes.remove(at: index)
        } else {
            boxes[index].isSelected.toggle()
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
