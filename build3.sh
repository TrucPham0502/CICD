#!/usr/bin/env bash
set -euo pipefail

# build_step1.sh
# Bước 1: cấu hình source roots, checkout branch flutter và pull latest,
# rồi chạy lệnh build iOS framework (lệnh thực tế đặt qua BUILD_FRAMEWORK_CMD hoặc nhập khi chạy).

# -------- helpers --------
info()  { echo -e "\033[1;34m[INFO]\033[0m $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m $*"; }
error() { echo -e "\033[1;31m[ERR]\033[0m $*"; exit 1; }

confirm() {
  read -r -p "$1 [y/N]: " ans
  case "$ans" in
    [Yy]|[Yy][Ee][Ss]) return 0 ;;
    *) return 1 ;;
  esac
}

abs_path() {
  # portable-ish realpath fallback
  if command -v realpath >/dev/null 2>&1; then
    realpath "$1"
  else
    # python fallback
    python -c "import os,sys; print(os.path.abspath(sys.argv[1]))" "$1"
  fi
}

# -------- start --------

# Default paths (thay đổi nếu cần)

DEFAULT_FLUTTER_ROOT="/Users/trucpham/Desktop/Source/FPT_LIFE_FLUTTER"
DEFAULT_IOS_ROOT="/Users/trucpham/Desktop/Source/FPT_LIFE_iOS"

read -r -p "Đường dẫn source root Flutter (mặc định: $DEFAULT_FLUTTER_ROOT): " FLUTTER_ROOT_INPUT
FLUTTER_ROOT="${FLUTTER_ROOT_INPUT:-$DEFAULT_FLUTTER_ROOT}"

read -r -p "Đường dẫn source root iOS native (mặc định: $DEFAULT_IOS_ROOT): " IOS_ROOT_INPUT
IOS_ROOT="${IOS_ROOT_INPUT:-$DEFAULT_IOS_ROOT}"

FLUTTER_ROOT="$(abs_path "$FLUTTER_ROOT")"
IOS_ROOT="$(abs_path "$IOS_ROOT")"

info "Flutter root: $FLUTTER_ROOT"
info "iOS root:     $IOS_ROOT"

# Check folders exist
[ -d "$FLUTTER_ROOT" ] || error "Không tìm thấy thư mục Flutter: $FLUTTER_ROOT"
[ -d "$IOS_ROOT" ] || warn "Không tìm thấy thư mục iOS: $IOS_ROOT  (nếu chưa có, bạn có thể tạo/clone sau)"

# Ask flutter branch
read -r -p "Nhập tên branch Flutter muốn checkout (ví dụ: feature/xyz): " BRANCH
if [ -n "$BRANCH" ]; then
    # Check git available
    command -v git >/dev/null 2>&1 || error "git không cài đặt. Vui lòng cài git trước khi chạy script này."

    # Perform git operations in flutter repo
    info "Chuyển vào thư mục Flutter..."
    pushd "$FLUTTER_ROOT" >/dev/null

    # verify it's a git repo
    if [ ! -d .git ]; then
    popd >/dev/null
    error "Thư mục $FLUTTER_ROOT không phải repo git (không có .git)."
    fi

    info "Fetch từ remote..."
    git fetch --all --prune

    # try to checkout branch (create local tracking if needed)
    if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    info "Branch local $BRANCH tồn tại -> checkout"
    git checkout "$BRANCH"
    else
    # try to checkout remote branch
    if git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
        info "Branch remote origin/$BRANCH tồn tại -> tạo local tracking và checkout"
        git checkout -b "$BRANCH" --track "origin/$BRANCH"
    else
        warn "Không tìm thấy branch '$BRANCH' trên remote 'origin'. Bạn vẫn có thể tạo branch mới cục bộ."
        if confirm "Tạo branch cục bộ '$BRANCH' từ HEAD hiện tại?"; then
        git checkout -b "$BRANCH"
        else
        popd >/dev/null
        error "Aborted bởi người dùng."
        fi
    fi
    fi

    info "Hiện tại trên branch: $(git rev-parse --abbrev-ref HEAD)"
    info "Kiểm tra thay đổi local (git status --porcelain):"
    GIT_PORCELAIN=$(git status --porcelain || true)
    if [ -n "$GIT_PORCELAIN" ]; then
    warn "Repo có thay đổi local ngay trước khi pull."
    else
    info "Repo sạch (no local unstaged/untracked changes)."
    fi

    # If user wants to discard all local changes before pull, they can set DISCARD_BEFORE_PULL=1
    # Default behavior: prompt the user to confirm discarding. Non-interactive: set AUTO_CONFIRM=1
    if [ "${DISCARD_BEFORE_PULL:-1}" = "1" ] && [ -n "$GIT_PORCELAIN" ]; then
    warn "DISCARD_BEFORE_PULL=1 được bật - script sẽ xóa sạch mọi thay đổi local trước khi pull."
    if confirm "Bạn CHẮC CHẮN muốn bỏ tất cả thay đổi local (git reset --hard && git clean -fdx) trong $FLUTTER_ROOT? THIS CANNOT BE UNDONE."; then
        info "Thực hiện git reset --hard"
        git reset --hard
        info "Thực hiện git clean -fdx (xóa untracked và ignored files)"
        git clean -fdx
        # refresh status
        GIT_PORCELAIN=$(git status --porcelain || true)
        info "Các thay đổi local đã bị loại bỏ."
    else
        info "Người dùng hủy việc discard. Script sẽ sử dụng autostash fallback để pull."
    fi
    fi

    # Proceed to pull: prefer --rebase --autostash if there are local changes, otherwise normal pull --rebase
    if [ -z "$GIT_PORCELAIN" ]; then
    info "Không có thay đổi local -> pull --rebase origin $BRANCH"
    git pull --rebase origin "$BRANCH"
    else
    info "Có thay đổi local -> thử pull --rebase --autostash origin $BRANCH"
    if git pull --rebase --autostash origin "$BRANCH"; then
        info "Pulled successfully with --autostash"
    else
        warn "--autostash không khả dụng hoặc pull thất bại. Thực hiện stash thủ công -> pull -> pop."
        STASH_MSG="auto-stash-before-pull-$(date -Iseconds)"
        git stash push -u -m "$STASH_MSG" || warn "git stash push thất bại (có thể không có thay đổi)."
        if git pull --rebase origin "$BRANCH"; then
        info "Pulled thành công sau stash"
        else
        error "git pull thất bại sau stash. Kiểm tra network/remote và thử lại."
        fi
        if git stash list | grep -q "$STASH_MSG"; then
        info "Áp lại stash"
        if git stash pop; then
            info "Áp stash thành công"
        else
            error "Xảy ra conflict khi áp stash - vui lòng resolve conflict thủ công và chạy 'git add' + 'git rebase --continue' nếu cần."
        fi
        fi
    fi
    fi

    info "Pull + rebase hoàn tất. Commit gần nhất:"
    git log -n 1 --pretty=format:'%h %s (%ci)'

    popd >/dev/null


    # Ensure flutter exists
    command -v flutter >/dev/null 2>&1 || error "flutter CLI không tìm thấy trên PATH. Cài/đặt flutter trước khi chạy script này."

    # Run flutter clean
    info "Chạy 'flutter clean' trong $FLUTTER_ROOT"
    pushd "$FLUTTER_ROOT" >/dev/null
    if flutter clean; then
    info "flutter clean thành công"
    else
    error "flutter clean thất bại"
    fi
    popd >/dev/null

    # Run flutter pub get
    info "Chạy 'flutter pub get' trong $FLUTTER_ROOT"
    pushd "$FLUTTER_ROOT" >/dev/null
    if flutter pub get; then
    info "flutter pub get thành công"
    else
    error "flutter pub get thất bại"
    fi
    popd >/dev/null

    # Replace Podfile if a Podfile exists in SCRIPT_DIR
    SRC_PODFILE="Podfile"
    DEST_PODFILE="$FLUTTER_ROOT/.ios/Podfile"
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

    # Run flutter build ios-framework
    OUTPUT_DIR="$(abs_path flutter_build)"
    mkdir -p "$OUTPUT_DIR"
    info "Bắt đầu build framework.... => output=$OUTPUT_DIR"
    pushd "$FLUTTER_ROOT" >/dev/null
    if flutter build ios-framework --release --no-debug --no-profile --output="/${OUTPUT_DIR}"; then
    info "Flutter build ios-framework thành công. Output tại: $OUTPUT_DIR"
    else
    error "Flutter build ios-framework thất bại"
    fi
    popd >/dev/null

    # xoá file trùng lặp
    info "Xoá file bị trùng...."
    rm -rf Fire* Goog* FBLPromises* nanopb* Promises* AppAuth*

    # copy đến thư mục lib
    IOS_LIB="$IOS_ROOT/FPTLife/FSS/Libs/Flutter"
    info "Xoá tất cả nội dung cũ trong $IOS_LIB"
    rm -rf "$IOS_LIB"/*

    # Copy tất cả nội dung từ OUTPUT_DIR/Release vào IOS_LIB
    info "Copy framework mới từ $OUTPUT_DIR/Release -> $IOS_LIB"
    cp -R "$OUTPUT_DIR/Release/"* "$IOS_LIB/"

    info "Đã cập nhật Flutter framework trong $IOS_LIB"
fi

# xcode build...
SCHEME="FPTLife_beta"
CONFIGURATION="Release beta"
EXPORT_METHOD="enterprise" # enterprise / ad-hoc / app-store
OUTPUT_IPA_DIR="$(abs_path ipa_build)"
ARCHIVE_PATH="$OUTPUT_IPA_DIR/$SCHEME.xcarchive"
TEAM_ID="7755R4CX4U"
BUNDLE_ID="beta.vn.fpt.fptlife"
PROVISIONING_PROFILE="99f99aa3-67ff-43e7-9213-c4e903e83a27" 
info "build iOS project: $IOS_ROOT"
pushd "$IOS_ROOT" >/dev/null
# -------- 1. Pod update & install --------
# info "Cập nhật pod repo..."
# pod repo update
# info "Cài đặt pod..."
# pod install
# -------- 2. Build archive --------


info "Bắt đầu build IPA ($EXPORT_METHOD) với scheme: $SCHEME"
mkdir -p "$OUTPUT_IPA_DIR"

# Create ExportOptions.plist for automatic signing
cat << EOF > ExportOptions.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>destination</key>
	<string>export</string>
	<key>method</key>
	<string>$EXPORT_METHOD</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>stripSwiftSymbols</key>
	<true/>
	<key>teamID</key>
	<string>$TEAM_ID</string>
	<key>thinning</key>
	<string>&lt;none&gt;</string>
</dict>
</plist>
EOF

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_IPA_DIR"

# Step 1: Clean the project
echo "Cleaning the project..."
xcodebuild clean -scheme "$SCHEME" -configuration "$CONFIGURATION"

# Step 2: Archive the project with automatic signing
echo "Archiving the project..."
xcodebuild archive \
    -scheme "$SCHEME" \
    -sdk iphoneos \
    -configuration "$CONFIGURATION" \
    -archivePath "$ARCHIVE_PATH" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    -allowProvisioningUpdates

# Check if archive succeeded
if [ $? -ne 0 ]; then
    echo "Archive failed. Exiting."
    exit 1
fi

# Step 3: Export the archive to IPA
echo "Exporting to IPA..."
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$OUTPUT_IPA_DIR" \
    -exportOptionsPlist ExportOptions.plist

# Check if export succeeded
if [ $? -ne 0 ]; then
    echo "Export failed. Exiting."
    exit 1
fi

# Cleanup ExportOptions.plist if desired
# rm ExportOptions.plist

echo "IPA built successfully at $OUTPUT_IPA_DIR/$SCHEME.ipa"

popd >/dev/null