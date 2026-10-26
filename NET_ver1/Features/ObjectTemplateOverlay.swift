import SwiftUI

/// Khuôn cho chế độ vật thể: khung vùng nên lấp đầy, có nhãn vị trí.
struct ObjectTemplateOverlay: View {
    let isSatisfied: Bool

    private var accent: Color {
        isSatisfied ? .netGreen : .netCoral
    }

    var body: some View {
        GeometryReader { proxy in
            let rect = focusRect(in: proxy.size)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(accent, style: .init(lineWidth: 2.5, dash: [12, 8]))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)

                Image(systemName: "plus")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent.opacity(0.8))
                    .offset(x: rect.minX + 6, y: rect.minY + 4)
            }
        }
        .allowsHitTesting(false)
    }

    /// Vật thể nên lấp gần hết khung nhưng chừa viền an toàn.
    private func focusRect(in size: CGSize) -> CGRect {
        let height = size.height * 0.66
        let width = size.width * 0.78
        return CGRect(
            x: (size.width - width) / 2,
            y: (size.height - height) / 2,
            width: width,
            height: height
        )
    }
}