#!/usr/bin/env bash
#
# deploy-phpmyadmin-2004.sh
# Deploy phpMyAdmin di Ubuntu 20.04 (LAMP stack: Apache + MySQL + PHP 7.4)
#
# Usage:
#   sudo bash deploy-phpmyadmin-2004.sh
#
# Download langsung dari GitHub:
#   wget https://raw.githubusercontent.com/<user>/<repo>/main/deploy-phpmyadmin-2004.sh
#   sudo bash deploy-phpmyadmin-2004.sh
#
# atau via git:
#   git clone https://github.com/<user>/<repo>.git
#   cd <repo> && sudo bash deploy-phpmyadmin-2004.sh
#

set -euo pipefail

# ====== CONFIG (edit sesuai kebutuhan / bisa dioverride via env var) ======
PMA_VERSION="${PMA_VERSION:-5.2.1}"          # versi phpMyAdmin
MYSQL_ROOT_PASS="${MYSQL_ROOT_PASS:-}"       # kosongkan = auto-generate
PMA_BLOWFISH="${PMA_BLOWFISH:-}"             # kosongkan = auto-generate
APACHE_PORT="${APACHE_PORT:-80}"
LOGFILE="/var/log/deploy-phpmyadmin.log"

# ====== HELPER ======
log() { echo -e "\e[1;32m[+]\e[0m $1" | tee -a "$LOGFILE"; }
err() { echo -e "\e[1;31m[!]\e[0m $1" | tee -a "$LOGFILE"; exit 1; }

# ====== CEK ROOT ======
if [[ $EUID -ne 0 ]]; then
  err "Script ini harus dijalankan sebagai root. Coba: sudo bash $0"
fi

# ====== CEK OS ======
if ! grep -qi "20.04" /etc/os-release 2>/dev/null; then
  echo -e "\e[1;33m[!] Warning: OS bukan Ubuntu 20.04, lanjut dengan risiko sendiri.\e[0m"
fi

touch "$LOGFILE"

# ====== OPSI GANTI PASSWORD MYSQL ROOT ======
# Kalau MYSQL_ROOT_PASS sudah diisi lewat env var, skip prompt (untuk mode non-interactive/CI).
if [[ -z "$MYSQL_ROOT_PASS" ]]; then
  echo ""
  echo "=========================================="
  echo " Konfigurasi Password MySQL Root"
  echo "=========================================="
  read -rp "Mau set password MySQL root sendiri? (y/N): " CHANGE_PASS
  CHANGE_PASS=${CHANGE_PASS,,}  # lowercase

  if [[ "$CHANGE_PASS" == "y" || "$CHANGE_PASS" == "yes" ]]; then
    while true; do
      read -rsp "Masukkan password baru: " PASS1; echo ""
      read -rsp "Ulangi password: " PASS2; echo ""
      if [[ "$PASS1" != "$PASS2" ]]; then
        echo -e "\e[1;31m[!] Password tidak sama, coba lagi.\e[0m"
        continue
      fi
      if [[ ${#PASS1} -lt 8 ]]; then
        echo -e "\e[1;33m[!] Password terlalu pendek (min 8 karakter), coba lagi.\e[0m"
        continue
      fi
      MYSQL_ROOT_PASS="$PASS1"
      unset PASS1 PASS2
      break
    done
    log "Password custom akan digunakan."
  else
    log "Password akan di-generate otomatis (random)."
  fi
fi

log "Update package list..."
apt update -y >> "$LOGFILE" 2>&1

log "Install dependencies dasar (curl, wget, unzip, software-properties-common)..."
apt install -y curl wget unzip software-properties-common ca-certificates lsb-release apt-transport-https gnupg2 openssl >> "$LOGFILE" 2>&1

# ====== INSTALL APACHE ======
if ! command -v apache2 &> /dev/null; then
  log "Install Apache2..."
  apt install -y apache2 >> "$LOGFILE" 2>&1
else
  log "Apache2 sudah terinstall, skip."
fi
systemctl enable apache2 >> "$LOGFILE" 2>&1
systemctl start apache2

# ====== INSTALL MYSQL ======
if ! command -v mysql &> /dev/null; then
  log "Install MySQL Server..."
  DEBIAN_FRONTEND=noninteractive apt install -y mysql-server >> "$LOGFILE" 2>&1
else
  log "MySQL sudah terinstall, skip."
fi
systemctl enable mysql >> "$LOGFILE" 2>&1
systemctl start mysql

# Fallback: kalau sampai sini masih kosong (mis. dijalankan non-interactive tanpa env var), generate random
if [[ -z "$MYSQL_ROOT_PASS" ]]; then
  MYSQL_ROOT_PASS=$(openssl rand -base64 18)
  log "MySQL root password di-generate otomatis (lihat di akhir output)."
fi

# Set password root MySQL (aman untuk fresh install / idempotent pakai ALTER USER)
log "Konfigurasi MySQL root user & auth plugin..."
mysql --user=root <<-EOSQL 2>>"$LOGFILE" || true
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASS}';
FLUSH PRIVILEGES;
EOSQL

# ====== INSTALL PHP + EXTENSIONS ======
log "Install PHP dan module yang dibutuhkan phpMyAdmin..."
apt install -y php php-mbstring php-zip php-gd php-json php-curl php-xml php-mysql php-bcmath libapache2-mod-php >> "$LOGFILE" 2>&1

PHP_VER=$(php -v | head -n1 | awk '{print $2}' | cut -d. -f1,2)
log "PHP terinstall versi: $PHP_VER"

# ====== DOWNLOAD PHPMYADMIN ======
log "Download phpMyAdmin v${PMA_VERSION}..."
cd /tmp
rm -rf phpMyAdmin-*
wget -q "https://files.phpmyadmin.net/phpMyAdmin/${PMA_VERSION}/phpMyAdmin-${PMA_VERSION}-all-languages.tar.gz" \
  -O phpmyadmin.tar.gz || err "Gagal download phpMyAdmin versi ${PMA_VERSION}, cek versi di https://www.phpmyadmin.net/downloads/"

log "Extract phpMyAdmin..."
tar -xzf phpmyadmin.tar.gz
rm -rf /usr/share/phpmyadmin
mv "phpMyAdmin-${PMA_VERSION}-all-languages" /usr/share/phpmyadmin

# ====== CONFIG PHPMYADMIN ======
log "Setup folder tmp untuk phpMyAdmin..."
mkdir -p /usr/share/phpmyadmin/tmp
chown -R www-data:www-data /usr/share/phpmyadmin
chmod 755 /usr/share/phpmyadmin/tmp

log "Generate config.inc.php..."
if [[ -z "$PMA_BLOWFISH" ]]; then
  PMA_BLOWFISH=$(openssl rand -base64 32)
fi

cp /usr/share/phpmyadmin/config.sample.inc.php /usr/share/phpmyadmin/config.inc.php
sed -i "s|\$cfg\['blowfish_secret'\] = '';|\$cfg['blowfish_secret'] = '${PMA_BLOWFISH}';|" /usr/share/phpmyadmin/config.inc.php

# Tambahkan config storage untuk fitur lanjutan (opsional tapi disarankan)
cat >> /usr/share/phpmyadmin/config.inc.php <<'EOPHP'

/* Konfigurasi tmp directory */
$cfg['TempDir'] = '/usr/share/phpmyadmin/tmp';
EOPHP

# ====== KONFIGURASI APACHE UNTUK PHPMYADMIN ======
log "Buat Apache config untuk phpMyAdmin..."
cat > /etc/apache2/conf-available/phpmyadmin.conf <<'EOAPACHE'
Alias /phpmyadmin /usr/share/phpmyadmin

<Directory /usr/share/phpmyadmin>
    Options SymLinksIfOwnerMatch
    DirectoryIndex index.php
    Require all granted

    <IfModule mod_php.c>
        AddType application/x-httpd-php .php
    </IfModule>

    <FilesMatch "\.php$">
        SetHandler application/x-httpd-php
    </FilesMatch>
</Directory>

<Directory /usr/share/phpmyadmin/tmp>
    Require all denied
</Directory>
EOAPACHE

a2enconf phpmyadmin >> "$LOGFILE" 2>&1
a2enmod rewrite >> "$LOGFILE" 2>&1

log "Restart Apache..."
systemctl restart apache2

# ====== FIREWALL (UFW, kalau aktif) ======
if command -v ufw &> /dev/null; then
  if ufw status | grep -q "Status: active"; then
    log "UFW aktif, allow port Apache..."
    ufw allow "Apache Full" >> "$LOGFILE" 2>&1 || ufw allow "${APACHE_PORT}/tcp" >> "$LOGFILE" 2>&1
  fi
fi

# ====== CLEANUP ======
rm -f /tmp/phpmyadmin.tar.gz

# ====== SUMMARY ======
SERVER_IP=$(hostname -I | awk '{print $1}')

log "=========================================="
log " DEPLOY PHPMYADMIN SELESAI"
log "=========================================="
log " URL akses     : http://${SERVER_IP}/phpmyadmin"
log " MySQL root pw : ${MYSQL_ROOT_PASS}"
log " Login phpMyAdmin pakai user 'root' + password di atas"
log "=========================================="
log " CATATAN KEAMANAN:"
log " - Simpan/backup password di atas lalu hapus dari log:"
log "   sudo shred -u ${LOGFILE}"
log " - Untuk production, disarankan pasang SSL (Let's Encrypt/certbot)"
log "   dan restrict akses /phpmyadmin via IP whitelist di Apache config."
log " - Jangan pakai root MySQL untuk login harian, buat user terpisah."
log "=========================================="
