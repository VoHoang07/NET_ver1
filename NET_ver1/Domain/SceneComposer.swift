import CoreGraphics
import Foundation

/// Quyết định người 3D đứng ở đâu, quay mặt thế nào, và cần zoom bao nhiêu.
///
/// ## Ranh giới
///
/// Lớp này là **hàm thuần**: cùng đầu vào thì cho cùng kết quả, không đọc camera,
/// không đụng UI. Nhờ vậy toàn bộ "app chọn góc nào" test được không cần thiết bị.
///
/// ## Điều app **không** biết
///
/// App không có bản đồ phòng. Nó chỉ biết **khung hình đang chụp có gì** —
/// người mẫu đang ở đâu, và ống kính đang ở mức nào. Mọi quyết định dưới đây
/// dựa trên hai thứ đó.
///
/// Hệ quả: ở phòng chật mà bàn kính chiếm giữa khung, app không biết cái bàn
/// là vật cản — nó chỉ biết người mẫu. Vì vậy `SceneComposer` ưu tiên **giữ người
/// ở giữa khung**, và phần tránh vật cản để dành cho bản sau khi có đo phòng.
nonisolated struct SceneComposer {

    /// Kết quả bố cục mà app đề xuất.
    nonisolated struct Layout: Equatable {
        /// Tâm người 3D trên khung, chuẩn hoá 0...1 (gốc trên-trái).
        var subjectCenter: CGPoint
        /// Mức zoom máy nên dùng (1.0 = không zoom).
        var suggestedZoom: CGFloat
        /// Bề rộng thân, chuẩn hoá theo **chiều ngang** khung.
        var subjectWidthRatio: CGFloat
        /// Chiều cao đầu, chuẩn hoá theo **chiều cao** khung.
        ///
        /// - Important: hai đại lượng này chuẩn hoá theo **hai trục khác nhau**, nên
        ///   không được chia lẫn. Khung 3:4 cao hơn rộng, dùng nhầm sẽ ra con số
        ///   sai lệch khoảng 30%.
        var headHeightRatio: CGFloat
        /// Người 3D có chạm bàn ghế ảo không.
        var usesTable: Bool
    }

    // MARK: - Giới hạn zoom

    /// Zoom nhỏ nhất — dưới mức này ảnh nhiễu vì crop quá nhiều từ cảm biến.
    nonisolated static let minimumZoom: CGFloat = 1.0
    /// Zoom lớn nhất.
    ///
    /// - Important: không cho vượt 2x. Zoom quá tay thì ảnh mất chi tiết, và nhiếp
    ///   ảnh gia không chụp chân dung bằng tele 5x — họ bước gần thay vì zoom.
    nonisolated static let maximumZoom: CGFloat = 2.0

    // MARK: - Bố cục

    /// Tính bố cục cho một tư thế.
    ///
    /// - Parameters:
    ///   - pose: tư thế người dùng đã chọn.
    ///   - viewport: kích thước khung hiển thị.
    ///   - availableDepth: khoảng cách lớn nhất app ước lượng được, đơn vị mét.
    ///     `nil` = không đo được (chưa quét phòng) — coi như có chỗ.
    ///   - currentZoom: mức zoom đang dùng, để tránh nhảy giật.
    static func layout(
        pose: ShootingPose,
        viewport: CGSize,
        availableDepth: CGFloat? = nil,
        currentZoom: CGFloat = 1.0
    ) -> Layout? {
        guard viewport.width > 0, viewport.height > 0 else { return nil }

        // Chiều cao đầu mong muốn chuẩn hoá theo chiều cao khung.
        let headHeightRatio = pose.headHeightRatio
        // Bề vai suy từ chiều cao đầu, chuẩn hoá theo chiều ngang khung.
        let subjectWidthRatio = headHeightRatio * viewport.height
            * BodyCanon.Width.shoulder / viewport.width

        // Vị trí tâm: khoảng cách lạc quan giữa đường mắt và tâm thân.
        let eyeY = pose.eyeLineRatio
        let bodyY = pose.bodyCenterY
        let centerY = (eyeY + bodyY) / 2

        return Layout(
            subjectCenter: CGPoint(x: 0.5, y: centerY),
            suggestedZoom: suggestedZoom(
                pose: pose,
                viewport: viewport,
                availableDepth: availableDepth,
                currentZoom: currentZoom
            ),
            subjectWidthRatio: subjectWidthRatio,
            headHeightRatio: headHeightRatio,
            usesTable: pose.usesTable
        )
    }

    // MARK: - Zoom

    /// Mức zoom cần để đạt **khoảng cách đứng** của tư thế.
    ///
    /// ## Vì sao cần zoom thay vì bắt người mẫu lùi
    ///
    /// Ở phòng chật — quán cà phê, phòng khách nhỏ — chỗ đứng đúng khoảng cách
    /// **không tồn tại trong phòng**. Người mẫu không thể lùi thêm 2 mét.
    ///
    /// Zoom khác bước lùi ở đúng một điểm quan trọng: **zoom giữ nguyên kích thước
    /// người trong khung** và chỉ thu hẹp trường nhìn. Người mẫu đứng yên, chỉ
    /// chỉnh zoom — đúng tinh thần "không đau đầu".
    ///
    /// Đổi lại: nền bị cắt, đường thẳng trong ảnh bị cắt thành đoạn. Vì vậy
    /// phải **giới hạn trần** thay vì cho zoom tới hết.
    static func suggestedZoom(
        pose: ShootingPose,
        viewport: CGSize,
        availableDepth: CGFloat?,
        currentZoom: CGFloat
    ) -> CGFloat {
        guard viewport.width > 0, availableDepth != nil else {
            // Chưa đo được phòng — giữ nguyên mức hiện tại, đừng đoán bừa.
            return min(max(currentZoom, minimumZoom), maximumZoom)
        }

        let depth = max(availableDepth ?? 0, 0.5)
        let headHeightMeters = BodyPoseReference.typicalHeadHeight
        let wantedDistance = pose.standoffInHeads * headHeightMeters

        // Khoảng cách đang có nhỏ hơn khoảng cách muốn thì phải zoom vào.
        guard depth < wantedDistance else {
            return minimumZoom
        }

        // Zoom theo đúng tỉ lệ khoảng cách.
        //
        // - Important: đây là ước lượng bậc nhất, chưa hiệu chỉnh độ méo ống kính
        //   và chưa biết tỉ lệ cắt của khung. Chấp nhận sai số vì sai số chỉ làm
        //   ảnh hơi xa/gần, còn người mẫu vẫn tự chỉnh được. Hệ số bịa ra thì
        //   mới là thứ không kiểm chứng được.
        let raw = wantedDistance / depth
        return min(max(raw, minimumZoom), maximumZoom)
    }
}

/// Số đo hình thể dùng chung cho các phần quy đổi mét ↔ tỉ lệ ảnh.
nonisolated enum BodyPoseReference {
    /// Chiều cao đầu trung bình của người trưởng thành, tính cả tóc.
    ///
    /// Khoảng 1/7.5 tổng chiều cao; với người cao 1,7m thì khoảng 0,23m. Giá trị
    /// này **có tham số hoá** theo chiều cao người dùng khai — xem `UserHeight`.
    static let typicalHeadHeight: CGFloat = 0.23

    /// Quy đổi chiều cao người (mét) sang chiều cao đầu tương ứng.
    static func headHeight(forUserHeight meters: CGFloat) -> CGFloat {
        let clamped = min(max(meters, 1.2), 2.2)
        return clamped / BodyCanon.totalHeightInHeads
    }
}