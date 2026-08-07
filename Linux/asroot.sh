#!/usr/bin/env bash
#
# grant-sudo-access.sh
# Memberikan akses root (sudo) ke user biasa di Ubuntu
#
# Usage:
#   sudo bash grant-sudo-access.sh
#   sudo bash grant-sudo-access.sh -u namauser
#
# Non-interactive:
#   sudo TARGET_USER=namauser bash grant-sudo-access.sh
#
# Download dari GitHub:
#   wget https://raw.githubusercontent.com/<user>/<repo>/main/grant-sudo-access.sh
#   sudo bash grant-sudo-access.sh
#

set -euo pipefail

TARGET_USER="${TARGET_USER:-}"
LOGFILE="/var/log/grant-sudo-access.log"
NOPASSWD="${NOPASSWD:-n}"   # y = sudo tanpa password (opsional, kurang aman)

log() { echo -e "\e[1;32m[+]\e[0m $1" | tee -a "$LOGFILE"; }
warn() { echo -e "\e[1;33m[!]\e[0m $1" | tee -a "$LOGFILE"; }
err() { echo -e "\e[1;31m[!]\e[0m $1" | tee -a "$LOGFILE"; exit 1; }

# ====== PARSE ARGUMENT ======
while getopts "u:h" opt; do
  case $opt in
    u) TARGET_USER="$OPTARG" ;;
    h)
      echo "Usage: sudo bash $0 [-u namauser]"
      exit 0
      ;;
    *) err "Argument tidak dikenali. Pakai: sudo bash $0 -u namauser" ;;
  esac
done

# ====== CEK ROOT ======
if [[ $EUID -ne 0 ]]; then
  err "Script ini harus dijalankan sebagai root/sudo. Coba: sudo bash $0"
fi

touch "$LOGFILE"

# ====== PILIH USER: EXISTING ATAU BUAT BARU ======
if [[ -z "$TARGET_USER" ]]; then
  echo ""
  echo "=========================================="
  echo " Grant Akses Root (sudo) ke User"
  echo "=========================================="
  read -rp "Masukkan username: " TARGET_USER
fi

if [[ -z "$TARGET_USER" ]]; then
  err "Username tidak boleh kosong."
fi

# Validasi format username Linux
if ! [[ "$TARGET_USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
  err "Format username tidak valid (huruf kecil, angka, underscore, dash; diawali huruf/underscore)."
fi

# ====== CEK USER SUDAH ADA ATAU BELUM ======
if id "$TARGET_USER" &> /dev/null; then
  log "User '$TARGET_USER' sudah ada di sistem."
else
  warn "User '$TARGET_USER' belum ada."
  read -rp "Mau buat user baru '$TARGET_USER' sekarang? (y/N): " CREATE_USER
  CREATE_USER=${CREATE_USER,,}
  if [[ "$CREATE_USER" == "y" || "$CREATE_USER" == "yes" ]]; then
    adduser --gecos "" "$TARGET_USER"
    log "User '$TARGET_USER' berhasil dibuat."
  else
    err "Dibatalkan. User '$TARGET_USER' tidak ditemukan di sistem."
  fi
fi

# ====== CEK SUDAH SUDO ATAU BELUM ======
if groups "$TARGET_USER" | grep -qw "sudo"; then
  warn "User '$TARGET_USER' sudah tergabung di grup 'sudo'. Tidak ada perubahan."
else
  log "Menambahkan '$TARGET_USER' ke grup 'sudo'..."
  usermod -aG sudo "$TARGET_USER"
  log "Berhasil ditambahkan ke grup 'sudo'."
fi

# ====== OPSI: SUDO TANPA PASSWORD (opsional) ======
if [[ -z "${TARGET_USER_NOPASSWD_ASKED:-}" ]]; then
  echo ""
  read -rp "Izinkan '$TARGET_USER' pakai sudo TANPA diminta password? (y/N, default N - lebih aman): " NP
  NOPASSWD=${NP,,}
fi

if [[ "$NOPASSWD" == "y" || "$NOPASSWD" == "yes" ]]; then
  SUDOERS_FILE="/etc/sudoers.d/90-${TARGET_USER}-nopasswd"
  echo "${TARGET_USER} ALL=(ALL) NOPASSWD:ALL" > "$SUDOERS_FILE"
  chmod 440 "$SUDOERS_FILE"
  if visudo -cf "$SUDOERS_FILE" &> /dev/null; then
    log "Sudo tanpa password diaktifkan untuk '$TARGET_USER' (file: $SUDOERS_FILE)."
    warn "PERHATIAN: opsi ini mengurangi keamanan, siapapun yang bisa login sebagai '$TARGET_USER' langsung punya akses root penuh tanpa password."
  else
    rm -f "$SUDOERS_FILE"
    err "Syntax sudoers tidak valid, perubahan dibatalkan demi keamanan."
  fi
else
  log "Sudo tetap butuh password (rekomendasi default)."
fi

# ====== VERIFIKASI ======
log "=========================================="
log " HASIL"
log "=========================================="
log " Username        : $TARGET_USER"
log " Grup            : $(id -nG "$TARGET_USER")"
log " Sudo NOPASSWD    : $([[ "$NOPASSWD" == "y" || "$NOPASSWD" == "yes" ]] && echo "Ya" || echo "Tidak")"
log "=========================================="
log " Cara pakai: login sebagai '$TARGET_USER' lalu jalankan perintah dengan awalan 'sudo'."
log " Contoh: sudo apt update"
log ""
log " CATATAN: user perlu logout/login ulang (atau buka sesi shell baru)"
log " agar keanggotaan grup 'sudo' langsung berlaku di sesi aktif."
