# NÉT — Trợ Lý Hướng Dẫn Tạo Dáng & Bố Cục Nhiếp Ảnh AR (iOS)

Ứng dụng iOS hỗ trợ chụp ảnh chân dung và hướng dẫn tạo dáng trực quan trong không gian thực tế bằng **ARKit**, **RealityKit**, **Vision** và **SwiftUI**.

## Tính năng nổi bật
- **Real-world Floor Anchoring & Smart Auto-Placement:** Phát hiện mặt sàn ngang thực tế (`ARWorldTrackingConfiguration`), phân tích 15 điểm ứng viên trên dải sàn mở để tự động đặt mẫu 3D vào góc đứng thoáng đẹp nhất theo bố cục 1/3.
- **Photorealistic 3D Pose Guide:** Hệ thống các tư thế 3D USDZ tỷ lệ người thật kèm bóng đổ tiếp xúc (`GroundShadowBuilder`), tự xoay góc 3/4 hướng về ống kính và nội suy chuyển động mượt (`simd_mix` & `simd_slerp`).
- **Real-time Posture Coaching & Auto-Capture:** Phân tích khung xương thời gian thực bằng Vision Framework trên thiết bị, chấm điểm bố cục/ánh sáng và tự động chụp khi khớp dáng.
- **Minimalist Pro Camera UI:** Khung ngắm tràn viền, giao diện kính mờ tinh gọn, bộ lọc màu phim (`Mood`) và tương thích đầy đủ với cả iPhone lẫn iPad.

## Yêu cầu hệ thống
- iOS 17.0+
- Xcode 16+ / Swift 6 Strict Concurrency

## Bản quyền & Quyền riêng tư
- **Bản quyền:** © 2026 Võ Vũ Minh Hoàng. All rights reserved.
- **Chính sách bảo mật:** Xem tại [docs/PRIVACY-POLICY.md](docs/PRIVACY-POLICY.md).
