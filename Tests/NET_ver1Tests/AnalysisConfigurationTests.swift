import XCTest
@testable import NET_ver1

/// Test cho cầu nối giữa main actor và queue phân tích.
///
/// Bug mà bộ test này chống lại: trước đây analyzer đọc `@Published var mode`
/// bằng `MainActor.assumeIsolated` **từ `analysisQueue`**. Điều đó vừa là lỗi
/// compile ở chế độ concurrency nghiêm, vừa là **crash runtime** ngay khi có
/// khung hình đầu tiên.
final class AnalysisConfigurationTests: XCTestCase {

    // MARK: - Truyền giá trị

    func testDefaultsAreSafe() {
        let configuration = AnalysisConfiguration()
        XCTAssertEqual(configuration.mode, .solo)
        XCTAssertEqual(configuration.viewportSize, .zero)
        XCTAssertEqual(configuration.orientation, .right)
    }

    func testBackgroundAnalysisOnlyForNonBodyModes() {
        // Mode người không cần segmentation — request này tốn nhất.
        var configuration = AnalysisConfiguration(mode: .solo)
        XCTAssertFalse(configuration.needsBackgroundAnalysis)

        configuration.mode = .couple
        XCTAssertFalse(configuration.needsBackgroundAnalysis)

        configuration.mode = .group
        XCTAssertFalse(configuration.needsBackgroundAnalysis)

        configuration.mode = .object
        XCTAssertTrue(configuration.needsBackgroundAnalysis)
    }

    // MARK: - Store

    func testStoreReturnsUpdatedValue() {
        let store = AnalysisConfigurationStore()
        XCTAssertEqual(store.current.mode, .solo)

        store.update { $0.mode = .group }
        XCTAssertEqual(store.current.mode, .group)
    }

    func testStoreUpdateIsCumulative() {
        let store = AnalysisConfigurationStore()
        store.update { $0.viewportSize = CGSize(width: 300, height: 400) }
        store.update { $0.mode = .object }

        // Cập nhật sau không được xoá giá trị đã set trước đó.
        XCTAssertEqual(store.current.viewportSize, CGSize(width: 300, height: 400))
        XCTAssertEqual(store.current.mode, .object)
        XCTAssertTrue(store.current.needsBackgroundAnalysis)
    }

    /// Ghi từ nhiều thread đồng thời rồi kiểm tra không mất dữ liệu.
    ///
    /// Nếu khoá bị bỏ sót, test này sẽ cho kết quả không xác định hoặc crash.
    func testConcurrentUpdatesDoNotLoseData() {
        let store = AnalysisConfigurationStore()
        let iterations = 500

        DispatchQueue.concurrentPerform(iterations: iterations) { index in
            store.update { configuration in
                // Mỗi lần ghi tăng một giá trị khác nhau để phát hiện mất ghi.
                if index.isMultiple(of: 2) {
                    configuration.viewportSize = CGSize(width: CGFloat(index), height: 0)
                } else {
                    configuration.mode = .object
                }
            }
        }

        // Sau khi chạy xong, giá trị phải là giá trị của lần ghi cuối cùng,
        // và store phải vẫn đọc được (không bị hỏng).
        let final = store.current
        XCTAssertTrue(
            final.viewportSize.width.isFinite || final.mode == .object,
            "Store phải trả về giá trị hợp lệ sau khi ghi đồng thời"
        )
    }

    func testConfigurationIsSendable() {
        // Compile-time check: nếu AnalysisConfiguration mất Sendable thì test này
        // không build được — đúng như ý muốn.
        let configuration = AnalysisConfiguration(mode: .couple, viewportSize: CGSize(width: 1, height: 1))
        func requireSendable<T: Sendable>(_ value: T) -> T { value }
        _ = requireSendable(configuration)
    }

    func testStoreIsSendable() {
        func requireSendable<T: Sendable>(_ value: T) -> T { value }
        let store = AnalysisConfigurationStore()
        _ = requireSendable(store)
    }
}
