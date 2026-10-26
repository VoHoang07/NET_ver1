import CoreGraphics
import Foundation

/// Ánh xạ toạ độ giữa khung hiển thị và khung ảnh thật mà camera ghi vào.
///
/// ## Vì sao cần lớp này
///
/// Khung hiển thị (view) và buffer camera có tỉ lệ khác nhau. Khi preview dùng
/// `.resizeAspectFill`, camera **giữ nguyên** toàn bộ ảnh rồi **cắt bớt** phần
/// thừa để lấp đầy khung hiển thị. Ví dụ khung hiển thị 3:4 với buffer 4:3 thì
/// mỗi bên bị cắt ~21.9%.
///
/// Hệ quả: vị trí 78% chiều ngang trong ảnh thật sẽ hiển thị ở 87% trên màn
/// hình. Nếu dựng khuôn theo khung hiển thị mà so với bbox Vision (đo trên ảnh
/// thật) thì khuôn sẽ lệch — người mẫu đứng đúng khuôn vẫn bị báo sai.
///
/// Lớp này gom phép tính cắt vào một chỗ để mọi nơi khác chỉ cần gọi
/// `viewPoint(fromVisionPoint:)`.
///
/// ## Hệ toạ độ
///
/// - **Vision**: chuẩn hoá 0...1, gốc tại **đáy-trái** (trục Y hướng lên), phủ
///   toàn bộ ảnh gốc.
/// - **View**: chuẩn hoá 0...1, gốc tại **trên-trái** (trục Y hướng xuống), phủ
///   phần ảnh **còn lại sau khi cắt**.
nonisolated struct SafeArea: Equatable {
    /// Kích thước khung hiển thị, đã tính theo hướng dọc sau khi xoay.
    let viewSize: CGSize
    /// Kích thước buffer camera, đã tính theo hướng dọc sau khi xoay.
    let bufferSize: CGSize
    /// Tỉ lệ phần bị cắt mỗi bên, theo phần trăm kích thước buffer (0...0.5).
    let horizontalCrop: CGFloat
    let verticalCrop: CGFloat

    /// - Parameters:
    ///   - viewSize: kích thước khung hiển thị sau khi xoay.
    ///   - bufferSize: kích thước buffer camera sau khi xoay.
    ///   - fillsView: `true` khi preview dùng `.resizeAspectFill` (cắt phần thừa),
    ///     `false` khi dùng `.resizeAspect` / `.resizeAspectFit` (vừa khung, có viền).
    init(viewSize: CGSize, bufferSize: CGSize, fillsView: Bool = true) {
        self.viewSize = viewSize
        self.bufferSize = bufferSize

        guard fillsView, viewSize.width > 0, viewSize.height > 0,
              bufferSize.width > 0, bufferSize.height > 0 else {
            horizontalCrop = 0
            verticalCrop = 0
            return
        }

        let viewAspect = viewSize.width / viewSize.height
        let bufferAspect = bufferSize.width / bufferSize.height

        if viewAspect > bufferAspect {
            // Khung hiển thị rộng hơn buffer -> cắt trên và dưới.
            let visibleHeight = bufferSize.width / viewAspect
            verticalCrop = (bufferSize.height - visibleHeight) / 2 / bufferSize.height
            horizontalCrop = 0
        } else {
            // Khung hiển thị hẹp hơn buffer -> cắt hai bên trái/phải.
            let visibleWidth = bufferSize.height * viewAspect
            horizontalCrop = (bufferSize.width - visibleWidth) / 2 / bufferSize.width
            verticalCrop = 0
        }
    }

    /// Tỉ lệ phần ảnh còn lại so với buffer ban đầu.
    var visibleWidthRatio: CGFloat { 1 - horizontalCrop * 2 }
    var visibleHeightRatio: CGFloat { 1 - verticalCrop * 2 }

    /// Đổi một điểm chuẩn hoá của Vision (gốc đáy-trái, toàn ảnh) sang
    /// toạ độ chuẩn hoá của khung hiển thị (gốc trên-trái, phần ảnh còn lại).
    func viewPoint(fromVisionPoint point: CGPoint) -> CGPoint {
        let x = (point.x - horizontalCrop) / visibleWidthRatio
        // Vision đo từ đáy lên, khung hiển thị đo từ trên xuống.
        let yFromBottom = (point.y - verticalCrop) / visibleHeightRatio
        return CGPoint(x: x, y: 1 - yFromBottom)
    }

    /// Đổi một hình chữ nhật chuẩn hoá của Vision sang toạ độ khung hiển thị.
    func viewRect(fromVisionRect rect: CGRect) -> CGRect {
        let x = (rect.minX - horizontalCrop) / visibleWidthRatio
        let width = rect.width / visibleWidthRatio

        // Lật cả chuỗi đoạn, không chỉ điểm đầu: Vision đo `minY` từ đáy lên,
        // nên cạnh trên của hình chữ nhật là `minY + height`, không phải `minY`.
        let topFromBottom = rect.minY + rect.height
        let top = 1 - (topFromBottom - verticalCrop) / visibleHeightRatio

        return CGRect(x: x, y: top, width: width, height: rect.height / visibleHeightRatio)
    }
}

extension CGSize {
    /// Kích thước sau khi áp dụng góc xoay của camera (bằng độ, chỉ tính 0/90/180/270).
    func rotated(byDegrees degrees: Int) -> CGSize {
        switch degrees.modulo(360) {
        case 90, 270:
            return CGSize(width: height, height: width)
        default:
            return self
        }
    }
}

private extension Int {
    func modulo(_ divisor: Int) -> Int {
        let result = self % divisor
        return result >= 0 ? result : result + divisor
    }
}
