#!/bin/bash
set -e

PANEL="/var/www/pterodactyl"
MW="$PANEL/app/Http/Middleware/AntiRusuh.php"
KERNEL="$PANEL/app/Http/Kernel.php"
ROUTE_ADMIN="$PANEL/routes/admin.php"

menu() {
    clear
    echo "================================="
    echo "     ANTI RUSUH FINAL v13"
    echo "================================="
    echo "1) Install"
    echo "2) Uninstall"
    echo -n "Pilih: "
    read pilih
}

install_antirusuh() {
    echo "Masukkan ID owner yang boleh buka /admin:"
    read OWNER_ID

    echo "Menulis .env..."
    sed -i '/ANTIRUSUH_OWNER/d' $PANEL/.env
    echo "ANTIRUSUH_OWNER=$OWNER_ID" >> $PANEL/.env

    echo "Membuat middleware..."
cat > $MW << 'EOF'
<?php

namespace Pterodactyl\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpKernel\Exception\HttpException;

class AntiRusuh
{
    public function handle(Request $request, Closure $next)
    {
        $owner = env('ANTIRUSUH_OWNER');
        $user = $request->user();

        if (!$user || $user->id != $owner) {
            throw new HttpException(403, 'Forbidden');
        }
        return $next($request);
    }
}
EOF

    echo "Register middleware ke Kernel.php..."
    sed -i "/protected \$middlewareAliases = \[/a\        'antirusuh' => \\Pterodactyl\\Http\\Middleware\\AntiRusuh::class," $KERNEL

    echo "Patch route admin..."
    # Tambah group sebelum isi admin.php
    sed -i "1s/^/Route::middleware(['antirusuh'])->group(function () {\n/" $ROUTE_ADMIN
    # Tambah penutup group di akhir file
    echo "});" >> $ROUTE_ADMIN

    echo "Clear cache..."
    cd $PANEL
    php artisan config:clear
    php artisan route:clear

    echo ""
    echo "======================================"
    echo "  ✔ ANTI RUSUH v13 AKTIF"
    echo "  ✔ Hanya ID $OWNER_ID yang bisa buka /admin"
    echo "======================================"
}

uninstall_antirusuh() {
    echo "Menghapus middleware..."
    rm -f $MW

    echo "Membersihkan Kernel..."
    sed -i "/'antirusuh'/d" $KERNEL

    echo "Memperbaiki route admin..."
    sed -i "/Route::middleware(\['antirusuh'\])->group(function () {/d" $ROUTE_ADMIN
    sed -i "/});/d" $ROUTE_ADMIN

    sed -i '/ANTIRUSUH_OWNER/d' $PANEL/.env

    echo "Clear cache..."
    cd $PANEL
    php artisan config:clear
    php artisan route:clear

    echo ""
    echo "======================================"
    echo "  ✔ ANTI RUSUH v13 DIHAPUS"
    echo "======================================"
}

menu

if [ "$pilih" = "1" ]; then
    install_antirusuh
elif [ "$pilih" = "2" ]; then
    uninstall_antirusuh
else
    echo "Pilihan tidak valid."
fi
