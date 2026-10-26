import Foundation

/// Gợi ý dạng chữ, luôn kèm **hành động cụ thể**.
///
/// "Ánh sáng chưa tốt" không giúp ích gì. "Nghiêng máy sang trái để ánh sáng chiếu
/// vào mặt" thì người dùng làm được ngay.
nonisolated enum CoachingMessage: Equatable, Identifiable {
    case postureEyeTooLow
    case postureEyeTooHigh
    case headClipped
    case subjectOffCenter
    case subjectTooSmall
    case subjectTooLarge
    case subjectTooWide
    case overexposed
    case underexposed
    case backlit
    case faceShadowed
    case blurry
    case tiltedLeft(degrees: Int)
    case tiltedRight(degrees: Int)
    case wrongSubjectCount(expected: Int, actual: Int)
    case noSubjectDetected
    case clutteredBackground
    case darkCondition

    var id: String { title }

    /// Tiêu đề ngắn hiển thị cạnh trạng thái.
    var title: String {
        switch self {
        case .postureEyeTooLow: "Đứng cao hơn một chút"
        case .postureEyeTooHigh: "Hạ thấp người xuống một chút"
        case .headClipped: "Đầu đã bị cắt"
        case .subjectOffCenter: "Lệch tâm khung"
        case .subjectTooSmall: "Đứng gần hơn"
        case .subjectTooLarge: "Lùi xa hơn"
        case .subjectTooWide: "Chủ thể quá bề ngang"
        case .overexposed: "Ánh sáng bị cháy"
        case .underexposed: "Ảnh đang tối"
        case .backlit: "Đang ngược sáng"
        case .faceShadowed: "Mặt đang bị che bóng"
        case .blurry: "Ảnh đang mờ"
        case .tiltedLeft: "Nghiêng máy sang trái"
        case .tiltedRight: "Nghiêng máy sang phải"
        case .wrongSubjectCount: "Số người chưa đúng"
        case .noSubjectDetected: "Chưa nhận ra chủ thể"
        case .clutteredBackground: "Nền đang rối"
        case .darkCondition: "Ánh sáng chưa đủ"
        }
    }

    /// Hành động cụ thể người dùng phải làm.
    var action: String {
        switch self {
        case .postureEyeTooLow:
            "Đứng thẳng hơn một chút để mắt nằm đúng đường 1/3 của khung."
        case .postureEyeTooHigh:
            "Cúi thấp hơn một chút để mắt nằm đúng đường 1/3 của khung."
        case .headClipped:
            "Lùi ra xa thêm một chút để lấy trọn đỉnh đầu."
        case .subjectOffCenter:
            "Dịch sang phía đối diện để tâm người vào giữa khung."
        case .subjectTooSmall:
            "Tiến lại gần hơn cho chủ thể chiếm khoảng hai phần ba khung."
        case .subjectTooLarge:
            "Lùi xa hơn một chút, tránh chủ thể sát mép khung."
        case .subjectTooWide:
            "Lùi xa hơn hoặc thu vai lại."
        case .overexposed:
            "Giảm độ sáng máy, hoặc tránh ánh sáng trực tiếp vào mặt."
        case .underexposed:
            "Bật đèn flash, hoặc quay sang chỗ sáng hơn."
        case .backlit:
            "Nghiêng máy sang trái để nguồn sáng chiếu vào mặt thay vì chói sau lưng."
        case .faceShadowed:
            "Nghiêng đầu nhẹ, hoặc đổi chỗ sáng cho nguồn sáng cao hơn."
        case .blurry:
            "Giữ máy ổn định và chạm vào mặt để lấy nét."
        case let .tiltedLeft(degrees):
            "Xoay máy sang phải \(degrees)° để đường chân trời cân."
        case let .tiltedRight(degrees):
            "Xoay máy sang trái \(degrees)° để đường chân trời cân."
        case let .wrongSubjectCount(expected, actual):
            expected > actual
                ? "Cần \(expected) người trong khung, hiện đang có \(actual)."
                : "Khung này hơi đông — thu lại còn \(expected) người."
        case .noSubjectDetected:
            "Ánh sáng chưa đủ để nhận ra người. Tìm chỗ sáng hơn rồi thử lại."
        case .clutteredBackground:
            "Tìm nơi nền đơn giản hơn, hoặc đứng cách vật thể xa hơn."
        case .darkCondition:
            "Bật đèn flash để camera nhận ra rõ hơn."
        }
    }

    /// Gợi ý riêng cho từng tiêu chí.
    ///
    /// - Returns: `nil` nghĩa là không có gợi ý riêng, dùng `action` chung của tiêu chí.
    static func message(for criterion: QualityCriterion, detail: String?) -> CoachingMessage? {
        switch criterion {
        case .posture:
            if detail?.contains("Mắt lệch") == true {
                return nil // giữ chi tiết hướng dẫn trong thông số
            }
            return nil
        case .lighting:
            if detail?.contains("cháy") == true { return .overexposed }
            if detail?.contains("chìm") == true { return .underexposed }
            if detail?.contains("ngược sáng") == true { return .backlit }
            return nil
        case .shadow: return .faceShadowed
        case .sharpness: return .blurry
        case .background: return .clutteredBackground
        case .horizon, .composition:
            return nil
        }
    }
}
