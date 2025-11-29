#!/bin/bash
set -e

OWNER_FILE="/var/www/pterodactyl/.env"
MW_PATH="/var/www/pterodactyl/app/Http/Middleware/AntiRusuh.php"
KERNEL="/var/www/pterodactyl/app/Http/Kernel.php"
ROUTE="/var/www/pterodactyl/routes/admin.php"

install_antirusuh() {
    echo "=== INSTALL ANTI RUSUH ==="

    read -p "Masukkan ID Owner Utama: " OWNER

    # Tambahkan ENV
    if grep -q "ANTIRUSUH_OWNER" $OWNER_FILE; then
        sed -i "s/ANTIRUSUH_OWNER=.*/ANTIRUSUH_OWNER=$OWNER/" $OWNER_FILE
    else
        echo "ANTIRUSUH_OWNER=$OWNER" >> $OWNER_FILE
    fi
    echo "[OK] Menambah ENV"

    # Buat Middleware
    cat > $MW_PATH << 'EOF'
<?php

namespace Pterodactyl\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpKernel\Exception\AccessDeniedHttpException;

class AntiRusuh
{
    public function handle(Request $request, Closure $next)
    {
        $owner = env('ANTIRUSUH_OWNER', 1);
        $user = $request->user();

        if (!$user || $user->id != $owner) {
            throw new AccessDeniedHttpException("Access Denied.");
        }

        return $next($request);
    }
}
EOF
    echo "[OK] Middleware dibuat"

    # Registrasi middleware ke Kernel
    if ! grep -q "AntiRusuh" $KERNEL; then
        sed -i "/VerifyReCaptcha::class,/a \        'antirusuh' => \\Pterodactyl\\Http\\Middleware\\AntiRusuh::class," $KERNEL
        echo "[OK] Middleware didaftarkan ke Kernel"
    fi

    # Patch routes admin
    if ! grep -q "antirusuh" $ROUTE; then
        sed -i "1s/^/Route::middleware(['antirusuh'])->group(function () {\n/" $ROUTE
        echo "});" >> $ROUTE
        echo "[OK] Proteksi admin ditambahkan"
    fi

    cd /var/www/pterodactyl
    php artisan cache:clear
    php artisan route:clear

    echo "=== ANTI RUSUH AKTIF ==="
    echo "Hanya ID $OWNER yg bisa buka /admin"
}

uninstall_antirusuh() {
    echo "=== UNINSTALL ANTI RUSUH ==="

    # Hapus ENV
    sed -i "/ANTIRUSUH_OWNER/d" $OWNER_FILE
    echo "[OK] ENV dibersihkan"

    # Hapus middleware
    rm -f $MW_PATH
    echo "[OK] Middleware dihapus"

    # Hapus dari Kernel
    sed -i "/antirusuh/d" $KERNEL
    echo "[OK] Kernel dibersihkan"

    # Kembalikan route admin
    sed -i "/Route::middleware(\['antirusuh'\])->group(function () {/,/});/d" $ROUTE
    echo "[OK] Proteksi admin dihapus"

    cd /var/www/pterodactyl
    php artisan cache:clear
    php artisan route:clear

    echo "=== ANTI RUSUH DIHAPUS & PANEL NORMAL ==="
}

echo "==============================="
echo "     ANTI RUSUH FINAL V13"
echo "==============================="
echo "1) Install"
echo "2) Uninstall"
read -p "Pilih: " PIL

if [ "$PIL" == "1" ]; then
    install_antirusuh
elif [ "$PIL" == "2" ]; then
    uninstall_antirusuh
else
    echo "Pilihan tidak valid."
fi
