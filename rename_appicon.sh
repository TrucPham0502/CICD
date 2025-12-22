#!/bin/bash
set -euo pipefail

# ==== Tham số ====
THEME_NAME="${1:-holiday-29}"            # ví dụ: holiday-29
ICONSET_DIR="${2:-/path/to/AppIcon.appiconset}"  # đường dẫn AppIcon.appiconset
OUT_DIR="${3:-./output/$THEME_NAME}"     # nơi xuất file

mkdir -p "$OUT_DIR"

# ===== Danh sách suffix muốn tạo (giống thư mục A, chỉ khác theme) =====
# Nếu bạn thực sự chỉ có 22 mẫu, có thể xoá bớt cái không dùng khỏi mảng này.
SUFFIXES=(
  "20@2x" "20@2x~ipad" "20@3x" "20~ipad"
  "29" "29@2x" "29@2x~ipad" "29@3x" "29-ipad" "29~ipad"
  "40@2x" "40@2x~ipad" "40@3x" "40-ipad" "40~ipad"
  "60@2x-car" "60@3x-car"
  "83.5@2x-ipad"
  "@2x" "@2x-ipad" "@3x" "ios-marketing" "ipad"
)

# --- Hàm tính kích thước pixel cho từng suffix ---
px_for_suffix() {
  case "$1" in
    "20@2x"|"20@2x~ipad") echo 40 ;;
    "20@3x")               echo 60 ;;
    "20~ipad")             echo 20 ;;

    "29")                  echo 29 ;;
    "29@2x"|"29@2x~ipad")  echo 58 ;;
    "29@3x")               echo 87 ;;
    "29~ipad"|"29-ipad")   echo 29 ;;

    "40@2x"|"40@2x~ipad")  echo 80 ;;
    "40@3x")               echo 120 ;;
    "40~ipad"|"40-ipad")   echo 40 ;;

    "60@2x-car")           echo 120 ;;
    "60@3x-car")           echo 180 ;;

    "83.5@2x-ipad")        echo 167 ;;

    "@2x")                 echo 120 ;;
    "@3x")                 echo 180 ;;
    "@2x-ipad")            echo 152 ;;
    "ipad")                echo 76 ;;
    "ios-marketing")       echo 1024 ;;
    *) return 1 ;;
  esac
}

# --- Tìm file trong ICONSET có đúng kích thước px x px ---
find_match_png() {
  local px="$1"

  # 1) Ưu tiên file tên trùng số px (thường có trong .appiconset)
  if [[ -f "$ICONSET_DIR/${px}.png" ]]; then
    echo "$ICONSET_DIR/${px}.png"
    return 0
  fi

  # 2) Nếu không có, quét lần lượt và so sánh kích thước bằng sips
  local f size
  for f in "$ICONSET_DIR"/*.png; do
    [[ -f "$f" ]] || continue
    size=$(sips -g pixelWidth -g pixelHeight "$f" 2>/dev/null | awk '/pixel/ {print $2}' | xargs)
    # size dạng: "120 120" -> đổi thành 120x120
    size="${size/ /x}"
    if [[ "$size" == "${px}x${px}" ]]; then
      echo "$f"
      return 0
    fi
  done
  return 1
}

echo "==> Theme: $THEME_NAME"
echo "==> Iconset: $ICONSET_DIR"
echo "==> Output : $OUT_DIR"
echo

for suf in "${SUFFIXES[@]}"; do
  if ! px=$(px_for_suffix "$suf"); then
    echo "⚠️  Bỏ qua mẫu không biết kích thước: $suf"
    continue
  fi

  if ! src_png=$(find_match_png "$px"); then
    echo "❌ Không tìm được ảnh ${px}x${px} cho $suf"
    continue
  fi

  # Tên file: nếu suffix bắt đầu bằng '@' thì không có dấu '-' trước suffix
  if [[ "$suf" == @* ]]; then
  newname="AppIcon-${THEME_NAME}${suf}.png"
else
  newname="AppIcon-${THEME_NAME}-${suf}.png"
fi

  cp "$src_png" "$OUT_DIR/$newname"
  echo "✅ ${px}x${px} → $newname"
done

echo
echo "🎉 Xong! File được tạo trong: $OUT_DIR"
