# Chính Sách Bảo Mật (Privacy Policy) — Ứng Dụng NÉT

**Cập nhật lần cuối:** Tháng 10/2026  
**Nhà phát triển:** Võ Vũ Minh Hoàng (`© 2026 Võ Vũ Minh Hoàng. All rights reserved.`)

## 1. Cam kết chung
**NÉT** tôn trọng tuyệt đối quyền riêng tư của người dùng. Ứng dụng **không yêu cầu đăng ký tài khoản**, **không theo dõi người dùng (`NSPrivacyTracking = false`)**, và **không thu thập hay truyền tải bất kỳ dữ liệu cá nhân nào** về máy chủ bên ngoài.

## 2. Quyền truy cập Camera (`NSCameraUsageDescription`)
- **Mục đích:** Ứng dụng cần quyền truy cập Camera để hiển thị trực tiếp mô hình 3D tạo dáng trên khung ngắm, giúp bạn căn chỉnh góc chụp và bố cục hình ảnh trong không gian thực tế (ARKit & RealityKit).
- **Xử lý dữ liệu:** Toàn bộ luồng hình ảnh từ Camera và phép đo tư thế (Vision Framework) được xử lý cục bộ theo thời gian thực ngay trên thiết bị của bạn (100% On-Device) và không bao giờ rời khỏi thiết bị.

## 3. Quyền truy cập Thư viện ảnh (`NSPhotoLibraryUsageDescription` & `NSPhotoLibraryAddUsageDescription`)
- **Mục đích:** Ứng dụng cần quyền truy cập Thư viện ảnh để lưu lại bức ảnh bạn vừa chụp vào thiết bị và hiển thị lại trong mục Bộ Sưu Tập khi bạn cho phép.
- **Xử lý dữ liệu:** Ứng dụng không tự ý đọc, phân tích hoặc sao chép bất kỳ hình ảnh nào ra khỏi thiết bị của bạn.

## 4. Lưu trữ tùy chỉnh cục bộ (`UserDefaults` — `CA92.1`)
Các tùy chỉnh cá nhân trong ứng dụng (như chiều cao mẫu 3D, số đo tham chiếu và trạng thái hướng dẫn) chỉ được lưu cục bộ trên thiết bị của bạn thông qua bộ nhớ `UserDefaults` của hệ điều hành iOS.

## 5. Liên hệ
Mọi thắc mắc liên quan đến Chính sách bảo mật, vui lòng liên hệ nhà phát triển **Võ Vũ Minh Hoàng** qua GitHub: [https://github.com/VoHoang07/NET_ver1](https://github.com/VoHoang07/NET_ver1).
