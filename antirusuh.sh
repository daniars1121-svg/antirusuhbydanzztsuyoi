#!/bin/bash

PANEL="/var/www/pterodactyl"
MW="$PANEL/app/Http/Middleware/AntiRusuh.php"
ADMINROUTE="$PANEL/routes/admin.php"

install_ar() {
    echo "[+] Installing Anti Rusuh V12 SAFE..."

    read -p "Masukkan ID Owner Utama: " OWNER

    echo "[+] Membuat middleware..."
    cat > $MW << 'EOF'
<?php

namespace Pterodactyl\Http\Middleware;

use Closure;
use Illuminate\Support\Facades\Auth;

class AntiRusuh
{
    public function handle($request, Closure $next)
    {
        $owner = env('ANTIRUSUH_OWNER');

        if (!$owner) {
            return $next($request);
        }

        $user = Auth::user();

        if (!$user || $user->id != $owner) {
            return response("Forbidden", 403);
        }

        return $next($request);
    }
}
EOF

    echo "[+] Set env..."
    sed -i '/ANTIRUSUH_OWNER/d' $PANEL/.env
    echo "ANTIRUSUH_OWNER=$OWNER" >> $PANEL/.env

    echo "[+] Patch admin.php (NO provider)..."
    if ! grep -q "AntiRusuh" $ADMINROUTE; then
        sed -i "1s|^|use Pterodactyl\\Http\\Middleware\\AntiRusuh;\nRoute::middleware([AntiRusuh::class])->group(function() {\n|" $ADMINROUTE
        echo "});" >> $ADMINROUTE
    fi

    echo "[+] Cache clear..."
    cd $PANEL
    php artisan optimize:clear

    echo "=============================="
    echo " ANTI RUSUH V12 AKTIF ✔"
    echo " Hanya ID $OWNER bisa buka /admin"
    echo "=============================="
}

uninstall_ar() {
    echo "[+] Uninstall Anti Rusuh V12..."

    rm -f $MW
    sed -i '/ANTIRUSUH_OWNER/d' $PANEL/.env

    sed -i '/AntiRusuh/d' $ADMINROUTE
    sed -i '/group(function()/d' $ADMINROUTE
    sed -i '/});$/d' $ADMINROUTE

    cd $PANEL
    php artisan optimize:clear

    echo "[✓] Anti Rusuh V12 dihapus & panel aman."
}

echo "=============================="
echo "   ANTI RUSUH FINAL V12 SAFE"
echo "=============================="
echo "1) Install"
echo "2) Uninstall"
read -p "Pilih: " P

if [ "$P" == "1" ]; then
    install_ar
elif [ "$P" == "2" ]; then
    uninstall_ar
else
    echo "Pilihan tidak valid."
fi
