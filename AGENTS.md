# Guidelines for AI Agents Working on NET_ver1

## 1. Auto Bug Logging (Bắt Buộc Tự Động Lưu Bug)
Mỗi khi gặp phải, điều tra hoặc sửa một lỗi (bug) trong dự án (bao gồm build error, crash runtime, silent bug, asset/rendering bug, concurrency error, logic sai lệch):
- **Phải tự động cập nhật ngay vào [docs/BUG-LOG.md](file:///Users/vohoang/Documents/NET_ver1/docs/BUG-LOG.md)**.
- Ghi rõ: Mã ID tiếp theo (`BUG-xxx`), Phân loại, Mức độ, Thông báo lỗi gốc bằng tiếng Anh (compiler error / crash log / XCTest assertion), Triệu chứng, Nguyên nhân gốc rễ, Cách giải quyết, và Unit test phòng ngừa.
- Không đợi người dùng phải nhắc nhở mới ghi log.

## 2. Coding & Architectural Principles
- **Clean Architecture**: Tách biệt rõ ràng Data → Domain → Presentation.
- **Swift Strict Concurrency**: Tuyệt đối không gọi `MainActor.assumeIsolated` từ background queue; sử dụng các store/lock an toàn đa luồng.
- **RealityKit & 3D Assets**:
  - Mỗi tư thế là một file USDZ nướng tĩnh độc lập.
  - Luôn bọc entity USDZ qua một parent entity wrapper trước khi scale.
  - Luôn kiểm tra tính tương thích giữa iOS 17 (`ARView`) và iOS 18+ (`RealityView`).
- **Regression Testing**: Mọi bug được sửa phải luôn có ít nhất một Unit Test đi kèm để chặn đứng lỗi tái diễn.
