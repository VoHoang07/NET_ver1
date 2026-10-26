import json
import subprocess
import sys
import glob
import os

# Đọc failure message từ xcresult gần nhất rồi in phần hình dạng.
pattern = os.path.expanduser(
    "~/Library/Developer/Xcode/DerivedData/NET_ver1-*/Logs/Test/*.xcresult"
)
result = max(glob.glob(pattern), key=os.path.getmtime)

raw = subprocess.run(
    ["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", result],
    capture_output=True, text=True,
).stdout

messages = []


def walk(node):
    if isinstance(node, dict):
        if node.get("nodeType") == "Failure Message":
            messages.append(node["name"])
        for value in node.values():
            walk(value)
    elif isinstance(node, list):
        for value in node:
            walk(value)


walk(json.loads(raw))

marker = "Hinh dang (dau # la bong nguoi):"
for message in messages:
    text = message.replace("\\n", "\n")
    if marker not in text:
        continue
    head = text.split(marker)[0]
    body = text.split(marker)[1].split("|||")[0]
    pose = head.split("`")[1] if "`" in head else "?"
    print(f"### {pose}")
    print(body.strip())
    print()