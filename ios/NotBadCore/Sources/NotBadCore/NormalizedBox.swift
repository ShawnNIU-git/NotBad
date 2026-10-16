import Foundation

/// 归一化矩形，坐标范围 0-1000，左上角为原点，与图片分辨率无关。
/// 与识别原型（recognition/notbad_recog）的 bbox 格式一致，JSON 中写作 `[x0, y0, x1, y1]`。
public struct NormalizedBox: Codable, Equatable, Hashable, Sendable {
    public static let scale: Double = 1000

    public var x0: Double
    public var y0: Double
    public var x1: Double
    public var y1: Double

    /// 自动纠正坐标顺序并限制在 0-1000 内。
    public init(x0: Double, y0: Double, x1: Double, y1: Double) {
        func clamp(_ v: Double) -> Double { min(max(v, 0), Self.scale) }
        self.x0 = clamp(min(x0, x1))
        self.y0 = clamp(min(y0, y1))
        self.x1 = clamp(max(x0, x1))
        self.y1 = clamp(max(y0, y1))
    }

    /// 由像素矩形（任意两个对角点）换算，用于手动框选。
    public init(pixelX0: Double, pixelY0: Double, pixelX1: Double, pixelY1: Double,
                imageWidth: Double, imageHeight: Double) {
        self.init(x0: pixelX0 / imageWidth * Self.scale,
                  y0: pixelY0 / imageHeight * Self.scale,
                  x1: pixelX1 / imageWidth * Self.scale,
                  y1: pixelY1 / imageHeight * Self.scale)
    }

    public var width: Double { x1 - x0 }
    public var height: Double { y1 - y0 }
    public var area: Double { width * height }

    /// 太小的框多半是误触。
    public func isUsable(minSide: Double = 15) -> Bool {
        width >= minSide && height >= minSide
    }

    /// 四周各扩展 `pad`（0-1000 单位），裁剪时给题目留余量。
    public func padded(by pad: Double) -> NormalizedBox {
        NormalizedBox(x0: x0 - pad, y0: y0 - pad, x1: x1 + pad, y1: y1 + pad)
    }

    /// 换算到像素，返回 (x, y, width, height)，已取整并限制在图片范围内。
    public func pixelRect(imageWidth: Int, imageHeight: Int) -> (x: Int, y: Int, width: Int, height: Int) {
        let w = Double(imageWidth), h = Double(imageHeight)
        let left = Int((x0 / Self.scale * w).rounded())
        let top = Int((y0 / Self.scale * h).rounded())
        let right = Int((x1 / Self.scale * w).rounded())
        let bottom = Int((y1 / Self.scale * h).rounded())
        return (left, top, max(0, right - left), max(0, bottom - top))
    }

    public func iou(with other: NormalizedBox) -> Double {
        let ix = max(0, min(x1, other.x1) - max(x0, other.x0))
        let iy = max(0, min(y1, other.y1) - max(y0, other.y0))
        let inter = ix * iy
        let union = area + other.area - inter
        return union > 0 ? inter / union : 0
    }

    // JSON 中是 [x0, y0, x1, y1] 数组
    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        let values = try (0..<4).map { _ in try c.decode(Double.self) }
        guard c.isAtEnd else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "bbox 需要 4 个数")
        }
        self.init(x0: values[0], y0: values[1], x1: values[2], y1: values[3])
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(contentsOf: [x0, y0, x1, y1])
    }
}
