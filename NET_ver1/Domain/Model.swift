import CoreGraphics
import Foundation

// MARK: - Capture Mode

nonisolated enum CaptureMode: String, CaseIterable, Identifiable {
    case solo = "Chân dung"
    case couple = "Cặp đôi"
    case group = "Nhóm"
    case object = "Vật thể"

    var id: String { rawValue }
    var title: String { rawValue }

    /// Vật thể không có khuôn người và không chấm được tư thế.
    var usesBodyTemplate: Bool { self != .object }

    /// Số người mong đợi. `nil` = không quan tâm số người.
    var expectedSubjectCount: Int? {
        switch self {
        case .solo: 1
        case .couple: 2
        case .group, .object: nil
        }
    }
}

// MARK: - Mood / Filter Options

nonisolated enum Mood: String, CaseIterable, Identifiable {
    case natural = "Tự nhiên"
    case film = "Thước phim"
    case warm = "Ấm áp"
    case cool = "Trong trẻo"
    case vintage = "Cổ điển"

    var id: String { rawValue }
    var title: String { rawValue }
}

// MARK: - Photo Recipe Model

nonisolated struct PhotoRecipe: Identifiable, Hashable, Equatable {
    let id: UUID
    var title: String
    var description: String
    var cameraAngle: String
    var suggestedMood: Mood
    var mode: CaptureMode

    init(
        id: UUID = UUID(),
        title: String,
        description: String,
        cameraAngle: String,
        suggestedMood: Mood,
        mode: CaptureMode = .solo
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.cameraAngle = cameraAngle
        self.suggestedMood = suggestedMood
        self.mode = mode
    }

    var direction: String { description }
    var cameraTip: String { cameraAngle }
}

// MARK: - Recipe Catalog

nonisolated struct RecipeCatalog {
    /// - Important: mọi `CaptureMode` dùng khuôn người phải có ít nhất một mẫu,
    ///   nếu không `recipes(for:)` sẽ trả về mảng rỗng và UI không có gì để hiển thị.
    static let all: [PhotoRecipe] = [
        PhotoRecipe(
            title: "Góc rộng cận cảnh",
            description: "Hơi nghiêng đầu 15 độ về phía ánh sáng",
            cameraAngle: "Giữ điện thoại ngang tầm mắt, lùi 1m",
            suggestedMood: .natural,
            mode: .solo
        ),
        PhotoRecipe(
            title: "Góc thấp nghiêng",
            description: "Đứng thẳng, chân bước nhẹ về trước",
            cameraAngle: "Đặt camera góc thấp từ dưới lên 45°",
            suggestedMood: .warm,
            mode: .solo
        ),
        PhotoRecipe(
            title: "Tựa vai sóng đôi",
            description: "Hai người đứng sát, quay nhẹ vào nhau",
            cameraAngle: "Góc ngang tầm mắt, cách 1.5m",
            suggestedMood: .film,
            mode: .couple
        ),
        PhotoRecipe(
            title: "Xếp hình khoảnh khắc nhóm",
            description: "Đứng thành vòng thấp, mắt nhìn vào giữa",
            cameraAngle: "Lùi xa đủ để lấy trọn vai mọi người",
            suggestedMood: .natural,
            mode: .group
        ),
        PhotoRecipe(
            title: "Đặt vật lên bệ nghiêng",
            description: "Ánh sáng xiên 45° để thấy khối và bề mặt",
            cameraAngle: "Đặt camera song song mặt phẳng của vật",
            suggestedMood: .cool,
            mode: .object
        ),
        PhotoRecipe(
            title: "Vật trên nền sạch",
            description: "Tách vật khỏi nền, giữ nét vào phần chính",
            cameraAngle: "Chụp vuông góc, tránh bóng đổ dài",
            suggestedMood: .vintage,
            mode: .object
        )
    ]

    static func recipes(for mode: CaptureMode) -> [PhotoRecipe] {
        all.filter { $0.mode == mode }
    }

    static var defaultRecipe: PhotoRecipe {
        all.first ?? PhotoRecipe(
            title: "Góc cơ bản",
            description: "Giữ máy ổn định và nhìn vào ống kính",
            cameraAngle: "Ngang tầm mắt, cách chủ thể khoảng 1.5m",
            suggestedMood: .natural
        )
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
