#!/bin/bash

# Định nghĩa các biến
GITHUB_TOKEN="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"
REPO_OWNER="TrucPham0502"
REPO_NAME="CICD"
BRANCH="main"
SCRIPT_NAME="build.sh"

# Tạo thư mục tạm để chứa các file
TEMP_DIR="/tmp/ios_build_$(date +%s)"
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

# Tải các file cần thiết
echo "Downloading build script and dependencies..."
curl -H "Authorization: token ${GITHUB_TOKEN}" \
     -L "https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}/${SCRIPT_NAME}" \
     -o build.sh

# Kiểm tra file đã tải về thành công
if [ ! -f build.sh ]; then
    echo "❌ Failed to download build.sh"
    exit 1
fi

# Tải các file phụ thuộc khác nếu cần
curl -H "Authorization: token ${GITHUB_TOKEN}" \
     -L "https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}/recipients.txt" \
     -o recipients.txt 2>/dev/null || true

curl -H "Authorization: token ${GITHUB_TOKEN}" \
     -L "https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}/beta.env" \
     -o beta.env 2>/dev/null || true

curl -H "Authorization: token ${GITHUB_TOKEN}" \
     -L "https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${BRANCH}/Podfile" \
     -o Podfile 2>/dev/null || true

# Cấp quyền thực thi cho script
chmod +x build.sh

# Chạy script
source prod.beta.env 2>/dev/null || true
./build.sh "$@"

# Dọn dẹp
cd - >/dev/null
rm -rf "$TEMP_DIR"