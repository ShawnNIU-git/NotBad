import UIKit
import Vision

/// 本地 OCR（Apple Vision），离线、免费，图片不出设备。
/// 对印刷体中文效果较好；数学公式和手写较弱，识别结果允许用户手动修改。
enum TextRecognizer {
    static func recognize(_ image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else { return "" }
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(cgImage: cgImage).perform([request])
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return lines.joined(separator: "\n")
        }.value
    }
}
