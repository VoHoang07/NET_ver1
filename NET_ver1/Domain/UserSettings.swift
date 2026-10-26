import CoreGraphics
import Foundation

/// Thông tin người dùng mà app cần để quy đổi khoảng cách thật.
///
/// ## Vì sao cần chiều cao
///
/// Quét phòng cho ra **bản đồ phẳng** — biết bàn ở đâu, nhưng không biết bàn cao
/// bao nhiêu, giống bản vẽ mặt bằng. Mà không biết chiều cao bàn thì không dựng
/// được tư thế ngồi đúng.
///
/// Lối thoát: dùng chính người mẫu làm thước đo. Biết cao 1,7m thì suy ra
/// chiều cao đầu, rồi suy ra chiều cao bàn.
///
/// ## Vì sao hỏi một lần rồi nhớ lại
///
/// Hỏi mỗi lần chụp thì phiền, và phiền thì bỏ. Hỏi một lần, nhớ lại, xong.
nonisolated struct UserHeight: Equatable, Sendable {
    /// Chiều cao người, tính bằng mét.
    let meters: CGFloat
    /// Ngày người dùng xác nhận — dùng để biết khi cần hỏi lại.
    let confirmedAt: Date

    /// Khoảng hợp lý cho người trưởng thành. Ngoài khoảng này thì khả năng cao
    /// người dùng gõ nhầm — mà sai chiều cao thì sai luôn khoảng cách.
    nonisolated static let range: ClosedRange<CGFloat> = 1.2...2.2
    nonisolated static let defaultMeters: CGFloat = 1.70

    /// Có dùng được không.
    var isValid: Bool { Self.range.contains(meters) }

    /// Chiều cao đầu tương ứng, tính bằng mét.
    var headHeight: CGFloat {
        BodyPoseReference.headHeight(forUserHeight: meters)
    }

    /// Khoảng cách máy mong muốn cho một tư thế, tính bằng mét.
    func standoff(for pose: ShootingPose) -> CGFloat {
        pose.standoffInHeads * headHeight
    }
}

/// Lưu và đọc thông tin người dùng từ `UserDefaults`.
///
/// - Important: chỉ lưu **một** thứ duy nhất là chiều cao. Không thu thập vị trí,
///   không thu thập danh tính — app là ứng dụng chụp ảnh, không cần những thứ đó.
nonisolated enum UserSettingsStore {
    private static let heightKey = "user.heightMeters"
    private static let dateKey = "user.heightConfirmedAt"

    /// Đọc chiều cao đã lưu. `nil` nếu chưa hỏi hoặc giá trị không hợp lệ.
    static func loadHeight() -> UserHeight? {
        let defaults = UserDefaults.standard
        guard let meters = defaults.object(forKey: heightKey) as? Double else { return nil }

        let value = UserHeight(meters: CGFloat(meters), confirmedAt: Date())
        guard value.isValid else { return nil }
        return value
    }

    /// Lưu chiều cao sau khi người dùng xác nhận.
    static func saveHeight(_ meters: CGFloat) {
        let defaults = UserDefaults.standard
        defaults.set(Double(meters), forKey: heightKey)
        defaults.set(Date(), forKey: dateKey)
    }

    /// Xoá để hỏi lại.
    static func clearHeight() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: heightKey)
        defaults.removeObject(forKey: dateKey)
    }

    /// Cần hỏi chiều cao không.
    ///
    /// - Important: hỏi muộn. Hỏi lúc mở app thì người dùng chưa hiểu app cần gì,
    ///   dễ bỏ qua. Hỏi lúc họ đang tạo dáng thì mới thấy là hữu ích.
    static func needsHeightPrompt() -> Bool {
        loadHeight() == nil
    }
}