import CoreGraphics
import Foundation

/// Khuôn người mẫu cho từng `CaptureMode`.
///
/// Mọi toạ độ đều là **tỉ lệ chuẩn hoá 0...1 theo khung hiển thị** (gốc trên-trái),
/// nên khuôn tự co giãn theo mọi kích thước khung mà không cần asset.
nonisolated struct PoseTemplate: Equatable {
    /// Chiều cao đầu / chiều cao khung. 0.17 → mắt rơi vào đường 1/3 từ trên.
    let headHeightRatio: CGFloat
    /// Vị trí đường mắt / chiều cao khung tính từ trên xuống.
    let eyeLineRatio: CGFloat
    /// Bề vai / chiều ngang khung.
    let shoulderWidthRatio: CGFloat
    /// Độ lệch ngang tối đa cho phép, tính theo nửa bề ngang khung.
    /// Bất đối xứng nhẹ tự nhiên hơn nên không cần bằng tuyệt đối.
    let horizontalSlack: CGFloat
    /// Độ cho phép cắt đầu (khi đỉnh đầu vượt lên khung).
    let topHeadSlack: CGFloat
    /// Vùng chịu sai lệch, tính theo chiều cao đầu.
    /// Trong vùng này không báo lỗi — tránh nhấp nháy liên tục.
    let headTolerance: CGFloat

    /// Vị trí đỉnh đầu tính từ trên xuống.
    ///
    /// Mắt nằm giữa đỉnh đầu và cằm (`BodyCanon.Marker.eyeLine` = 0.5H), nên đỉnh
    /// đầu phải nằm **phía trên** đường mắt một nửa chiều cao đầu.
    var topOfHeadRatio: CGFloat {
        eyeLineRatio - headHeightRatio * BodyCanon.Marker.eyeLine.heightFromTop
    }

    /// Vị trí cằm tính từ trên xuống.
    var chinRatio: CGFloat {
        topOfHeadRatio + headHeightRatio * BodyCanon.Marker.chin.heightFromTop
    }

    /// Vị trí vai tính từ trên xuống.
    var shoulderRatio: CGFloat {
        topOfHeadRatio + headHeightRatio * BodyCanon.Marker.shoulder.heightFromTop
    }

    /// Vị trí hông tính từ trên xuống.
    var hipRatio: CGFloat {
        topOfHeadRatio + headHeightRatio * BodyCanon.Marker.hip.heightFromTop
    }

    /// Vị trí ngực tính từ trên xuống.
    var chestRatio: CGFloat {
        topOfHeadRatio + headHeightRatio * BodyCanon.Marker.chest.heightFromTop
    }

    /// Bề ngang đầu / chiều ngang khung.
    var headWidthRatio: CGFloat {
        headHeightRatio * BodyCanon.Width.head
    }

    /// Đáy khuôn hướng dẫn, tính từ trên xuống.
    ///
    /// - Important: **không** dùng `hipRatio` cho khuôn. hông nằm ở 0.93 khiến
    ///   góc ngoặc dưới sát đáy khung, người mẫu không tìm được chỗ đứng.
    ///   Ngắn lại ở ngực để khuôn gọn và canh được.
    var guideBottomRatio: CGFloat {
        chestRatio + headHeightRatio * 0.6
    }

    static let portrait = PoseTemplate(
        headHeightRatio: 0.17,
        eyeLineRatio: 1.0 / 3.0,
        shoulderWidthRatio: 0.45,
        horizontalSlack: 0.03,
        topHeadSlack: 0.01,
        headTolerance: 0.012
    )

    /// Cặp đôi: đứng sát hơn nên vai rộng hơn một chút, nhưng vẫn chừa
    /// khoảng thở để sau này chỉnh thoải mái.
    static let couple = PoseTemplate(
        headHeightRatio: 0.17,
        eyeLineRatio: 1.0 / 3.0,
        shoulderWidthRatio: 0.62,
        horizontalSlack: 0.04,
        topHeadSlack: 0.01,
        headTolerance: 0.014
    )

    /// Nhóm: nhìn từ xa nên đầu nhỏ hơn, mắt vẫn giữ trên đường 1/3.
    static let group = PoseTemplate(
        headHeightRatio: 0.14,
        eyeLineRatio: 1.0 / 3.0,
        shoulderWidthRatio: 0.70,
        horizontalSlack: 0.05,
        topHeadSlack: 0.01,
        headTolerance: 0.016
    )

    static func template(for mode: CaptureMode) -> PoseTemplate? {
        switch mode {
        case .solo: portrait
        case .couple: couple
        case .group: group
        case .object: nil
        }
    }
}
