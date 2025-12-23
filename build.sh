#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------- color helpers (safe: disable when not a TTY) ----------------------------------------
if [ -t 1 ]; then
  BLUE='\033[1;34m'
  GREEN='\033[1;32m'
  YELLOW='\033[1;33m'
  RED='\033[1;31m'
  MAG='\033[1;35m'
  CYAN='\033[1;36m'
  BOLD='\033[1m'
  RESET='\033[0m'
else
  BLUE=''
  GREEN=''
  YELLOW=''
  RED=''
  MAG=''
  CYAN=''
  BOLD=''
  RESET=''
fi
# ------------------------------------------------ helpers ------------------------------------------------
info()  { printf "%b\n" "${BLUE}[INFO]${RESET} $*"; }
warn()  { printf "%b\n" "${YELLOW}[WARN]${RESET} $*"; }
error() { printf "%b\n" "${RED}[ERR]${RESET} $*"; exit 1; }

confirm() {
  read -r -p "$1 [y/N]: " ans
  case "$ans" in
    [Yy]|[Yy][Ee][Ss]) return 0 ;;
    *) return 1 ;;
  esac
}

abs_path() {
  if [ ! -d "$1" ]; then
    mkdir -p "$1" || {
      echo "❌ Không thể tạo thư mục: $1" >&2
      exit 1
    }
  fi

  if command -v realpath >/dev/null 2>&1; then
    realpath "$1"
  else
    python -c "import os,sys; print(os.path.abspath(sys.argv[1]))" "$1"
  fi
}



# -------- functions --------

# ---------------------------------------- git checkout/pull with optional discard (DISCARD_BEFORE_PULL env var, default 1) ----------------------------------------
git_checkout_and_pull() {
  local repo_dir="$1"
  local branch="$2"
  local stash_apply="${3:-}" 

  [ -d "$repo_dir" ] || error "git: repo_dir không tồn tại: $repo_dir"
  command -v git >/dev/null 2>&1 || error "git không cài đặt."

  info "Git: xử lý repo: $repo_dir  branch: '${branch:-<empty>}'"
  pushd "$repo_dir" >/dev/null

  [ -d .git ] || { popd >/dev/null; error "$repo_dir không phải git repo"; }

  info "git fetch --all --prune"
  git fetch --all --prune

  if [ -z "$branch" ]; then
    error "Không có branch được cung cấp - bỏ qua checkout/pull"
    popd >/dev/null
    return 0
  fi


  info "Hiện tại trên branch: $(git rev-parse --abbrev-ref HEAD)"
  local status
  status="$(git status --porcelain || true)"
  if [ -n "$status" ]; then
    warn "Repo có thay đổi local."
  else
    info "Repo sạch."
  fi

  if [ "${DISCARD_BEFORE_PULL:-1}" = "1" ] && [ -n "$status" ]; then
    warn "DISCARD_BEFORE_PULL=1 -> sẽ reset & clean"
    git reset --hard
    git clean -fdx
    status=""
    info "Các thay đổi local đã bị loại bỏ." 
  fi
  checkout $branch
  info "git pull --rebase origin $branch"
  git pull --rebase origin "$branch"
  info "Git pull + rebase hoàn tất. Commit gần nhất: $(git log -n 1 --pretty=format:'%h %s (%ci)')"
  
   # -------------------- APPLY STASH --------------------
  if [ -n "$stash_apply" ]; then
    info "Đang áp dụng stash '$stash_apply' vào repo $repo_dir".......
    if git apply "$stash_apply"; then
      info "Đã áp dụng stash '$stash_apply' vào repo $repo_dir"
    else
      warn "Không apply được stash $stash_apply"
    fi
  fi
  popd >/dev/null
}
# -------------------- checkout logic --------------------
checkout() {
  local branch="$1"
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    info "Checkout local branch $branch"
    git checkout "$branch"
  elif git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
    info "Tạo local tracking branch origin/$branch"
    git checkout -b "$branch" --track "origin/$branch"
  else
    warn "Không tìm thấy branch '$branch' trên origin."
    if confirm "Tạo branch cục bộ '$branch' từ HEAD hiện tại?"; then
      git checkout -b "$branch"
    else
      popd >/dev/null
      error "Aborted bởi người dùng."
    fi
  fi
}

# ---------------------------------------- pod repo update && pod install (skippable repo update by SKIP_POD_REPO_UPDATE=1) ----------------------------------------
pod_install_update() {
  local ios_root="$1"
  [ -d "$ios_root" ] || error "pod: ios_root không tồn tại: $ios_root"
  pushd "$ios_root" >/dev/null
  command -v pod >/dev/null 2>&1 || error "CocoaPods (pod) không cài đặt."

  if [ "${SKIP_POD_REPO_UPDATE:-0}" != "1" ]; then
    info "pod repo update (this may take a while)"
    pod repo update
  else
    info "SKIP_POD_REPO_UPDATE=1 -> bỏ qua pod repo update"
  fi

  info "pod install"
  pod install
  popd >/dev/null
}

# ---------------------------------------- build flutter ios-framework ----------------------------------------
build_flutter_framework() {
  local flutter_root="$1"
  local out_dir="$2" # abs or relative
  local SRC_PODFILE="$3"
  [ -d "$flutter_root" ] || error "flutter build: flutter_root không tồn tại: $flutter_root"
  command -v flutter >/dev/null 2>&1 || error "flutter CLI không tìm thấy trên PATH."

  out_dir="$(abs_path "$out_dir")"
  mkdir -p "$out_dir"

  pushd "$flutter_root" >/dev/null
  info "flutter clean"
  flutter clean

  info "flutter pub get"
  flutter pub get

  # Replace Podfile if a Podfile exists in SCRIPT_DIR
  DEST_PODFILE="$flutter_root/.ios/Podfile"
  if [ -f "$SRC_PODFILE" ]; then
    info "Tìm thấy Podfile tại $SRC_PODFILE -> sẽ thay thế $DEST_PODFILE"
    if [ -f "$DEST_PODFILE" ]; then
      BACKUP="$DEST_PODFILE.bak.$(date +%s)"
      info "Sao lưu Podfile hiện tại sang: $BACKUP"
      cp "$DEST_PODFILE" "$BACKUP" || warn "Không thể sao lưu Podfile hiện tại"
    else
      info "Không tìm thấy Podfile đích - sẽ tạo mới"
      mkdir -p "$(dirname "$DEST_PODFILE")"
    fi
    cp "$SRC_PODFILE" "$DEST_PODFILE" || error "Không thể copy Podfile -> $DEST_PODFILE"
    info "Podfile đã được thay thế."
  else
    warn "Không tìm thấy Podfile tại $SRC_PODFILE - bỏ qua bước thay thế Podfile."
  fi

  info "flutter build ios-framework -> output=$out_dir"
  flutter build ios-framework --release --no-debug --no-profile --output="$out_dir"
  popd >/dev/null
}

# ---------------------------------------- copy flutter build Release -> ios_lib ----------------------------------------
copy_flutter_build() {
  local out_dir="$1/Release"   # abs path to flutter_build
  local ios_lib="$2"   # destination dir
  [ -d "$out_dir" ] || error "copy_flutter_build: out_dir không tồn tại: $out_dir"
  mkdir -p "$ios_lib"

  # Remove duplicate/trash files inside flutter build (as requested)
  info "Xoá file bị trùng...."
  pushd "$out_dir" >/dev/null
  rm -rf Fire* Goog* FBLPromises* nanopb* Promises* AppAuth* 2>/dev/null || true
  popd >/dev/null

  info "Xóa nội dung cũ trong $ios_lib"
  rm -rf "${ios_lib:?}/"*

  # Expecting $out_dir/Release contains frameworks
  if [ -d "$out_dir" ]; then
    info "Copy từ $out_dir -> $ios_lib"
    cp -R "$out_dir/"* "$ios_lib/"
  else
    warn "Không tìm thấy $out_dir - kiểm tra xem flutter build đã tạo Release hay không"
    # Try copying all if Release not present (fallback)
    cp -R "$out_dir/"* "$ios_lib/" || warn "Không copy được (có thể không có file nào)"
  fi

  info "Đã copy Flutter frameworks vào $ios_lib"
}

# ----------------- set iOS version / build only (prefer .xcworkspace) -----------------
set_ios_version() {
  local ios_root="$1"
  local build="$2"     # numeric or "auto"

  info "Cập nhật iOS build=$build (ios_root=$ios_root)"

  if [ -z "$build" ]; then
    info "Không có build được cung cấp -> bỏ qua"
    return 0
  fi

  if command -v agvtool >/dev/null 2>&1; then
    local proj_path
    proj_path=$(find "$ios_root" -maxdepth 3 -type d -name "FPTLife.xcodeproj" -print -quit 2>/dev/null || true)

    local agv_dir=""
    if [ -n "$proj_path" ]; then
      agv_dir=$(dirname "$proj_path")
      info "Không tìm thấy workspace, nhưng tìm thấy xcodeproj: $proj_path -> sẽ chạy agvtool trong $agv_dir"
    else
      warn "Không tìm thấy .xcodeproj để chạy agvtool"
      agv_dir=""
    fi

    if [ -n "$agv_dir" ]; then
      pushd "$agv_dir" >/dev/null || true
      if [ -n "$build" ]; then
        xcrun agvtool new-version -all "$build" || warn "agvtool new-version failed"
      fi
      popd >/dev/null || true
    fi
  else
    warn "agvtool không có trên PATH -> bỏ qua cập nhật project-level"
  fi
  info "Hoàn tất cập nhật iOS version/build"
}
# -------------------------------------------------------------------------




# ---------------------------------------- xcode archive & export (automatic signing) ----------------------------------------
build_xcode_archive_and_export() {
  local ios_root="$1"
  local scheme="$2"
  local configuration="$3"
  local team_id="$4"
  local export_method="$5"   # enterprise / ad-hoc / app-store
  local output_ipa_dir="$6"

  [ -d "$ios_root" ] || error "xcode: ios_root không tồn tại: $ios_root"
  mkdir -p "$output_ipa_dir"

  pushd "$ios_root" >/dev/null

  local archive_path="$output_ipa_dir/${scheme}.xcarchive"
  local export_plist="$output_ipa_dir/ExportOptions.plist"

  info "Tạo ExportOptions.plist ($export_method, auto signing)"
  cat > "$export_plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>$export_method</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>teamID</key>
  <string>$team_id</string>
  <key>compileBitcode</key>
  <false/>
  <key>destination</key>
  <string>export</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>thinning</key>
  <string>&lt;none&gt;</string>
</dict>
</plist>
EOF

  info "xcodebuild clean -scheme $scheme -configuration $configuration"
  xcodebuild clean -scheme "$scheme" -configuration "$configuration" || warn "clean returned non-zero (continuing)"

  info "Archiving: scheme=$scheme configuration=$configuration -> $archive_path"
  xcodebuild archive \
    -workspace "FPTLife.xcworkspace" \
    -scheme "$scheme" \
    -sdk iphoneos \
    -configuration "$configuration" \
    -archivePath "$archive_path" \
    DEVELOPMENT_TEAM="$team_id" \
    -allowProvisioningUpdates
    

  info "Exporting to IPA -> $output_ipa_dir"
  xcodebuild -exportArchive \
    -archivePath "$archive_path" \
    -exportPath "$output_ipa_dir" \
    -exportOptionsPlist "$export_plist" \
    -allowProvisioningUpdates

  info "xcodebuild finished. IPA (if success) at $output_ipa_dir"
  popd >/dev/null
}

# ---------------------------------------- validate IPA ----------------------------------------
validate_ipa() {
  local ipa_path="$1"
  local apple_id="$2"
  local app_password="$3"

  if [ ! -f "$ipa_path" ]; then
    echo "❌ IPA file không tồn tại: $ipa_path"
    return 1
  fi

  echo "🔍 Đang validate IPA: $ipa_path"
  xcrun altool --validate-app \
    -f "$ipa_path" \
    -t ios \
    -u "$apple_id" \
    -p "$app_password" \
    --output-format xml

  echo "✅ Validate IPA thành công"
}


# ---------------------------------------- upload ipa to Diawi ----------------------------------------
upload_ipa_to_diawi() {
  local ipa_file="$1"
  local diawi_token="$2"

  [ -f "$ipa_file" ] || { error "❌ IPA file không tồn tại: $ipa_file" >&2; return 1; }
  [ -n "$diawi_token" ] || { error "❌ Chưa truyền Diawi API token" >&2; return 1; }


  local response
  response=$(curl -s \
    -F "token=$diawi_token" \
    -F "file=@$ipa_file" \
    -F "wall_of_apps=false" \
    -F "installation_notifications=false" \
    https://upload.diawi.com/)
# response='{"job":"5ur5gNkRU2TnIRDpV5U9t5hqxg358JxO6OBcJ7OceN"}'


  # Lấy job ID
  local job_id
  job_id=$(echo "$response" | grep -o '"job":"[^"]*"' | cut -d '"' -f 4)

  if [ -z "$job_id" ]; then
    error "❌ $response Không lấy được job id, kiểm tra token hoặc file IPA." >&2
    return 1
  fi

#   info "🔄 Đang đợi Diawi xử lý (job: $job_id)..."

  local status link
  while true; do
    sleep 5
    local status link
    local status_response
    status_response=$(curl -s "https://upload.diawi.com/status?token=${diawi_token}&job=${job_id}")
    status=$(echo "$status_response" | grep -o '"status":[0-9]*' | cut -d ':' -f2)
    link=$(echo "$status_response" | grep -o '"link":"[^"]*"' | cut -d '"' -f4 | sed 's/\\//g')
    if [ "$status" = "2000" ] && [ -n "$link" ]; then
      # Trả về link để gán cho INSTALL_LINK
      echo "$link"
      return 0
    elif [ "$status" = "ERROR" ]; then
      error "❌ Lỗi xử lý IPA trên Diawi" >&2
      return 1
    fi
  done
}


# ---------------------------------------- Send mail --------------------------------------------------------------------------------
send_install_link_email() {
  local subject="$1"
  local message="$2"
  local recipients_file="$3"
open -a Mail >/dev/null 2>&1 || true
while IFS= read -r email || [ -n "$email" ]; do
   if [ -n "$email" ]; then
      osascript <<EOF
tell application "Mail"
    set newMessage to make new outgoing message with properties {subject:"$subject", content:"$message", visible:false}
    tell newMessage
        make new to recipient at end of to recipients with properties {address:"$email"}
        send
    end tell
end tell
EOF
      echo "📧 Đã gửi email tới: $email"
    fi
  done < "$recipients_file"
}

send_outlook_email() {
  local subject="$1"
  local install_link="$2"
  local branch_name="$3"
  local release_note="$4"
  local recipients_file="$5"
  local smtp_user="$6"
  local smtp_pass="$7"


  local html_template="mail_template.html"

  local smtp_host="smtp.office365.com"
  local smtp_port="587"

  # ===== Validate =====
  if [ ! -f "$recipients_file" ]; then
    echo "❌ Không tìm thấy file recipients: $recipients_file"
    return 1
  fi

  if [ ! -f "$html_template" ]; then
    echo "❌ Không tìm thấy $html_template"
    return 1
  fi

  # ===== Render HTML =====
  local html_body
  html_body=$(sed \
    -e "s|{{SUBJECT}}|$subject|g" \
    -e "s|{{INSTALL_LINK}}|$install_link|g" \
    -e "s|{{BRANCH_NAME}}|$branch_name|g" \
    -e "s|{{RELEASE_NOTE}}|$release_note|g" \
    "$html_template")

  # ===== Send từng mail =====
  while IFS= read -r email || [ -n "$email" ]; do
    [ -z "$email" ] && continue

    curl --silent --show-error --fail \
      --url "smtp://${smtp_host}:${smtp_port}" \
      --ssl-reqd \
      --mail-from "$smtp_user" \
      --mail-rcpt "$email" \
      --user "$smtp_user:$smtp_pass" \
      --upload-file - <<EOF
From: $smtp_user
To: $email
Subject: $subject
MIME-Version: 1.0
Content-Type: text/html; charset="UTF-8"

$html_body
EOF

    if [ $? -eq 0 ]; then
      echo "📧 Đã gửi email tới: $email"
    else
      echo "❌ Gửi mail thất bại tới: $email"
    fi
  done < "$recipients_file"
}


# ----------------------------------------  Get last commits ---------------------------------------- 
get_last_commits() {
  local repo_dir="$1"
  local count="${2:-10}"  # default 10 commits
  pushd "$repo_dir" >/dev/null || return 1
  git log -n "$count" --pretty=format:'- %h %s (%cr) by %an' || echo "Không lấy được commit"
  popd >/dev/null || return 1
}

get_last_commits_today() {
  local repo_dir="$1"
  pushd "$repo_dir" >/dev/null || return 1
  git log --since=midnight --pretty=format:'- %h %s (%cr) by %an' || echo "Không lấy được commit"
  popd >/dev/null || return 1
}

# ------------------------------------------------ main script flow ------------------------------------------------

# ------------------------------------------------ Defaults (you can override env vars) ------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# DEFAULT_FLUTTER_ROOT="/Users/trucpham/Desktop/Source/FPT_LIFE_FLUTTER"
# DEFAULT_IOS_ROOT="/Users/trucpham/Desktop/Source/FPT_LIFE_iOS"

SCHEME="${SCHEME:-}"
CONFIGURATION="${CONFIGURATION:-}"
EXPORT_METHOD="${EXPORT_METHOD:-}"
OUTPUT_IPA_DIR="$(abs_path "${OUTPUT_IPA_DIR:-$SCRIPT_DIR/ipa_build}")"
TEAM_ID="${TEAM_ID:-}"  # override via env if needed
STASH_NAME="${STASH_NAME:-}"
DIAWI_TOKEN="${DIAWI_TOKEN:-}"
APP_STORE_U="${APP_STORE_U:-}"
APP_STORE_P="${APP_STORE_P:-}"
RECIPIENTS="${RECIPIENTS:-}"
ENV="${ENV:-}"

info "SCHEME=$SCHEME"
info "CONFIGURATION=$CONFIGURATION"
info "EXPORT_METHOD=$EXPORT_METHOD"
info "TEAM_ID=$TEAM_ID"
info "STASH_NAME=$STASH_NAME"
info "RECIPIENTS=$RECIPIENTS"
info "ENV=$ENV"

IOS_BUILD="${5:-}"
FLUTTER_ROOT="${2:-}"
IOS_ROOT="${1:-}"
BRANCH_FLUTTER="${4:-}"
BRANCH_IOS="${3:-}"
SMTP_USER="${6:-}"
SMTP_PASS="${7:-}"

info "Flutter root: $FLUTTER_ROOT"
info "iOS root:     $IOS_ROOT"
info "Flutter branch: $BRANCH_FLUTTER"
info "iOS branch: $BRANCH_IOS"
info "mail from user:  $SMTP_USER"



# ------------------------------------------------ Ask branches ------------------------------------------------

if [ -n "$IOS_ROOT" ]; then
  if [ -z "$BRANCH_IOS" ]; then
    read -r -p "Nhập tên branch iOS muốn checkout (để trống để bỏ qua): " BRANCH_IOS
  else 
    echo "Đã cung cấp branch iOS: $BRANCH_IOS"
  fi
else
  error "iOS root không được cung cấp. Không thể checkout branch iOS."
  exit 1
fi

if [ -n "$FLUTTER_ROOT" ]; then
 if [ -z "$BRANCH_FLUTTER" ]; then
    read -r -p "Nhập tên branch Flutter muốn checkout (để trống để bỏ qua): " BRANCH_FLUTTER
  else 
    echo "Đã cung cấp branch Flutter: $BRANCH_FLUTTER"
  fi
fi



# ---------------------------------------- If flutter branch provided -> checkout + build + copy ----------------------------------------
if [ -n "${BRANCH_FLUTTER:-}" ]; then
  git_checkout_and_pull "$FLUTTER_ROOT" "$BRANCH_FLUTTER"
else
  info "Bỏ qua bước build Flutter (không có branch được cung cấp)."
fi

# ---------------------------------------- If iOS branch provided -> checkout/pull ----------------------------------------
if [ -n "${BRANCH_IOS:-}" ]; then
  STASH_PATH="${STASH_PATH:-}"
  if [ -n "${STASH_NAME:-}" ]; then
    STASH_PATH="$SCRIPT_DIR/$STASH_NAME"
  fi
  git_checkout_and_pull "$IOS_ROOT" "$BRANCH_IOS" "$STASH_PATH"
else
  info "Bỏ qua checkout iOS (không có branch được cung cấp)."
fi

 # ---------------------------------------- build flutter ----------------------------------------
if [ -n "${BRANCH_FLUTTER:-}" ]; then
  FLUTTER_BUILD_DIR="$SCRIPT_DIR/flutter_build"
  build_flutter_framework "$FLUTTER_ROOT" "$FLUTTER_BUILD_DIR" "$SCRIPT_DIR/Podfile"

  # ---------------------------------------- remove duplicates pattern (optional) - run in flutter_build dir ----------------------------------------
  pushd "$FLUTTER_BUILD_DIR" >/dev/null || true
  info "Xoá các file/trùng pattern nếu cần..."
  rm -rf Fire* Goog* FBLPromises* nanopb* Promises* AppAuth* 2>/dev/null || true
  popd >/dev/null || true

  # ---------------------------------------- copy frameworks to ios project ----------------------------------------
  IOS_LIB="$IOS_ROOT/FPTLife/FSS/Libs/Flutter"
  copy_flutter_build "$FLUTTER_BUILD_DIR" "$IOS_LIB"
fi


# ---------------------------------------- Pod install/update --------------------------------------------------------------------------------
pod_install_update "$IOS_ROOT"

# ---------------------------------------- Prefer env vars but fallback to interactive prompt ----------------------------------------

if [ -n "$IOS_BUILD" ]; then
  IOS_BUILD="${IOS_BUILD:-1}"
  set_ios_version "$IOS_ROOT" "$IOS_BUILD"
else
  info "Bỏ qua cập nhật iOS version/build"
fi

# ---------------------------------------- Build xcode archive & export ipa ------------------------------------------------------------
build_xcode_archive_and_export "$IOS_ROOT" "$SCHEME" "$CONFIGURATION" "$TEAM_ID" "$EXPORT_METHOD" "$OUTPUT_IPA_DIR"


# ---------------------------------------- validate IPA ----------------------------------------
OUTPUT_IPA_DIR="$SCRIPT_DIR/ipa_build"
IPA_PATH="$OUTPUT_IPA_DIR/FPTLife.ipa"

if [ -n "$APP_STORE_U" ] && [ -n "$APP_STORE_P" ]; then 
  validate_ipa "$IPA_PATH" "$APP_STORE_U" "$APP_STORE_P"
fi

# ---------------------------------------- upload app ------------------------------------------------------------

INSTALL_LINK="${INSTALL_LINK:-}"
if [ -n "$DIAWI_TOKEN" ]; then 
  info "📤 Đang upload IPA lên Diawi..."
  INSTALL_LINK=$(upload_ipa_to_diawi "$IPA_PATH" "$DIAWI_TOKEN")
  info "📄 Kết quả upload: $INSTALL_LINK"
fi

# ---------------------------------------- send mail ------------------------------------------------------------
# info "📧 Bắt đầu gửi mail..."
# if [ -n "$INSTALL_LINK" ]; then
#   SUBJECT="iOS App Build Mới"
#   branch_name=""
#   if [ -n "$IOS_ROOT" ] && [ -d "$IOS_ROOT/.git" ]; then
#     branch_name=$(git -C "$IOS_ROOT" rev-parse --abbrev-ref HEAD)
#   fi
#   MESSAGE="Xin chào,\n\nĐây là bản build mới của ứng dụng:\n$INSTALL_LINK\n\nBranch: $branch_name\n\nCài đặt trên thiết bị iOS để test."
#   release_note=""
#   if [ -n "$IOS_ROOT" ] && [ -d "$IOS_ROOT/.git" ]; then
#     release_note="Release Note:\n$(get_last_commits "$IOS_ROOT" 20)"
#   fi
#   send_install_link_email "$SUBJECT" "$MESSAGE\n\n$release_note\n\n\n Best regards,\n\nTruc Pham" "$RECIPIENTS.txt"
# else
#   error "❌ Không có link cài đặt. Không gửi email."
# fi
if [ -n "$INSTALL_LINK" ]; then
  SUBJECT="$ENV"

  branch_name=""
  if [ -n "$IOS_ROOT" ] && [ -d "$IOS_ROOT/.git" ]; then
    branch_name=$(git -C "$IOS_ROOT" rev-parse --abbrev-ref HEAD)
  fi

  release_note="No message"
  # if [ -n "$IOS_ROOT" ] && [ -d "$IOS_ROOT/.git" ]; then
  #   release_note="$(get_last_commits "$IOS_ROOT" 20)"
  # fi

  # release_note=$(printf "%s" "$release_note" \
    #  | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')

  # release_note=$(printf "%s" "$release_note" | tr '\n' '<br>')
  smtp_user="$SMTP_USER"
  smtp_pass="$SMTP_PASS"
  send_outlook_email "$SUBJECT" "$INSTALL_LINK" "$branch_name" "$release_note" "$RECIPIENTS.txt" "$smtp_user" "$smtp_pass"

else
  error "❌ Không có link cài đặt. Không gửi email."
fi



info "All done."

# if [ -n "$IOS_ROOT" ] && [ -d "$IOS_ROOT/.git" ]; then
#   echo
#   read -p "📌 Bạn có muốn commit dữ liệu hiện tại của $IOS_ROOT không? (y/n): " do_commit
#   if [[ "$do_commit" =~ ^[Yy]$ ]]; then
#     read -p "✏️  Nhập commit message: " commit_msg
#     if [ -n "$commit_msg" ]; then
#       git -C "$IOS_ROOT" add .
#       git -C "$IOS_ROOT" commit -m "$commit_msg"
#       git -C "$IOS_ROOT" push
#       info "✅ Đã commit và push lên branch $(git -C "$IOS_ROOT" rev-parse --abbrev-ref HEAD)"
#     else
#       warn "⚠️  Không có commit message, bỏ qua commit."
#     fi
#   else
#     info "⏩ Bỏ qua commit."
#   fi
# fi