#!/bin/bash

# ====== CONFIG ======
SMTP_HOST="smtp.office365.com"
SMTP_PORT="587"

SMTP_USER="trucpn3@fpt.com"
SMTP_PASS=""

MAIL_FROM="$SMTP_USER"
MAIL_TO="trucpham.work@gmail.com"
MAIL_SUBJECT="Test gửi mail HTML Outlook"

HTML_FILE="mail_template.html"
# ====================

# Kiểm tra file HTML
if [ ! -f "$HTML_FILE" ]; then
  echo "❌ Không tìm thấy file $HTML_FILE"
  exit 1
fi

# Gửi mail
curl --silent --show-error --fail \
  --url "smtp://${SMTP_HOST}:${SMTP_PORT}" \
  --ssl-reqd \
  --mail-from "$MAIL_FROM" \
  --mail-rcpt "$MAIL_TO" \
  --user "$SMTP_USER:$SMTP_PASS" \
  --upload-file - <<EOF
From: $MAIL_FROM
To: $MAIL_TO
Subject: $MAIL_SUBJECT
MIME-Version: 1.0
Content-Type: text/html; charset="UTF-8"

$(cat "$HTML_FILE")
EOF

if [ $? -eq 0 ]; then
  echo "✅ Gửi mail thành công"
else
  echo "❌ Gửi mail thất bại"
fi
