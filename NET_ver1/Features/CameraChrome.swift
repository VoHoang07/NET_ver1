import SwiftUI

struct PoseGuide: View {
    let recipe: PhotoRecipe
    let mode: CaptureMode

    var body: some View {
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 36)
                .stroke(Color.netCoral, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .frame(width: guideWidth, height: guideHeight)
                .overlay {
                    Image(systemName: guideIcon)
                        .font(.system(size: 40))
                        .foregroundStyle(Color.netCoral.opacity(0.35))
                }

            VStack(spacing: 4) {
                Text(recipe.direction)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text(recipe.cameraTip)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.black.opacity(0.55), in: .rect(cornerRadius: 14))
            .padding(.horizontal, 30)
        }
        .accessibilityElement(children: .combine)
    }

    /// Nhóm và vật thể cần khung rộng hơn chân dung, nếu không các đối tượng thứ hai
    /// sẽ nằm ngoài vùng hướng dẫn.
    private var guideWidth: CGFloat {
        switch mode {
        case .solo: 160
        case .couple: 230
        case .group: 250
        case .object: 220
        }
    }

    private var guideHeight: CGFloat {
        switch mode {
        case .solo, .object: 230
        case .couple, .group: 180
        }
    }

    private var guideIcon: String {
        switch mode {
        case .solo: "person.fill"
        case .couple: "person.2.fill"
        case .group: "person.3.fill"
        case .object: "cube.fill"
        }
    }
}
