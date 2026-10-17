import Foundation

/// 提示词。系统提示词来自 shared/prompts 的打包副本，与 Python 端和中转后端共用。
public enum Prompts {
    public static let analyzeUser = "请分析这张试卷照片，按要求输出 JSON。"
    public static let probeUser = "图片里有一个彩色几何图形。请只回答它的颜色和形状，例如“红色圆形”。"

    public static var analyzeSystem: String { load("analyze_page") }
    public static var solveSystem: String { load("solve_question") }

    /// 解题请求的用户消息。与 recognition/notbad_recog/prompts.py 的 solve_user_prompt 保持一致。
    public static func solveUser(text: String, subject: String = "", studentAnswer: String = "") -> String {
        var lines: [String] = []
        if !subject.isEmpty { lines.append("学科：\(subject)") }
        lines.append("识别出的题干：\(text.isEmpty ? "（未识别，请看图片）" : text)")
        if !studentAnswer.isEmpty { lines.append("学生的错误答案：\(studentAnswer)") }
        lines.append("请按要求输出 JSON。")
        return lines.joined(separator: "\n")
    }

    static func load(_ name: String) -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "md", subdirectory: "prompts"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            preconditionFailure("缺少提示词资源 \(name).md，请运行 scripts/sync_prompts.sh")
        }
        return text
    }
}
