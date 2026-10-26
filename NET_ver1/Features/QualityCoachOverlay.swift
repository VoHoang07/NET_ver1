import SwiftUI

/// Một chỉ dẫn duy nhất, ngắn nhất có thể, kèm mũi tên chỉ hướng sửa.
///
/// ## Vì sao không liệt kê nhiều lỗi
///
/// Bản đầu hiện danh sách 2 lỗi kèm số liệu kỹ thuật, đặt ở đỉnh khung. Nó che
/// đúng vùng đầu và đường mắt — tức che mất thứ người dùng cần nhìn. Người đang
/// chụp cũng không đọc nổi "Mắt lệch 10.8% chiều cao khung" khi mắt đang nhìn
/// người mẫu.
///
/// Ở đây: **một** chỉ dẫn, đặt ở đáy, có mũi tên. Chi tiết kỹ thuật giữ cho
/// VoiceOver, nơi người dùng không nhìn khung hình nên đọc được thoải mái.
struct QualityCoachOverlay: View {
    let check: CaptureCheck

    /// Lỗi cần sửa gấp nhất. Điều kiện cần trước, rồi tới điều kiện đủ.
    private var topIssue: CriterionResult? {
        (check.failures + check.remainingPolish).first
    }

    private var accent: Color {
        switch check.status {
        case .notReady: .netCoral
        case .good: Color(red: 0.93, green: 0.70, blue: 0.26)
        case .ideal: .netGreen
        }
    }

    private var instruction: Instruction? {
        guard let topIssue else { return nil }
        return Instruction(issue: topIssue)
    }

    var body: some View {
        Group {
            if let instruction {
                HStack(spacing: 6) {
                    Image(systemName: instruction.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent)

                    Text(instruction.text)
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(Color.black.opacity(0.42), in: Capsule())
                .overlay {
                    Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.7)
                }
            } else if check.status == .ideal {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent)

                    Text("Sẵn sàng chụp")
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(Color.black.opacity(0.42), in: Capsule())
                .overlay {
                    Capsule().strokeBorder(Color.netGreen.opacity(0.55), lineWidth: 0.7)
                }
            }
        }        .animation(.easeOut(duration: 0.2), value: check.status)
        .animation(.easeOut(duration: 0.2), value: topIssue?.id)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spokenSummary))
        }

        // MARK: - VoiceOver

        /// Mọi tiêu chí chi tiết cho người dùng hữu hạn — không giới hạn số dòng.
        ///
        /// Số kỹ thuật không nên hiện trên màn hình lúc đang chụp, nhưng người dùng
        /// VoiceOver không nhìn khung hình nên đọc được thoải mái.
        private var spokenSummary: String {
        let issues = check.failures + check.remainingPolish
        guard !issues.isEmpty else { return "Mọi tiêu chí đều đạt" }

        return issues.map { issue in
            if let detail = issue.detail {
                return "\(issue.criterion.title): \(detail)"
            }
            return issue.criterion.title
        }.joined(separator: ". ")
        }
        }

// MARK: - Chỉ dẫn

/// Câu ngắn, dạng mệnh lệnh, kèm mũi tên chỉ hướng.
private struct Instruction {
    let symbol: String
    let text: String

    init(issue: CriterionResult) {
        switch issue.criterion {
        case .sharpness:
            symbol = "bolt.slash"
            text = "Máy đang rung — giữ yên hoặc chạm lấy nét"

        case .lighting:
            // Ánh sáng là lỗi ảnh hỏng, nên chỉ dẫn phải cụ thể theo nguyên nhân.
            if let detail = issue.detail {
                if detail.contains("cháy") {
                    symbol = "sun.max"
                    text = "Chỗ sáng đang cháy — tránh hướng thẳng vào nắng"
                } else if detail.contains("chìm") {
                    symbol = "moon"
                    text = "Ảnh đang tối — bật flash hoặc tìm chỗ sáng hơn"
                } else {
                    symbol = "sun.min"
                    text = "Đang ngược sáng — nghiêng máy trái cho sáng vào mặt"
                }
            } else {
                symbol = "sun.min"
                text = "Ánh sáng chưa ổn"
            }

        case .shadow:
            symbol = "circle.lefthalf.filled"
            text = "Mặt đang có bóng — nghiêng đầu nhẹ sang một bên"

        case .horizon:
            symbol = "arrow.uturn.left"
            text = "Máy đang nghiêng — xoay ngược lại cho ngang"

        case .posture:
            symbol = "arrow.up.and.down"
            if let detail = issue.detail, detail.contains("cao hơn") {
                text = "Mắt đang cao quá đường ngang — hạ người xuống một chút"
            } else if let detail = issue.detail, detail.contains("thấp hơn") {
                text = "Mắt đang thấp quá đường ngang — đứng thẳng hơn một chút"
            } else if let detail = issue.detail, detail.contains("cắt") {
                text = "Đỉnh đầu bị cắt — lùi ra xa một chút"
            } else if let detail = issue.detail, detail.contains("lệch") {
                text = "Đang lệch tâm — dịch sang phía đối diện"
            } else {
                text = "Chưa nhận ra người — tìm chỗ sáng hơn"
            }

        case .composition:
            if let detail = issue.detail, detail.contains("Cần") {
                symbol = "person.2"
                text = "Khung cần \(detail.replacingOccurrences(of: " người nhưng đang có ", with: " người, đang có "))"
            } else if let detail = issue.detail, detail.contains("Đầu nhỏ") {
                symbol = "arrow.up.forward"
                text = "Đứng gần hơn một chút"
            } else if let detail = issue.detail, detail.contains("Đầu lớn") {
                symbol = "arrow.down.forward"
                text = "Lùi ra xa một chút"
            } else if let detail = issue.detail, detail.contains("tiến") {
                symbol = "arrow.up.forward"
                text = "Tiến lại gần hơn"
            } else {
                symbol = "arrow.down.forward"
                text = "Lùi ra xa hơn một chút"
            }

            case .background:
            symbol = "square.dashed"
            text = "Nền đang rối — tìm chỗ nền đơn giản hơn"
            }
            }
            }
