import CoreGraphics
import Foundation
import ImageIO
import os

/// Thông số cần cho một lần phân tích khung hình.
///
/// Được đóng gói thành hộp `Sendable` để **đọc được từ mọi thread** mà không cần
/// chạm vào main actor. `FrameAnalyzer` chạy trên `analysisQueue`, nên nếu đọc
/// trực tiếp `@Published var` của main actor thì không an toàn.
///
/// Main actor sở hữu hộp này và **ghi** vào nó; các thread khác chỉ **đọc**.
nonisolated struct AnalysisConfiguration: Sendable {
    var mode: CaptureMode
    var viewportSize: CGSize
    /// Hướng của buffer camera so với màn hình.
    var orientation: CGImagePropertyOrientation

    init(
        mode: CaptureMode = .solo,
        viewportSize: CGSize = .zero,
        orientation: CGImagePropertyOrientation = .right
    ) {
        self.mode = mode
        self.viewportSize = viewportSize
        self.orientation = orientation
    }

    /// Có cần đo độ bận nền không — chỉ bật khi thật sự dùng tới tiêu chí này
    /// vì `VNGeneratePersonSegmentationRequest` tốn kém nhất trong các request.
    var needsBackgroundAnalysis: Bool {
        !mode.usesBodyTemplate
    }
}

/// Cầu nối giữa main actor và queue phân tích.
///
/// Ghi từ main actor, đọc từ bất kỳ thread nào. Dùng `OSAllocatedUnfairLock` vì
/// đọc diễn ra ở tần suống cao (mỗi lần phân tích) — khoá unfair lock rẻ hơn
/// nhiều so với `DispatchQueue.sync`, và việc chờ không đáng kể vì critical
/// section chỉ gán ba giá trị.
nonisolated final class AnalysisConfigurationStore: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: AnalysisConfiguration())
    private var state: AnalysisConfiguration {
        get { lock.withLock { $0 } }
        set { lock.withLock { $0 = newValue } }
    }

    var current: AnalysisConfiguration { state }

    func update(_ transform: @Sendable (inout AnalysisConfiguration) -> Void) {
        lock.withLock { state in
            transform(&state)
        }
    }
}
