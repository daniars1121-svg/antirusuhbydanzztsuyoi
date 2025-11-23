#!/bin/bash
PANEL="/var/www/pterodactyl"

echo "=== CEK ANTI-RUSUH ==="

# 1. CEK FILE MIDDLEWARE
if [ -f "$PANEL/app/Http/Middleware/AntiRusuh.php" ]; then
    echo "[OK] Middleware AntiRusuh ada."
else
    echo "[ERROR] Middleware AntiRusuh TIDAK ADA!"
    echo "Solusi: Install ulang antirusuh.sh"
fi

# 2. CEK REGISTER DI KERNEL
if grep -q "AntiRusuh" "$PANEL/app/Http/Kernel.php"; then
    echo "[OK] Kernel sudah didaftarkan."
else
    echo "[ERROR] Kernel BELUM terdaftar!"
    echo "Solusi: Tambahkan ke Kernel.php bagian middlewareAliases"
    echo "'antirusuh' => App\\Http\\Middleware\\AntiRusuh::class,"
fi

# 3. CEK CONFIG
if [ -f "$PANEL/config/antirusuh.php" ]; then
    echo "[OK] File config antirusuh ditemukan."
else
    echo "[ERROR] Config AntiRusuh tidak ditemukan!"
fi

# 4. CEK ISI CONFIG OWNERS
echo "Owner saat ini:"
grep -n "'owners'" -n "$PANEL/config/antirusuh.php"
grep -n "'" "$PANEL/config/antirusuh.php" | sed -n '2p'

# 5. CEK DATABASE DARI ENV
DB_USER=$(grep DB_USERNAME "$PANEL/.env" | cut -d= -f2)
DB_PASS=$(grep DB_PASSWORD "$PANEL/.env" | cut -d= -f2)
DB_NAME=$(grep DB_DATABASE "$PANEL/.env" | cut -d= -f2)

echo "== Cek Database =="
echo "User  : $DB_USER"
echo "Pass  : $DB_PASS"
echo "DB    : $DB_NAME"

mysql -u"$DB_USER" -p"$DB_PASS" -e "USE $DB_NAME; SELECT id, username FROM users LIMIT 5;" >/dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "[OK] Database bisa diakses."
else
    echo "[ERROR] Database TIDAK BISA DIAKSES!"
    echo "Solusi: Periksa username/password di .env"
fi

# 6. CEK LOG ERROR LARAVEL
echo "== Cek Error Laravel (20 baris terakhir) =="
tail -n 20 "$PANEL/storage/logs/laravel.log" | grep -i "rusuh\|middleware\|403\|error"

# 7. CEK ROUTE BERPENGARUH ATAU TIDAK
echo "== CEK BLOKIR ROUTE TEST =="
curl -I http://localhost/admin/nodes >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "[PERINGATAN] Route admin/nodes MASIH BISA DIAKSES!"
else
    echo "[OK] Route admin/nodes TERBLOKIR oleh AntiRusuh."
fi

echo ""
echo "=== CEK SELESAI ==="
echo "Kalau ada ERROR → kirim screenshot hasilnya."
