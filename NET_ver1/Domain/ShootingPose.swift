import CoreGraphics
import Foundation

/// Một tư thế người mẫu có thể chọn.
///
/// ## Vì sao chỉ 6 tư thế
///
/// Mỗi tư thế cần một mô hình 3D riêng. Làm nhiều mà làm dở thì tệ hơn không
/// có — người mẫu thấy một dáng sai thì mất lòng tin cả app. Sáu tư thế đủ cho
/// phần lớn tình huống chụp một người.
///
/// ## Ba nguyên tắc đã lọc các tư thế
///
/// 1. **Máy đo được** — Vision phải chấm được, không thì app chỉ hướng dẫn chứ
///    không chấm. Thế nên "tựa vào tường" bị lo: app không biết tường ở đâu.
/// 2. **Người mẫu làm nhanh** — đứng yên, không bắt dữ, không ngại.
/// 3. **Đổi hình dáng** — dáng đứng thẳng luôn giống nhau, dáng ngồi nghiêng thì
///    cho ảnh có chiều sâu.
nonisolated struct ShootingPose: Identifiable, Equatable, Hashable {
    /// Nhóm tư thế — quyết định người 3D có bàn ghế ảo hay không.
    nonisolated enum Stance: String, Equatable, Hashable {
        /// Ngồi sau bàn, tay chống lên mặt bàn.
        case seated
        /// Đứng tự do.
        case standing

        var title: String {
            switch self {
            case .seated: "Ngồi"
            case .standing: "Đứng"
            }
        }
    }

    let id: String
    let title: String
    /// Câu ngắn gợi ý cho người mẫu, hiện ngay trên khung.
    let cue: String
    let stance: Stance

    /// Nghiêng người mong muốn (độ). Dương = vai phải thấp hơn vai trái.
    ///
    /// Đây là thứ cho ảnh có chiều sâu: vai bằng nhau nhìn phẳng và nhạt.
    let shoulderTilt: CGFloat

    /// Nghiêng trục thân mong muốn (độ). Dương = nghiêng sang phải.
    let spineTilt: CGFloat

    /// Người 3D có quay đầu sang một bên không (không có mặt chi tiết nên đầu
    /// nghiêng tạo cảm giác đang nhìn cói).
    let headTurn: CGFloat

    /// Vị trí tâm người trên khung, đo từ trên xuống (0...1).
    ///
    /// - Important: đường mắt nên ở **1/3 chiều cao khung** — quy tắc cổ điển,
    ///   và là thứ làm cho phần trên khung thoáng, phần dưới nặng.
    let bodyCenterY: CGFloat

    /// Khoảng cách máy so với người, tính bằng số lần chiều cao đầu.
    ///
    /// Khoảng cách này quyết định **mức zoom** cần dùng — nên khi phòng không đủ
    /// chỗ lùi, app bù lại bằng zoom thay vì bắt người mẫu đi xa.
    let standoffInHeads: CGFloat

    /// Người 3D có dựa tay vào bàn không — tạo cảm giác "đang ngồi ở quán"
    /// thay vì "đang bị đặt vào khung hình".
    let usesTable: Bool

    // MARK: - Danh mục

    static let seatedStraight = ShootingPose(
        id: "seated-straight",
        title: "Ngồi thẳng",
        cue: "Thẳng lưng, tay đặt trên bàn",
        stance: .seated,
        shoulderTilt: 0,
        spineTilt: 0,
        headTurn: 0,
        bodyCenterY: 0.62,
        standoffInHeads: 7,
        usesTable: true
    )

    static let seatedChinRest = ShootingPose(
        id: "seated-chin",
        title: "Tay chống cằm",
        cue: "Một tay đặt cằm, tay kia trên bàn",
        stance: .seated,
        shoulderTilt: 4,
        spineTilt: 2,
        headTurn: 8,
        bodyCenterY: 0.62,
        standoffInHeads: 6,
        usesTable: true
    )

    static let seatedLean = ShootingPose(
        id: "seated-lean",
        title: "Nghiêng vai",
        cue: "Nghiêng người sang một bên, vai hạ xuống",
        stance: .seated,
        shoulderTilt: 14,
        spineTilt: 9,
        headTurn: -6,
        bodyCenterY: 0.62,
        standoffInHeads: 6,
        usesTable: true
    )

    static let standingStraight = ShootingPose(
        id: "standing-straight",
        title: "Đứng thẳng",
        cue: "Hai chân, tay tự nhiên",
        stance: .standing,
        shoulderTilt: 0,
        spineTilt: 0,
        headTurn: 0,
        bodyCenterY: 0.55,
        standoffInHeads: 8,
        usesTable: false
    )

    static let standingHandOnHip = ShootingPose(
        id: "standing-hip",
        title: "Chống hông",
        cue: "Một tay chống hông, nghiêng nhẹ",
        stance: .standing,
        shoulderTilt: 11,
        spineTilt: 7,
        headTurn: 5,
        bodyCenterY: 0.55,
        standoffInHeads: 7,
        usesTable: false
    )

    static let standingLookAside = ShootingPose(
        id: "standing-aside",
        title: "Nhìn qua vai",
        cue: "Quay đầu sang bên, mặt gần chếch",
        stance: .standing,
        shoulderTilt: 7,
        spineTilt: 3,
        headTurn: 22,
        bodyCenterY: 0.55,
        standoffInHeads: 6.5,
        usesTable: false
    )

    /// Sáu tư thế, đúng thứ tự hiện trong UI.
    static let all: [ShootingPose] = [
        .seatedStraight, .seatedChinRest, .seatedLean,
        .standingStraight, .standingHandOnHip, .standingLookAside,
    ]

    static func pose(id: String) -> ShootingPose {
        all.first { $0.id == id } ?? .seatedStraight
    }

    // MARK: - Khoảng cách

    /// Chiều cao đầu mong muốn, tính theo chiều cao khung hiển thị.
    ///
    /// Khoảng **1/3 chiều cao khung cho chiều cao đầu** là chuẩn chân dung — đầu
    /// chiếm 1/3 chiều cao, mắt rơi vào đường 1/3 từ trên, còn lại là thân.
    /// Dùng chung một quy tắc cho cả ngồi lẫn đứng để app nhất quán.
    var headHeightRatio: CGFloat { 0.17 }

    /// Vị trí đường mắt mong muốn.
    var eyeLineRatio: CGFloat { 1.0 / 3.0 }

    /// Góc nhìn dọc của camera 3D, tính bằng độ.
    ///
    /// - Important: hằng số này giờ được **gán tường minh** lên camera ở cả hai nhánh
    ///   dựng cảnh, dù mặc định của `PerspectiveCamera` vốn đã là 60° (đọc từ
    ///   `PerspectiveCameraComponent.init` trong RealityFoundation).
    ///
    ///   Trước đây nó chỉ nằm ở đây và được giả thiết là khớp mặc định — tức công
    ///   thức và hình ảnh phụ thuộc vào một mặc định của thư viện ngoài tầm kiểm soát.
    ///   Đặt tường minh thì hai bên luôn khớp, kể cả khi thư viện đổi mặc định.
    ///
    ///   Bài học kèm theo: đừng kết luận "mặc định là 50°" chỉ từ trí nhớ. Lần này
    ///   đã đoán sai rồi phải đọc lại `swiftinterface` mới đúng — cùng kiểu lỗi đã
    ///   gặp nhiều lần với metadata USD.
    static let verticalFieldOfView: CGFloat = 60

    /// Phần chiều cao người được phép chiếm trong khung hình.
    ///
    /// 0,62 giúp toàn thân người mẫu (từ đỉnh đầu tới bàn chân) nằm trọn trong vùng
    /// khung ngắm trống (từ 16% đến 76% chiều cao màn hình), không bao giờ đè lên
    /// thanh công cụ phía trên hay hàng nút chụp phía dưới.
    static let frameFillRatio: CGFloat = 0.58

    /// Khoảng cách máy so với người, tính bằng mét.
    ///
    /// - Important: tính từ **chiều cao người**, không dùng `standoffInHeads`.
    ///
    ///   `standoffInHeads × chiều cao đầu` cho 7 × 0,227 = **1,59 m**, và với FOV 60°
    ///   thì người cao 1,80 m chiếm **118%** chiều cao khung — bị cắt mất cả đầu lẫn
    ///   chân. Đây là một trong những nguyên nhân khiến người 3D tràn khung hình.
    ///
    ///   Khoảng cách chọn để người **cao nhất** trong sáu tư thế vừa đúng
    ///   `frameFillRatio`; tư thế thấp hơn sẽ lùi tương ứng, không tràn.
    var cameraDistance: CGFloat {
        let halfFov = tan(Double(Self.verticalFieldOfView) / 2 * .pi / 180)
        return (FigureAssetLoader.referenceHeight / Self.frameFillRatio) / (2 * halfFov)
    }
}