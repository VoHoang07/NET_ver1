import CoreGraphics
import Foundation

/// Nhân thân chuẩn (canon), đơn vị H = chiều cao đầu.
///
/// Người trưởng thành cao khoảng 7.5 thân (tính cả chiều cao đầu). Các mốc
/// dưới đây theo truyền thống nhiếp ảnh — dùng để dựng khuôn người mẫu và để
/// chấm tư thế, nên phải là hằng số, không nhúng số vào nơi khác.
nonisolated enum BodyCanon {
    /// Toàn bộ chiều cao người tính theo đơn vị đầu.
    static let totalHeightInHeads: CGFloat = 7.5

    enum Marker: CaseIterable {
        case topOfHead      // 0.0
        case eyeLine        // 0.5 — nằm giữa đỉnh đầu và cằm
        case chin           // 1.0
        case shoulder       // 1.5
        case chest          // 2.0
        case navel          // 3.0
        case hip            // 4.0
        case knee           // 6.0
        case foot           // 7.5

        /// Vị trí dọc tính từ đỉnh đầu, đơn vị H.
        var heightFromTop: CGFloat {
            switch self {
            case .topOfHead: 0
            case .eyeLine: 0.5
            case .chin: 1.0
            case .shoulder: 1.5
            case .chest: 2.0
            case .navel: 3.0
            case .hip: 4.0
            case .knee: 6.0
            case .foot: 7.5
            }
        }
    }

    /// Bề rộng tương đối, đơn vị H.
    enum Width {
        static let head: CGFloat = 0.72
        static let shoulder: CGFloat = 2.0
        static let hip: CGFloat = 1.45

        /// Tỉ số bề vai so với chiều ngang đầu. Chuẩn thường nằm trong khoảng 2.5–3.
        static var shoulderToHeadRatio: CGFloat { shoulder / head }
    }

    /// Nhân số đổi từ H sang chiều cao khung: 1 người cao `totalHeightInHeads` H.
    static func heightMultiplier(headHeight: CGFloat) -> CGFloat {
        totalHeightInHeads * headHeight
    }
}
