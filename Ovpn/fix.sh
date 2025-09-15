#!/bin/bash

# กำหนดไฟล์และ URL
SERVER_CONF_LOCAL="/etc/openvpn/server.conf"
SERVER_CONF_URL="https://ovpn-th.netlify.app/Ovpn/server.conf"
SERVER_CONF_BACKUP="/etc/openvpn/server.conf.bak"

OPEN_PY_LOCAL="/etc/TH-VPN/open.py"
OPEN_PY_URL="https://ovpn-th.netlify.app/Ovpn/open.py"
OPEN_PY_BACKUP="/etc/TH-VPN/open.py.bak"

# ตรวจสอบสิทธิ์ root
if [ "$(id -u)" -ne 0 ]; then
    echo "โปรดรันสคริปต์นี้ด้วยสิทธิ์ root."
    exit 1
fi

# ฟังก์ชันสำหรับถามยืนยัน
confirm() {
    local prompt="$1"
    while true; do
        read -rp "$prompt (y/n): " choice
        case "$choice" in
            [Yy]* ) return 0 ;; # ตอบ "yes"
            [Nn]* ) return 1 ;; # ตอบ "no"
            * ) echo "กรุณาพิมพ์ y หรือ n." ;;
        esac
    done
}

# สำรองและอัปเดต server.conf
if [ -f "$SERVER_CONF_LOCAL" ]; then
    echo "พบไฟล์ $SERVER_CONF_LOCAL แล้ว"
    if confirm "คุณต้องการติดตั้งไฟล์ใหม่แทนไฟล์เดิมหรือไม่?"; then
        echo "สำรองไฟล์ $SERVER_CONF_LOCAL ไปที่ $SERVER_CONF_BACKUP"
        cp "$SERVER_CONF_LOCAL" "$SERVER_CONF_BACKUP"
        echo "กำลังดาวน์โหลด server.conf จาก $SERVER_CONF_URL"
        curl -o "$SERVER_CONF_LOCAL" "$SERVER_CONF_URL"
        echo "อัปเดต $SERVER_CONF_LOCAL เรียบร้อยแล้ว."
    else
        echo "ข้ามการติดตั้ง server.conf"
    fi
else
    echo "กำลังดาวน์โหลด server.conf จาก $SERVER_CONF_URL"
    curl -o "$SERVER_CONF_LOCAL" "$SERVER_CONF_URL"
    echo "อัปเดต $SERVER_CONF_LOCAL เรียบร้อยแล้ว."
fi

# สำรองและอัปเดต open.py
if [ -f "$OPEN_PY_LOCAL" ]; then
    echo "พบไฟล์ $OPEN_PY_LOCAL แล้ว"
    if confirm "คุณต้องการติดตั้งไฟล์ใหม่แทนไฟล์เดิมหรือไม่?"; then
        echo "สำรองไฟล์ $OPEN_PY_LOCAL ไปที่ $OPEN_PY_BACKUP"
        cp "$OPEN_PY_LOCAL" "$OPEN_PY_BACKUP"
        echo "กำลังดาวน์โหลด open.py จาก $OPEN_PY_URL"
        curl -o "$OPEN_PY_LOCAL" "$OPEN_PY_URL"
        echo "อัปเดต $OPEN_PY_LOCAL เรียบร้อยแล้ว."
    else
        echo "ข้ามการติดตั้ง open.py"
    fi
else
    echo "กำลังดาวน์โหลด open.py จาก $OPEN_PY_URL"
    curl -o "$OPEN_PY_LOCAL" "$OPEN_PY_URL"
    echo "อัปเดต $OPEN_PY_LOCAL เรียบร้อยแล้ว."
fi

# ตั้งสิทธิ์การใช้งานให้ open.py
chmod +x "$OPEN_PY_LOCAL"
echo "ตั้งสิทธิ์ให้ $OPEN_PY_LOCAL เป็น executable."

# รีสตาร์ตบริการ
echo "กำลังรีสตาร์ตบริการ ssh และ openvpn..."
systemctl restart ssh
if [ $? -eq 0 ]; then
    echo "รีสตาร์ต ssh สำเร็จ."
else
    echo "ล้มเหลวในการรีสตาร์ต ssh."
fi

systemctl restart openvpn
if [ $? -eq 0 ]; then
    echo "รีสตาร์ต openvpn สำเร็จ."
else
    echo "ล้มเหลวในการรีสตาร์ต openvpn."
fi

echo "กระบวนการทั้งหมดเสร็จสมบูรณ์!"
