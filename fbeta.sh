#!/bin/bash

# Định nghĩa các biến
TOKEN="$1"
DEFAULT_FLUTTER_ROOT="${3:-"/Users/trucpham/Desktop/Source/FPT_LIFE_FLUTTER"}"
DEFAULT_IOS_ROOT="${2:-"/Users/trucpham/Desktop/Source/FPT_LIFE_iOS"}"
IOS_BUILD="${6:-}"
BRANCH_FLUTTER="${5:-}"
BRANCH_IOS="${4:-}"
SMTP_USER="trucpn3@fpt.com"
SMTP_PASS=""

# Tạo thư mục tạm để chứa các file
TEMP_DIR="/tmp/ios_build/$(date +%s)"
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

cleanup() {
  echo "[watcher] remove temp dir"
  cd - >/dev/null
  rm -rf "$TEMP_DIR"
}

get() {
     REPO_OWNER="TrucPham0502"
     REPO_NAME="CICD"
     BRANCH="main"
     local SCRIPT_NAME="$1"
     curl -H "Authorization: token ${TOKEN}" \
     -L "https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}/${SCRIPT_NAME}" \
     -o $SCRIPT_NAME 2>/dev/null || true
}

trap cleanup EXIT INT TERM

# Tải các file cần thiết
echo "Downloading....."
get build.sh
get beta.recipients.txt
get mail_template.html
get beta.env
get Podfile

# Kiểm tra file đã tải về thành công
if [ ! -f build.sh ] && [ ! -f recipients.txt ] && [ ! -f beta.env ] && [ ! -f Podfile ]; then
    echo "❌ Failed to download"
    exit 1
fi

# Cấp quyền thực thi cho script
chmod +x build.sh

# Chạy script
source beta.env 2>/dev/null || true
./build.sh "$DEFAULT_IOS_ROOT" "$DEFAULT_FLUTTER_ROOT" "$BRANCH_IOS"  "$BRANCH_FLUTTER" "$IOS_BUILD" "$SMTP_USER" "$SMTP_PASS"




