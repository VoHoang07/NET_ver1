import CoreGraphics
import Foundation

/// Kích thước thân người, tính bằng **chiều cao đầu**.
///
/// ## Vì sao tính bằng đầu
///
/// Nhân thân chuẩn người lớn viết bằng "7,5 đầu" — tức chiều cao người bằng 7,5
/// lần chiều cao đầu. Dùng đơn vị này thì **mọi tư thế dùng chung một hệ số**, không
/// phải đo từng người.
///
/// Với người cao 1,7m thì một đầu ≈ 0,227m. Người cao 1,95m thì ≈ 0,26m — cùng
/// bộ hình khối, chỉ scale theo chiều cao thật.
nonisolated enum FigureBuild {
    /// Số đầu trong một chiều cao người trưởng thành.
    nonisolated static let totalHeads: CGFloat = 7.5

    /// Vị trí các mốc, tính theo chiều cao đầu, **đo từ đỉnh đầu xuống**.
    ///
    /// Mọi con số đều là giá trị trung bình của người trưởng thành. Sai vài phần
    /// trăm không ai nhận ra — nhưng sai cả mét thì nhìn là ra ngay.
    nonisolated enum Heads {
        /// Đỉnh đầu.
        static let crown: CGFloat = 0
        /// Đường mắt.
        static let eyeLine: CGFloat = 1.0
        /// Cằm.
        static let chin: CGFloat = 1.25
        /// Vai.
        static let shoulder: CGFloat = 1.5
        /// Ngực.
        static let chest: CGFloat = 2.4
        /// Eo.
        static let waist: CGFloat = 3.2
        /// Hông.
        static let hip: CGFloat = 4.0
        /// Gối.
        static let knee: CGFloat = 5.5
        /// Mắt cá.
        static let ankle: CGFloat = 7.25
    }

    /// Bề rộng thân, tính theo chiều cao đầu.
    nonisolated enum Width {
        /// Vai — bề rộng lớn nhất, đây là mốc định nghĩa cho mọi tỉ lệ khác.
        static let shoulder: CGFloat = 1.6
        /// Eo.
        static let waist: CGFloat = 1.05
        /// Hông.
        static let hip: CGFloat = 1.25
        /// Đầu.
        static let head: CGFloat = 0.72
        /// Độ dày thân, tính theo chiều cao đầu (người nhìn nghiêng 3/4).
        static let depth: CGFloat = 0.62
    }
}

// MARK: - Số đo cho một tư thế

/// Bộ số đo 3D của một tư thế: các mốc trong **không gian 3D**, đơn vị mét.
nonisolated struct FigureMetrics: Equatable {
    /// Chiều cao đầu, tính bằng mét.
    let headHeight: CGFloat
    /// Độ nghiêng vai (độ), quanh trục Z — nghiêng sang một bên.
    let shoulderRoll: CGFloat
    /// Độ xoay thân (độ), quanh trục Y.
    let bodyYaw: CGFloat
    /// Độ nghiêng cằm (độ).
    let headPitch: CGFloat
    /// Độ xoay đầu (độ).
    let headYaw: CGFloat
    /// Cánh tay có chạm bàn không.
    let armsRestOnTable: Bool

    /// Đổi mốc tính theo "số đầu" sang mét, đo từ đỉnh đầu xuống.
    func meters(fromCrown heads: CGFloat) -> CGFloat {
        heads * headHeight
    }

    /// Vị trí theo ba trục, quy về **RealityKit** (Y lên, camera nhìn từ -Z).
    ///
    /// - Important: trục Y của RealityKit hướng **lên**, khác với toạ độ ảnh của
    ///   Vision (Y hướng lên nhưng gốc ở đáy). Ở đây Y = 0 là **mặt đất**, và
    ///   `crown` có Y bằng tổng chiều cao — không phải 0. Nếu đặt đỉnh đầu ở Y = 0
    ///   thì người sẽ nằm ngửa dưới sàn.
    func position(of heads: CGFloat, lateralOffset: CGFloat = 0) -> SIMD3<Float> {
        let height = meters(fromCrown: heads)
        let totalHeight = meters(fromCrown: FigureBuild.Heads.ankle)
        return SIMD3<Float>(
            Float(lateralOffset),
            Float(totalHeight - height),
            0
        )
    }
}

// MARK: - Dựng từ tư thế

nonisolated extension ShootingPose {
    /// Suy ra bộ số đo 3D từ tư thế đã chọn.
    ///
    /// - Parameters:
    ///   - userHeight: chiều cao người mẫu. `nil` thì dùng giá trị trung bình.
    func metrics(userHeight: CGFloat?) -> FigureMetrics {
        let head = BodyPoseReference.headHeight(forUserHeight: userHeight ?? 1.70)

        return FigureMetrics(
            headHeight: head,
            shoulderRoll: shoulderTilt,
            bodyYaw: 0,
            headPitch: headTurn > 15 ? -6 : 0,
            headYaw: headTurn,
            armsRestOnTable: usesTable
        )
    }
}