#!/usr/bin/env bash
# Khởi chạy NET_ver1 AI Interview Coach
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Đang khởi chạy NET_ver1 AI Interview Coach..."
python3 "$DIR/server.py"
