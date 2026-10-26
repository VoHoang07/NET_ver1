import Foundation
import RealityKit
import UIKit

/// Vật liệu mờ cho người 3D và bàn ghế ảo.
///
/// ## Vì sao tách riêng
///
/// Cùng một vật liệu dùng cho người và bàn, khác nhau ở độ đục. Gộp chỗ này thì
/// đổi độ mờ một lần, không phải sửa hai file.
enum FigureMaterial {

    /// Màu da người ấm áp khi đang hướng dẫn đứng vào khung.
    ///
    /// - Important: giữ sắc độ ấm (R > G > B rõ rệt) để vừa mang cảm giác lớp da người
    ///   mềm mại trên nền camera, vừa tương phản tốt trên cả nền sáng lẫn tối.
    static let guide = UIColor(red: 0.96, green: 0.54, blue: 0.34, alpha: 1)
    /// Màu khi đã đúng vị trí — xanh lá.
    static let aligned = UIColor(red: 0.24, green: 0.78, blue: 0.45, alpha: 1)

    /// Độ đục của lớp da người khi chưa đúng vị trí — đủ rõ khối cơ thể liền mạch
    /// nhưng vẫn nhìn xuyên nhẹ qua bối cảnh thật phía sau.
    static let alphaWhenGuiding: CGFloat = 0.58
    /// Khi đã đúng vị trí, mờ thêm để **không che khuôn mặt** người thật.
    static let alphaWhenAligned: CGFloat = 0.18

    /// Vật liệu lớp da bán trong suốt cho người mẫu 3D.
    ///
    /// - Important: KHÔNG dùng `UnlitMaterial`. "Unlit" nghĩa là **không nhận
    ///   ánh sáng**: mọi mặt của hình khối cùng một màu, không mặt nào sáng hơn mặt
    ///   nào. Quả cầu không bóng trông y như hình tròn phẳng dán lên — đúng loại
    ///   "không phải 3D" mà người dùng phản ánh.
    ///
    ///   `PhysicallyBasedMaterial` có phản xạ ánh sáng nên mặt hướng về nguồn sáng
    ///   sáng hơn, hình khối có khối và đọc ra khối cơ thể người.
    @MainActor
    static func make(isAligned: Bool, dimmed: Bool = false) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        let alpha = (dimmed || isAligned) ? alphaWhenAligned : alphaWhenGuiding
        let base = isAligned ? aligned : guide

        material.baseColor = .init(tint: base.withAlphaComponent(alpha))
        material.blending = .transparent(opacity: .init(floatLiteral: 1.0))
        // Loại bỏ mặt sau để khi bán trong suốt không bị nhìn xuyên thấy mặt lưng bên trong.
        material.faceCulling = .back
        // Độ nhám cao giúp bề mặt da mịn màng, triệt tiêu các vệt bóng gắt dọc theo lưới đa giác.
        material.roughness = .init(floatLiteral: 0.78)
        material.metallic = .init(floatLiteral: 0.0)
        material.clearcoat = .init(floatLiteral: 0.02)
        material.clearcoatRoughness = .init(floatLiteral: 0.65)
        return material
    }

    /// Áp vật liệu cho một entity và **mọi** hình con của nó.
    ///
    /// - Important: không dùng `forEachDescendant` — API đó không có trong RealityKit
    ///   bản iOS 17, chỉ xuất hiện ở bản mới hơn. Duyệt `children` bằng đệ quy chạy
    ///   được mọi phiên bản, và với vài chục hình khối thì chẳng tốn gì.
    ///
    /// `Entity.components` và `Entity.children` đều là `@MainActor`, nên hàm này
    /// phải ở main actor — đúng chỗ cảnh RealityKit được dựng và cập nhật.
    ///
    /// - Important: với model có xương, phần **da** (mesh) và phần **xương** (joints)
    ///   là hai prim riêng trong USDZ. Chỉ thay vật liệu cho model đang xét sẽ bỏ
    ///   sót `Beta_Joints`, và khúc xương đó hiện lên với màu gốc đậm đục — người
    ///   3D lại thành búp bê đặc. Vì vậy phải duyệt cả cây.
    @MainActor
    static func apply(to entity: Entity, isAligned: Bool, dimmed: Bool = false) {
        let material = make(isAligned: isAligned, dimmed: dimmed)

        if var model = entity.components[ModelComponent.self] {
            model.materials = [material]
            entity.components.set(model)
        }
        for child in entity.children {
            apply(to: child, isAligned: isAligned, dimmed: dimmed)
        }
    }
}