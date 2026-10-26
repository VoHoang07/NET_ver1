# Auto Bug Logging Rule for Antigravity & AI Assistants

## Mục đích
Đảm bảo mọi lỗi kỹ thuật (compile error, runtime crash, silent bug, asset/rendering bug, logic mismatch) phát sinh hoặc được xử lý trong quá trình lập trình dự án **NET_ver1** đều được tự động ghi nhận ngay lập tức vào [BUG-LOG.md](file:///Users/vohoang/Documents/NET_ver1/docs/BUG-LOG.md).

## Quy Tắc Hành Động Bắt Buộc (Mandatory Workflow)
1. **Khi nào cần ghi log?**
   - Bất cứ khi nào bạn hoặc người dùng phát hiện một bug, một bài kiểm tra (test) bị đỏ, một lỗi crash ứng dụng, hoặc một hành vi hiển thị không mong muốn.
   - Khi hoàn thành việc sửa chữa (fix) một lỗi kỹ thuật hoặc một giả định thiết kế bị sai.
   - Khi phát hiện một "lỗi im lặng" (silent bug) mà hệ thống không in ra log cảnh báo.

2. **Hành động bắt buộc của AI:**
   - Mở file [docs/BUG-LOG.md](file:///Users/vohoang/Documents/NET_ver1/docs/BUG-LOG.md).
   - Xác định mã số tiếp theo (ví dụ: `BUG-021`, `BUG-022`,...).
   - Thêm một hàng mới vào bảng **Danh Sách Tổng Hợp Nhanh (Bug Matrix)**.
   - Thêm mục phân tích chi tiết vào phần **Chi Tiết Từng Sự Cố Kỹ Thuật** theo cấu trúc:
     * **Mã & Tiêu đề**: `### BUG-xxx: [Tiêu đề]`
     * **Phân loại**: [Asset 3D / RealityKit / Concurrency / Camera / Vision / UI / Logic]
     * **Mức độ**: [Nghiêm trọng / Cao / Trung bình / Thấp]
     * **Thông báo lỗi gốc (Original Error / Assertion)**: Dòng lỗi tiếng Anh nguyên bản từ compiler, runtime crash log, exception, hoặc XCTest assertion message
     * **Triệu chứng**: Chi tiết hiện tượng, lỗi hiển thị hoặc crash stacktrace
     * **Nguyên nhân gốc rễ**: Giải thích tường tận cơ chế gây lỗi
     * **Giải pháp**: Phương án sửa đổi code/tài nguyên
     * **Phòng ngừa & Test**: Tên unit test hoặc biện pháp chặn lỗi tái phát
   - Giữ nguyên các mục cũ, chỉ thêm mới vào cuối danh sách.
