import NotBadCore
import UIKit

/// 图片存在 Application Support/Images 下，数据库只存文件名。
enum ImageStore {
    /// 原图最长边上限，兼顾清晰度和存储空间
    static let maxPageSide: CGFloat = 2560

    private static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func url(for fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    /// 保存为 JPEG，返回文件名。
    @discardableResult
    static func save(_ image: UIImage, quality: CGFloat = 0.85) throws -> String {
        guard let data = image.jpegData(compressionQuality: quality) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let name = UUID().uuidString + ".jpg"
        // 试卷含个人信息：设备锁定时文件保持加密
        try data.write(to: url(for: name), options: [.atomic, .completeFileProtection])
        return name
    }

    static func load(_ fileName: String) -> UIImage? {
        UIImage(contentsOfFile: url(for: fileName).path)
    }

    static func delete(_ fileName: String?) {
        guard let fileName else { return }
        try? FileManager.default.removeItem(at: url(for: fileName))
    }
}

extension UIImage {
    /// 转正方向并限制尺寸。相册照片常带 EXIF 方向，裁剪前必须先转正。
    func normalizedForStorage(maxSide: CGFloat = ImageStore.maxPageSide) -> UIImage {
        // size 是点，乘以 scale 才是像素
        let pixelSize = CGSize(width: size.width * scale, height: size.height * scale)
        let ratio = min(1, maxSide / max(pixelSize.width, pixelSize.height))
        if imageOrientation == .up && ratio == 1 && scale == 1 { return self }
        let target = CGSize(width: (pixelSize.width * ratio).rounded(), height: (pixelSize.height * ratio).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// 按归一化框裁剪。调用前图片须已经过 normalizedForStorage（方向为 up、scale 为 1）。
    func cropped(to box: NormalizedBox, padding: Double = 8) -> UIImage? {
        guard let cgImage else { return nil }
        let rect = box.padded(by: padding).pixelRect(imageWidth: cgImage.width, imageHeight: cgImage.height)
        guard rect.width > 0, rect.height > 0,
              let cropped = cgImage.cropping(to: CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height))
        else { return nil }
        return UIImage(cgImage: cropped)
    }
}
