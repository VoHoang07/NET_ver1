#!/usr/bin/env python3
"""Script tiện ích tự động ghi nhận bug mới vào docs/BUG-LOG.md.

Cách sử dụng:
  1. Qua dòng lệnh:
     python3 tools/log_bug.py --title "Lỗi lệch màu" --category "RealityKit / Material" \
         --severity "Trung bình" --symptom "Màu cam không chuyển xanh khi khớp" \
         --cause "Quên cập nhật isAligned trong view model" \
         --solution "Thêm binding cập nhật isAligned" --test "testFigureColourFollowsAlignment"

  2. Chạy tương tác:
     python3 tools/log_bug.py
"""

import argparse
import os
import re
import sys

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUG_LOG_PATH = os.path.join(BASE_DIR, "docs", "BUG-LOG.md")


def get_next_bug_id(content: str) -> str:
    matches = re.findall(r"BUG-(\d{3})", content)
    if not matches:
        return "BUG-001"
    highest = max(int(m) for m in matches)
    return f"BUG-{highest + 1:03d}"


def add_bug_to_file(
    title: str,
    category: str,
    severity: str,
    symptom: str,
    cause: str,
    solution: str,
    test: str,
    error_msg: str = "",
    status: str = "Đã sửa",
):
    if not os.path.exists(BUG_LOG_PATH):
        print(f"Lỗi: Không tìm thấy file {BUG_LOG_PATH}", file=sys.stderr)
        sys.exit(1)

    with open(BUG_LOG_PATH, "r", encoding="utf-8") as f:
        content = f.read()

    bug_id = get_next_bug_id(content)
    print(f"Đang ghi nhận: [{bug_id}] {title}")

    # 1. Thêm vào bảng Quick Index (trước dòng '---' phân cách đầu tiên sau bảng)
    table_row = f"| **{bug_id}** | {category} | {severity} | {title} | {status} | `{test}` |\n"
    
    # Tìm vị trí kết thúc bảng
    table_marker = re.search(r"(\| \*\*BUG-\d+\*\*.*?\n)\n---", content, re.DOTALL)
    if table_marker:
        pos = table_marker.end(1)
        content = content[:pos] + table_row + content[pos:]
    else:
        # Fallback nếu không khớp regex
        pos = content.find("## Chi Tiết Từng Sự Cố Kỹ Thuật")
        content = content[:pos] + table_row + "\n---\n\n" + content[pos:]

    # 2. Thêm vào mục Chi tiết (trước phần Biểu Mẫu Nhập Liệu Chuẩn)
    error_block = f"""- **Thông báo lỗi gốc (Original Error / Assertion)**:
  ```text
  {error_msg.strip() if error_msg.strip() else "[None - Silent Bug hoặc logic issue]"}
  ```
"""
    detail_section = f"""### {bug_id}: {title}
- **Phân loại**: {category}
- **Mức độ**: {severity}
{error_block}- **Triệu chứng**: {symptom}
- **Nguyên nhân gốc rễ**: {cause}
- **Giải pháp**: {solution}
- **Phòng ngừa & Test**: {test}

---

"""
    template_pos = content.find("## Biểu Mẫu Nhập Liệu Chuẩn Khi Gặp Bug Mới")
    if template_pos != -1:
        content = content[:template_pos] + detail_section + content[template_pos:]
    else:
        content += "\n\n" + detail_section

    with open(BUG_LOG_PATH, "w", encoding="utf-8") as f:
        f.write(content)

    print(f"✅ Đã ghi nhận thành công {bug_id} vào docs/BUG-LOG.md!")


def main():
    parser = argparse.ArgumentParser(description="Tự động ghi bug vào docs/BUG-LOG.md")
    parser.add_argument("--title", help="Tiêu đề tóm tắt lỗi")
    parser.add_argument("--category", default="Logic", help="Phân loại lỗi")
    parser.add_argument("--severity", default="Trung bình", help="Mức độ nghiêm trọng")
    parser.add_argument("--error-msg", default="", help="Thông báo lỗi gốc bằng tiếng Anh / XCTest assertion")
    parser.add_argument("--symptom", help="Triệu chứng và hiện tượng")
    parser.add_argument("--cause", help="Nguyên nhân gốc rễ")
    parser.add_argument("--solution", help="Giải pháp khắc phục")
    parser.add_argument("--test", default="N/A", help="Unit test bảo vệ")
    parser.add_argument("--status", default="Đã sửa", help="Trạng thái xử lý")

    args = parser.parse_args()

    if not args.title:
        print("=== NHẬP LIỆU BUG MỚI VÀO DOCS/BUG-LOG.MD ===")
        title = input("Tiêu đề ngắn gọn: ").strip()
        if not title:
            print("Tiêu đề không được để trống!")
            sys.exit(1)
        category = input("Phân loại (Asset 3D / RealityKit / Concurrency / Camera / Vision / UI) [Logic]: ").strip() or "Logic"
        severity = input("Mức độ (Nghiêm trọng / Cao / Trung bình / Thấp) [Trung bình]: ").strip() or "Trung bình"
        error_msg = input("Thông báo lỗi gốc tiếng Anh / log / assertion: ").strip()
        symptom = input("Triệu chứng: ").strip()
        cause = input("Nguyên nhân gốc rễ: ").strip()
        solution = input("Giải pháp: ").strip()
        test = input("Unit test bảo vệ: ").strip() or "N/A"
        status = input("Trạng thái [Đã sửa]: ").strip() or "Đã sửa"
    else:
        title = args.title
        category = args.category
        severity = args.severity
        error_msg = args.error_msg
        symptom = args.symptom or ""
        cause = args.cause or ""
        solution = args.solution or ""
        test = args.test
        status = args.status

    add_bug_to_file(title, category, severity, symptom, cause, solution, test, error_msg, status)


if __name__ == "__main__":
    main()
