#!/usr/bin/env bash
set -euo pipefail

# (Tuỳ chọn) đảm bảo PATH nếu chạy từ launchd
FLUTTER_PATH="/Users/trucpham/Documents/flutter/flutter/bin"
export PATH="/usr/local/bin:/usr/bin:/bin:$FLUTTER_PATH:$PATH"
export RUBYOPT="-EUTF-8"


# Cấu hình
REPO_FLUTTER="/Users/trucpham/Desktop/Source/FPT_LIFE_FLUTTER"
REPO_DIR="/Users/trucpham/Desktop/Source/FPT_LIFE_iOS"
HOOK_SCRIPT="/Users/trucpham/Desktop/Project/CICD/fbeta.sh"
# nếu bạn muốn tách token ra env var, thay bằng ${GITHUB_PAT} hoặc tương tự
TOKEN=""

STATE_DIR="$HOME/.git-remote-watcher"
LOCK_DIR="$STATE_DIR/lock"
mkdir -p "$STATE_DIR" 
   
cd "$REPO_DIR" || exit 1

# lock để tránh chạy chồng chéo
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "[watcher] Another instance is running. Exiting."
  exit 0
fi

cleanup() {
  echo "[watcher] remove lock dir"
  rm -rf "$LOCK_DIR"
}
# cleanup khi script thoát, hoặc bị Ctrl+C, hoặc lỗi
trap cleanup EXIT INT TERM

# đảm bảo script có thể chạy
if [ ! -x "$HOOK_SCRIPT" ]; then
  echo "[watcher] Hook script không tồn tại hoặc không executable: $HOOK_SCRIPT"
  exit 1
fi

# lấy branch hiện tại (nếu đang detached HEAD thì dùng HEAD)
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)"

# xác định upstream: cố lấy @{u}, nếu không có thì dùng origin/BRANCH
if UPSTREAM="$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null)"; then
  :
else
  UPSTREAM="origin/$BRANCH"
fi

# fetch remote (chỉ cập nhật refs remote, KHÔNG làm pull)
git fetch --quiet

# local và remote commit ids
LOCAL="$(git rev-parse HEAD 2>/dev/null || echo "")"
REMOTE="$(git rev-parse "$UPSTREAM" 2>/dev/null || echo "")"

if [ -z "$REMOTE" ]; then
  echo "[watcher] Không tìm được remote ref $UPSTREAM"
  exit 0
fi

if [ "$REMOTE" != "$LOCAL" ]; then
  echo "[watcher] Remote khác local: local=$LOCAL, remote=$REMOTE. Kiểm tra commit message..."

# Lấy commit message của commit remote
  COMMIT_MSG="$(git log -1 --pretty=%B "$REMOTE" 2>/dev/null || echo "")"
# COMMIT_MSG="build beta 1 release/2.8.1"
  # normalize: trim leading/trailing whitespace (bash)
  echo "[watcher] commit message (remote):"
  echo "Message :  $COMMIT_MSG"

  commit_message=$(echo "$COMMIT_MSG" | xargs)
  set -- $commit_message
  ACTION="$1"
  ENVIRONMENT="$2"
  IOS_BUILD="${3:-}"
  BRANCH_FLUTTER="${4:-}"


  # pattern: build <env> <ios_build> <branch_flutter>
  # env allowed: beta or prod.beta   (thích hợp bạn có thể bổ sung)
  # ios_build: số nguyên
  # branch_flutter: phần còn lại (có thể chứa /)
  if [ "$ACTION" = "build" ]; then
    echo "[watcher] Parsed build command -> env=${ENVIRONMENT}, ios_build=${IOS_BUILD}, branch_flutter=${BRANCH_FLUTTER}"
    # gọi hook: truyền token, đường dẫn repo iOS, repo flutter, branch iOS, branch flutter, env, ios_build
    # Bạn có thể điều chỉnh thứ tự/param theo logic của fbeta.sh
    # "$ENVIRONMENT"
    "$HOOK_SCRIPT" "$TOKEN" "$REPO_DIR" "$REPO_FLUTTER" "$BRANCH" "$BRANCH_FLUTTER" "$IOS_BUILD" 
  else
    echo "[watcher] Commit message không khớp pattern 'build <env> <ios_build> <branch_flutter>' -> không chạy hook."
  fi
else
  echo "[watcher] Local đã bằng remote (không thay đổi)."
fi
