import Foundation

/// Quyết định khi nào được bấm chụp tự động.
///
/// ## Vì sao cần cả ba điều kiện
///
/// Bấm sau 1,2 giây giữ nguyên là **rủi ro lớn nhất của app**. Người mẫu đang
/// chỉnh tóa, xoay đầu, hay chớp mắt — app bấm, họ nói "tôi chưa sẵn sàng", và
/// mất lòng tin ngay lập tức.
///
/// Ảnh hỏng tệ hơn bấm chậm một chút. Vì vậy ta đòi **ba điều kiện cùng lúc**:
///
/// 1. **Đúng chỗ** — người mẫu đã vào đúng bố cục app chọn.
/// 2. **Giữ yên** — đứng yên liên tục đủ lâu.
/// 3. **Mắt mở** — không chớp mắt, không quay đầu đi chỗ khác.
///
/// Ba điều kiện này gần như không thể trùng nhầm với nhau.
nonisolated struct AutoCaptureDecider: Sendable {

    /// Thời gian phải giữ yên trước khi bấm.
    ///
    /// - Important: **1,2 giây** là đánh đổi giữa hai lỗi. Ngắn hơn dễ bấm lúc
    ///   người mẫu chưa ổn; dài hơn thì họ mất kiên nhẫn và bỏ app. Số này chọn
    ///   theo phản hồi thực tế, sẽ tinh chỉnh sau khi có người dùng thật.
    nonisolated static let requiredStillness = Duration.seconds(1.2)

    /// Trạng thái của bộ quyết định, chạy liên tục theo từng khung hình.
    nonisolated struct State: Sendable {
        /// Thời điểm bắt đầu giữ yên liên tục.
        var stillnessStartedAt: ContinuousClock.Instant?
        /// Điểm khớp của lần đánh giá gần nhất.
        var lastScore: CGFloat = 0
        /// Độ lệch đầu gần nhất, dùng phát hiện quay đầu đi chỗ khác.
        var lastHeadX: CGFloat?
    }

    var state = State()

    /// Kết quả cho một khung hình.
    nonisolated enum Decision: Equatable {
        /// Chưa đủ điều kiện — tiếp tục chờ.
        case waiting
        /// Chờ thêm một chút, đã gần đạt.
        case nearlyReady(progress: CGFloat)
        /// Bấm chụp.
        case capture
    }

    /// Cập nhật và quyết định.
    ///
    /// - Parameters:
    ///   - now: thời điểm hiện tại.
    ///   - match: kết quả chấm tư thế.
    ///   - eyesOpen: mắt có đang mở không.
    ///   - headMoved: đầu có vừa di chuyển mạnh không.
    mutating func evaluate(
        now: ContinuousClock.Instant,
        match: PostureMatch,
        eyesOpen: Bool,
        headMoved: Bool
    ) -> Decision {
        let score = match.score
        state.lastScore = score

        // Dùng `isAligned` — cùng định nghĩa với màu xanh trên màn hình. Trước đây
        // dùng `score >= idealThreshold`, chỉ trùng khớp do hằng số tình cờ nên
        // đổi ngưỡng một chỗ là app bấm chụp lúc vẫn hiện chưa khớp.
        let aligned = match.isAligned

        // Ba điều kiện phải đúng **cùng lúc**. Không cái nào được bù cho cái nào.
        guard aligned, eyesOpen, !headMoved else {
            state.stillnessStartedAt = nil
            // Tiến độ phải về 0: vòng tròn đếm ngược chỉ có nghĩa khi cả ba điều
            // kiện đang đúng. Trả `score` ở đây làm vòng tròn nhảy gần 100% rồi
            // đứng yên lúc mắt còn nhắm — nhìn như app bị treo.
            return aligned ? .nearlyReady(progress: 0) : .waiting
        }

        if state.stillnessStartedAt == nil {
            state.stillnessStartedAt = now
            return .nearlyReady(progress: score)
        }

        let held = now - (state.stillnessStartedAt ?? now)
        guard held >= Self.requiredStillness else {
            return .nearlyReady(progress: min(Self.fraction(held), 1))
        }

        return .capture
    }

    /// Gọi sau khi bấm, để không bấm liên tục nhiều ảnh liên tiếp.
    mutating func reset() {
        state.stillnessStartedAt = nil
        state.lastScore = 0
        state.lastHeadX = nil
    }

    /// Tiến độ hiện tại (0...1) để vẽ vòng tròn đếm ngược.
    func progress(at now: ContinuousClock.Instant) -> CGFloat {
        guard let started = state.stillnessStartedAt else { return 0 }
        return min(Self.fraction(now - started), 1)
    }

    /// Đổi `Duration` sang tỉ lệ 0...1 so với ngưỡng giữ yên.
    private static func fraction(_ duration: Duration) -> CGFloat {
        let total = seconds(of: requiredStillness)
        guard total > 0 else { return 0 }
        return seconds(of: duration) / total
    }

    private static func seconds(of duration: Duration) -> CGFloat {
        CGFloat(duration.components.seconds)
            + CGFloat(duration.components.attoseconds) / 1e18
    }
}