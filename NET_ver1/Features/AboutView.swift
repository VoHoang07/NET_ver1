import SwiftUI

/// Màn hình Thông tin ứng dụng & Chính sách bảo mật (App Store Review Guideline 5.1.1).
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingPrivacyPolicy = false

    static let appName = "NÉT"
    static let appVersion = "1.0.0"
    static let copyrightNotice = "© 2026 Võ Vũ Minh Hoàng. All rights reserved."
    static let privacyPolicyURL = URL(string: "https://github.com/VoHoang07/NET_ver1/blob/main/docs/PRIVACY-POLICY.md")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    appHeaderCard
                    featureHighlightsCard
                    legalAndPrivacyCard
                    copyrightFooter
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: 540)
                .frame(maxWidth: .infinity)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Thông tin ứng dụng")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Đóng") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $isShowingPrivacyPolicy) {
                PrivacyPolicyDetailView()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Subviews

    private var appHeaderCard: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.18), Color.white.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 84, height: 84)
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8)
                    }

                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(.white)
            }

            Text(Self.appName)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Trợ lý hướng dẫn tạo dáng & bố cục nhiếp ảnh AR")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)

            Text("Phiên bản \(Self.appVersion)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: .capsule)
                .overlay {
                    Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6)
        }
    }

    private var featureHighlightsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("CÔNG NGHỆ TRÊN THIẾT BỊ")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.55))
                .tracking(1.1)

            infoRow(
                icon: "arkit",
                title: "Bám sàn thực tế ARKit & RealityKit",
                subtitle: "Tự động nhận diện mặt đất thực tế và gợi ý góc đứng thoáng đẹp theo bố cục 1/3."
            )
            Divider().overlay(Color.white.opacity(0.1))
            infoRow(
                icon: "lock.shield",
                title: "Xử lý cục bộ 100% (On-Device)",
                subtitle: "Mọi khung hình camera và phân tích tư thế đều được xử lý trực tiếp trên thiết bị, không tải lên máy chủ."
            )
        }
        .padding(18)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6)
        }
    }

    private var legalAndPrivacyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PHÁP LÝ & QUYỀN RIÊNG TƯ")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.55))
                .tracking(1.1)

            Button {
                isShowingPrivacyPolicy = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.12), in: .circle)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Chính sách bảo mật (Privacy Policy)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("Xem chi tiết cam kết bảo vệ dữ liệu người dùng")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(14)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            Link(destination: Self.privacyPolicyURL) {
                HStack(spacing: 12) {
                    Image(systemName: "safari")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.12), in: .circle)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Chính sách bảo mật trực tuyến")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(Self.privacyPolicyURL.absoluteString)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.60))
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(14)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6)
        }
    }

    private var copyrightFooter: some View {
        VStack(spacing: 6) {
            Text(Self.copyrightNotice)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
            Text("Thiết kế & Phát triển tại Việt Nam")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(.top, 8)
    }

    private func infoRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Màn hình chi tiết Chính sách bảo mật tích hợp sẵn trong ứng dụng.
struct PrivacyPolicyDetailView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Chính sách bảo mật ứng dụng NÉT")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)

                    Text("Cập nhật lần cuối: 2026")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))

                    policySection(
                        title: "1. Cam kết chung",
                        content: "NÉT tôn trọng tuyệt đối quyền riêng tư của người dùng. Ứng dụng không yêu cầu đăng ký tài khoản, không theo dõi người dùng (No Tracking) và không thu thập bất kỳ dữ liệu cá nhân nào về máy chủ bên ngoài."
                    )

                    policySection(
                        title: "2. Quyền truy cập Camera",
                        content: "Ứng dụng cần quyền truy cập Camera để hiển thị trực tiếp mô hình 3D tạo dáng trên khung ngắm, giúp bạn căn chỉnh góc chụp và bố cục hình ảnh. Luồng hình ảnh từ Camera được xử lý theo thời gian thực ngay trên thiết bị (On-Device) và không bao giờ được truyền qua mạng."
                    )

                    policySection(
                        title: "3. Quyền truy cập Thư viện ảnh",
                        content: "Ứng dụng cần quyền truy cập Thư viện ảnh để lưu lại bức ảnh bạn vừa chụp vào thiết bị và hiển thị lại trong mục Bộ Sưu Tập khi bạn cho phép. Ứng dụng không tự ý đọc hoặc sao chép bất kỳ hình ảnh nào ra khỏi thiết bị của bạn."
                    )

                    policySection(
                        title: "4. Lưu trữ tùy chỉnh cục bộ",
                        content: "Các tùy chỉnh cá nhân trong ứng dụng (như chiều cao mẫu 3D, số đo tham chiếu và trạng thái hướng dẫn) chỉ được lưu cục bộ trên thiết bị của bạn thông qua bộ nhớ UserDefaults của hệ điều hành iOS."
                    )

                    policySection(
                        title: "5. Bản quyền & Liên hệ",
                        content: "\(AboutView.copyrightNotice)\nMọi thắc mắc về quyền riêng tư, vui lòng liên hệ qua trang hỗ trợ chính thức của nhà phát triển Võ Vũ Minh Hoàng."
                    )
                }
                .padding(20)
                .frame(maxWidth: 600, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Chính sách bảo mật")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Xong") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func policySection(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Text(content)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
