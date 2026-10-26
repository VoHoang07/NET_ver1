import XCTest
@testable import NET_ver1

/// Test lời nhắc — vì lời nhắc là thứ người dùng đọc và làm theo, nên nó phải
/// đúng và phải cụ thể. Lời nhắc chung chung thì vô dụng.
final class CoachingMessageTests: XCTestCase {

    // MARK: - Mọi lời nhắc đều phải có hành động

    func testEveryMessageHasActionAndTitle() {
        let messages: [CoachingMessage] = [
            .postureEyeTooLow, .postureEyeTooHigh, .headClipped, .subjectOffCenter,
            .subjectTooSmall, .subjectTooLarge, .subjectTooWide, .overexposed,
            .underexposed, .backlit, .faceShadowed, .blurry,
            .tiltedLeft(degrees: 3), .tiltedRight(degrees: 5),
            .wrongSubjectCount(expected: 2, actual: 1), .noSubjectDetected,
            .clutteredBackground, .darkCondition
        ]

        for message in messages {
            XCTAssertFalse(message.title.isEmpty, "\(message) thiếu tiêu đề")
            XCTAssertFalse(message.action.isEmpty, "\(message) thiếu hành động")
        }
    }

    func testActionIsNotJustRestatingTheProblem() {
        // Lời nhắc phải chứa động từ hành động, không chỉ nêu lại lỗi.
        let actionVerbs = [
            "Nghiêng", "Lùi", "Tiến", "Bật", "Xoay", "Đứng", "Cúi", "Tìm",
            "Dịch", "Giảm", "Hạ", "Thu", "Giữ", "Ánh"
        ]
        let messages: [CoachingMessage] = [
            .postureEyeTooLow, .headClipped, .subjectTooSmall, .overexposed,
            .underexposed, .backlit, .faceShadowed, .blurry,
            .tiltedLeft(degrees: 3), .clutteredBackground
        ]

        for message in messages {
            let hasVerb = actionVerbs.contains { message.action.contains($0) }
            XCTAssertTrue(hasVerb, "Hành động của \(message) không có động từ: \(message.action)")
        }
    }

    func testMessagesHaveUniqueIDs() {
        let messages: [CoachingMessage] = [
            .postureEyeTooLow, .postureEyeTooHigh, .headClipped, .overexposed,
            .tiltedLeft(degrees: 3), .tiltedRight(degrees: 3)
        ]
        let ids = messages.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "id phải khác nhau để SwiftUI ForEach không trùng")
    }

    // MARK: - Tilt direction phải đúng

    /// Nghiêng sang phải thì phải bảo **xoay sang trái** để cân lại.
    func testTiltedRightTellsUserToRotateLeft() {
        let message = CoachingMessage.tiltedRight(degrees: 4)
        XCTAssertTrue(message.action.contains("trái"), "Máy đang nghiêng phải thì phải bảo xoay trái, đang là: \(message.action)")
    }

    func testTiltedLeftTellsUserToRotateRight() {
        let message = CoachingMessage.tiltedLeft(degrees: 4)
        XCTAssertTrue(message.action.contains("phải"), "Máy đang nghiêng trái thì phải bảo xoay phải, đang là: \(message.action)")
    }

    func testTiltedMessageIncludesDegreeAmount() {
        XCTAssertTrue(CoachingMessage.tiltedLeft(degrees: 7).action.contains("7"))
    }

    // MARK: - Subject count

    func testTooFewPeopleAsksForMore() {
        let message = CoachingMessage.wrongSubjectCount(expected: 2, actual: 1)
        XCTAssertTrue(message.action.contains("Cần"))
    }

    func testTooManyPeopleAsksToTrimDown() {
        let message = CoachingMessage.wrongSubjectCount(expected: 1, actual: 4)
        XCTAssertTrue(message.action.contains("thu lại"), "Khi dư người phải bảo thu lại, đang là: \(message.action)")
    }

    // MARK: - Ánh xạ theo tiêu chí

    func testLightingDetailSelectsCorrectMessage() {
        XCTAssertEqual(
            CoachingMessage.message(for: .lighting, detail: "Vùng sáng bị cháy 30%"),
            .overexposed
        )
        XCTAssertEqual(
            CoachingMessage.message(for: .lighting, detail: "Vùng tối bị chìm 40%"),
            .underexposed
        )
        XCTAssertEqual(
            CoachingMessage.message(for: .lighting, detail: "Chủ thể tối hơn nền — đang ngược sáng"),
            .backlit
        )
    }

    func testCriteriaWithoutSpecificMessageReturnNil() {
        // Người dùng vẫn phải thấy detail của các tiêu chí này.
        XCTAssertNil(CoachingMessage.message(for: .horizon, detail: "Nghiêng 3.2°"))
        XCTAssertNil(CoachingMessage.message(for: .composition, detail: "Cần 2 người"))
        XCTAssertNil(CoachingMessage.message(for: .posture, detail: "Mắt lệch 6.0%"))
    }

    func testShadowAndSharpnessAndBackgroundAlwaysHaveMessages() {
        XCTAssertEqual(CoachingMessage.message(for: .shadow, detail: "Có bóng"), .faceShadowed)
        XCTAssertEqual(CoachingMessage.message(for: .sharpness, detail: "Mờ"), .blurry)
        XCTAssertEqual(CoachingMessage.message(for: .background, detail: "Nền rối"), .clutteredBackground)
    }
}
