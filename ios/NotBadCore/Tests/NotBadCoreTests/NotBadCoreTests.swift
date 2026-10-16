import Foundation
import XCTest
@testable import NotBadCore

final class NormalizedBoxTests: XCTestCase {
    func testInitFixesOrderAndClamps() {
        let box = NormalizedBox(x0: 500, y0: 1200, x1: -10, y1: 200)
        XCTAssertEqual(box, NormalizedBox(x0: 0, y0: 200, x1: 500, y1: 1000))
    }

    func testPixelRoundTrip() {
        let box = NormalizedBox(pixelX0: 200, pixelY0: 500, pixelX1: 1200, pixelY1: 1000,
                                imageWidth: 2000, imageHeight: 1000)
        XCTAssertEqual(box, NormalizedBox(x0: 100, y0: 500, x1: 600, y1: 1000))
        let rect = box.pixelRect(imageWidth: 2000, imageHeight: 1000)
        XCTAssertEqual(rect.x, 200)
        XCTAssertEqual(rect.y, 500)
        XCTAssertEqual(rect.width, 1000)
        XCTAssertEqual(rect.height, 500)
    }

    func testPaddingAndUsable() {
        XCTAssertEqual(NormalizedBox(x0: 5, y0: 5, x1: 100, y1: 100).padded(by: 10),
                       NormalizedBox(x0: 0, y0: 0, x1: 110, y1: 110))
        XCTAssertFalse(NormalizedBox(x0: 0, y0: 0, x1: 5, y1: 500).isUsable())
        XCTAssertTrue(NormalizedBox(x0: 0, y0: 0, x1: 50, y1: 50).isUsable())
    }

    func testIoU() {
        let a = NormalizedBox(x0: 0, y0: 0, x1: 10, y1: 10)
        XCTAssertEqual(a.iou(with: a), 1)
        XCTAssertEqual(a.iou(with: NormalizedBox(x0: 5, y0: 0, x1: 15, y1: 10)), 50.0 / 150.0, accuracy: 1e-9)
    }

    func testCodableAsArray() throws {
        let box = try JSONDecoder().decode(NormalizedBox.self, from: Data("[1, 2, 3, 4]".utf8))
        XCTAssertEqual(box, NormalizedBox(x0: 1, y0: 2, x1: 3, y1: 4))
        XCTAssertEqual(String(decoding: try JSONEncoder().encode(box), as: UTF8.self), "[1,2,3,4]")
        XCTAssertThrowsError(try JSONDecoder().decode(NormalizedBox.self, from: Data("[1, 2, 3]".utf8)))
    }
}

final class RecognitionParserTests: XCTestCase {
    func testParsesFencedReplyWithDefaults() throws {
        let reply = """
        好的：
        ```json
        {"subject": "数学", "questions": [
          {"number": 3, "bbox": [500, 400, 100, 200], "teacher_mark": "WRONG", "is_wrong": true, "confidence": 0.8},
          {"number": " 4 ", "teacher_mark": "checkmark"}
        ]}
        ```
        """
        let page = try RecognitionParser.parsePage(from: reply)
        XCTAssertEqual(page.subject, "数学")
        XCTAssertEqual(page.questions.count, 2)
        let q3 = page.questions[0]
        XCTAssertEqual(q3.number, "3")
        XCTAssertEqual(q3.bbox, NormalizedBox(x0: 100, y0: 200, x1: 500, y1: 400))
        XCTAssertEqual(q3.teacherMark, .wrong)
        XCTAssertTrue(q3.isWrong)
        XCTAssertEqual(page.questions[1].number, "4")
        XCTAssertEqual(page.questions[1].teacherMark, TeacherMark.none)
        XCTAssertEqual(page.wrongQuestions.map(\.number), ["3"])
    }

    func testNoJSONThrows() {
        XCTAssertThrowsError(try RecognitionParser.parsePage(from: "无法识别")) { error in
            XCTAssertEqual(error as? RecognitionParseError, .noJSONObject)
        }
    }

    /// 与 Python 识别原型共用同一份示例标注，保证两边格式一致。
    func testDecodesSharedExampleLabel() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // NotBadCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // NotBadCore
            .deletingLastPathComponent()  // ios
            .deletingLastPathComponent()  // 仓库根目录
            .appendingPathComponent("recognition/data/example/page_example.json")
        let page = try JSONDecoder().decode(RecognizedPage.self, from: Data(contentsOf: url))
        XCTAssertEqual(Subject(title: page.subject), .math)
        XCTAssertEqual(page.questions.map(\.number), ["1", "2", "二.1"])
        XCTAssertEqual(page.wrongQuestions.count, 1)
        XCTAssertTrue(page.questions[2].hasFigure)
    }
}

final class ReviewSchedulerTests: XCTestCase {
    var scheduler: ReviewScheduler!
    var start: Date!

    override func setUp() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        scheduler = ReviewScheduler(calendar: calendar)
        // 2026-10-16 15:00 北京时间
        start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 15))!
    }

    private func day(_ offset: Int) -> Date {
        scheduler.calendar.date(byAdding: .day, value: offset, to: scheduler.calendar.startOfDay(for: start))!
    }

    func testNewMistakeIsDueToday() {
        let s = scheduler.initialState(createdAt: start)
        XCTAssertEqual(s.due, day(0))
        XCTAssertTrue(scheduler.isDue(s, now: start))
    }

    func testRememberedGrowsInterval() {
        var s = scheduler.initialState(createdAt: start)
        s = scheduler.next(after: s, grade: .remembered, now: start)
        XCTAssertEqual(s.intervalDays, 1)
        XCTAssertEqual(s.due, day(1))
        s = scheduler.next(after: s, grade: .remembered, now: day(1))
        XCTAssertEqual(s.intervalDays, 3)
        s = scheduler.next(after: s, grade: .remembered, now: day(4))
        XCTAssertEqual(s.intervalDays, 8)  // 3 × 2.5 = 7.5 → 8
        XCTAssertEqual(s.due, day(12))
        XCTAssertFalse(scheduler.isDue(s, now: day(11)))
    }

    func testForgotResetsAndLowersEase() {
        var s = scheduler.initialState(createdAt: start)
        for _ in 0..<3 { s = scheduler.next(after: s, grade: .remembered, now: start) }
        s = scheduler.next(after: s, grade: .forgot, now: start)
        XCTAssertEqual(s.repetitions, 0)
        XCTAssertEqual(s.lapses, 1)
        XCTAssertEqual(s.intervalDays, 1)
        XCTAssertEqual(s.ease, 2.3, accuracy: 1e-9)
    }

    func testEaseHasFloorAndIntervalHasCap() {
        var s = scheduler.initialState(createdAt: start)
        for _ in 0..<20 { s = scheduler.next(after: s, grade: .forgot, now: start) }
        XCTAssertEqual(s.ease, ReviewScheduler.minEase, accuracy: 1e-9)
        for _ in 0..<30 { s = scheduler.next(after: s, grade: .remembered, now: start) }
        XCTAssertEqual(s.intervalDays, ReviewScheduler.maxIntervalDays)
        XCTAssertTrue(scheduler.isMastered(s))
    }

    func testFuzzyKeepsAtLeastOneDay() {
        var s = scheduler.initialState(createdAt: start)
        s = scheduler.next(after: s, grade: .fuzzy, now: start)
        XCTAssertEqual(s.intervalDays, 1)
        XCTAssertEqual(s.ease, 2.35, accuracy: 1e-9)
    }
}
