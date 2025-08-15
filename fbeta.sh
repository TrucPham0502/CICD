#!/bin/bash

# Định nghĩa các biến
TOKEN="$1"
DEFAULT_FLUTTER_ROOT="${3:-"/Users/trucpham/Desktop/Source/FPT_LIFE_FLUTTER"}"
DEFAULT_IOS_ROOT="${2:-"/Users/trucpham/Desktop/Source/FPT_LIFE_iOS"}"
IOS_BUILD="${4:-}"

# Tạo thư mục tạm để chứa các file
TEMP_DIR="/tmp/ios_build_$(date +%s)"
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

get() {
     REPO_OWNER="TrucPham0502"
     REPO_NAME="CICD"
     BRANCH="main"
     local SCRIPT_NAME="$1"
     curl -H "Authorization: token ${TOKEN}" \
     -L "https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}/${SCRIPT_NAME}" \
     -o $SCRIPT_NAME 2>/dev/null || true
}

# Tải các file cần thiết
echo "Downloading....."
get build.sh
get recipients.txt
get beta.env
get Podfile

# Kiểm tra file đã tải về thành công
if [ ! -f build.sh ] && [ ! -f recipients.txt ] && [ ! -f beta.env ] && [ ! -f Podfile ]; then
    echo "❌ Failed to download"
    cd - >/dev/null
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Cấp quyền thực thi cho script
chmod +x build.sh

# Chạy script
source beta.env 2>/dev/null || true
./build.sh "$DEFAULT_IOS_ROOT" "$DEFAULT_FLUTTER_ROOT" "$IOS_BUILD"

# Dọn dẹp
cd - >/dev/null
rm -rf "$TEMP_DIR"