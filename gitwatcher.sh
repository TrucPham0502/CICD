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
BRANCH=""
# nếu bạn muốn tách token ra env var, thay bằng ${GITHUB_PAT} hoặc tương tự
TOKEN=""

STATE_DIR="$HOME/.git-remote-watcher"
LOCK_DIR="$STATE_DIR/lock"
mkdir -p "$STATE_DIR" 

cleanup() {
  echo "[watcher] remove lock dir"
  rm -rf "$LOCK_DIR"
}

# cleanup khi script thoát, hoặc bị Ctrl+C, hoặc lỗi
trap cleanup EXIT INT TERM


send_mail() {
  local recipient_name="$1"
  local recipient_email="$2"
  local subject="$3"
  local body="$4"

  local escaped_subject=${subject//\"/\\\"}
  local escaped_body=${body//\"/\\\"}
  local escaped_recipient=${recipient_email//\"/\\\"}

  osascript <<EOF
  with timeout of 300 seconds
    try
      tell application "Mail"
        activate
        set newMessage to make new outgoing message with properties {subject:"$escaped_subject", content:"$escaped_body"}
        tell newMessage
          make new to recipient at end of to recipients with properties {address:"$escaped_recipient"}
        end tell
        delay 1
        send newMessage
      end tell
      return "OK"
    on error errMsg number errNum
      return "ERROR: " & errNum & " - " & errMsg
    end try
  end timeout
EOF
}



run_hook() {
  local env="$1"
  local ios_build="$2"
  local branch_flutter="$3"
  local commit_msg="$4"
  local recipient_name="$5"
  local recipient_email="$6"

  echo "[watcher] Chạy hook build..."
  "$HOOK_SCRIPT" "$TOKEN" "$REPO_DIR" "$REPO_FLUTTER" "$BRANCH" "$branch_flutter" "$ios_build"
  local rc=$?

  if [ $rc -eq 0 ]; then
    echo "[watcher] Build thành công."
  else
    echo "[watcher] Build thất bại (exit=$rc)."
    send_mail "$recipient_name" "$recipient_email" \
      "[CI][FAILED] Build thất bại: $env / $branch_flutter" \
      "Xin chào $recipient_name,\n\nCI đã THẤT BẠI khi build.\nBranch iOS: $BRANCH\nBranch Flutter: $branch_flutter\nCommit:\n$commit_msg\n\nExit code: $rc\n\n-- CI Watcher"
  fi
}

process_commit() {
  local remote="$1"

  # Lấy commit message của commit remote
  # commit_msg="$(git log -1 --pretty=%B "$remote" 2>/dev/null || echo "")"
  commit_msg="build beta 1 release/2.8.1"
    # normalize: trim leading/trailing whitespace (bash)
    echo "[watcher] commit message (remote):"
    echo "Message :  $commit_msg"

    commit_message=$(echo "$commit_msg" | xargs)
    set -- $commit_message
    ACTION="$1"
    env="$2"
    ios_build="${3:-}"
    branch_flutter="${4:-}"

    
      
      
    if [ "$ACTION" = "build" ]; then
      echo "[watcher] Parsed build command -> env=${env}, ios_build=${ios_build}, branch_flutter=${branch_flutter}"

      local author_name
      local author_email
      author_name=$(git log -1 --pretty=format:'%an' "$remote")
      author_email=$(git log -1 --pretty=format:'%ae' "$remote")

      echo "[watcher] Commit author: $author_name <$author_email>"


      run_hook "$env" "$ios_build" "$branch_flutter" "$commit_msg" "$author_name" "$author_email"
    else
      echo "[watcher] Commit message không khớp pattern 'build <env> <ios_build> <branch_flutter>' -> không chạy hook."
    fi

}

watch_branch() {
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
    process_commit "$REMOTE"
  else
    echo "[watcher] Local đã bằng remote (không thay đổi)."
  fi
  #  process_commit "$REMOTE"
}

main() {
    cd "$REPO_DIR" || exit 1
  # lock để tránh chạy chồng chéo
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "[watcher] Another instance is running. Exiting."
    exit 0
  fi

  # đảm bảo script có thể chạy
  if [ ! -x "$HOOK_SCRIPT" ]; then
    echo "[watcher] Hook script không tồn tại hoặc không executable: $HOOK_SCRIPT"
    exit 1
  fi

  # lấy branch hiện tại (nếu đang detached HEAD thì dùng HEAD)
  BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)"
  echo "[watcher] Current branch: $BRANCH"
  watch_branch
}


main "$@"

















