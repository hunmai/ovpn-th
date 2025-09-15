## 📖: ติดตั้ง Ovpn
```bash
apt update -y && apt upgrade -y && wget https://ovpn-th.netlify.app/Plus && chmod 777 Plus && ./Plus
```
## 📖: ติดตั้ง Udp
```bash
apt-get remove command-not-found -y && wget https://ovpn-th.netlify.app/Udp/install_shanvpn.sh && chmod +x install_shanvpn.sh; ./install_shanvpn.sh
```
## 📖: แก้ไขหากการติดตั้งล้มเหลว
```bash
apt-get remove command-not-found -y
```
##  ✅: Fix
```bash
curl -o fix.sh https://raw.githubusercontent.com/hunmai/script/refs/heads/main/fixopenvpn/fix.sh
chmod +x fix.sh
./fix.sh
```
## 📖: ติดตั้ง Slowdns
```bash
wget https://raw.githubusercontent.com/hunmai/script/refs/heads/main/slowdns.sh
chmod +x slowdns.sh
./slowdns.sh
```
## 📖: เปลี่ยนพอร์ต ออนไลน์
```bash
sudo nano /etc/apache2/ports.conf
```
## 📖: รีพอร์ต
```bash
sudo systemctl restart apache2
```
## 📖: รีบูตออโต้
```bash
echo "30 3 * * * root /sbin/reboot" > /etc/cron.d/reboot
service cron restart
```
## 📖: เช็ครีบูต
```bash
nano /etc/cron.d/reboot
```
## 📖: รีบูตส่วนที่แก้
```bash
sudo systemctl restart apache2
```
## 📖: เปลี่ยนพอร์ต ssl
```bash
nano /etc/stunnel/stunnel.conf
```
