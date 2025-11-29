#!/bin/bash
set -e

PTERO="/var/www/pterodactyl"

banner(){
    echo "======================================"
    echo "        ANTI RUSUH FINAL – ACTIVE"
    echo "    (Tanpa edit admin.php / kernel)"
    echo "======================================"
}

install(){
    banner
    read -p "Masukkan ID Owner Utama: " OWNER

    mkdir -p "$PTERO/routes"

    cat > "$PTERO/routes/antirusuh.php" <<EOF
<?php

use Illuminate\Support\Facades\Route;

Route::middleware([])->group(function () {

    \$owner = $OWNER;

    // Proteksi semua halaman admin panel
    Route::any('/admin/{any?}', function () use (\$owner) {

        \$u = request()->user();
        if (!\$u) abort(403, "ngapain wok");

        \$path = request()->path();

        \$block = [
            "admin/nodes",
            "admin/servers",
            "admin/databases",
            "admin/locations",
            "admin/mounts",
            "admin/nests",
        ];

        foreach (\$block as \$p){
            if (strpos(\$path, \$p) === 0 && \$u->id != \$owner && empty(\$u->root_admin)) {
                abort(403, "ngapain wok");
            }
        }
    })->where('any', '.*');

    // Lindungi panel server user
    Route::matched(function (\$event) use (\$owner) {

        \$req = \$event->request;
        \$u = \$req->user();
        if (!\$u) return;

        \$srv = \$req->route()->parameter('server');

        if (\$srv) {
            if (\$srv->owner_id != \$u->id && empty(\$u->root_admin) && \$u->id != \$owner) {
                abort(403, "ngapain wok");
            }
        }
    });

});
EOF

    # DAFTARKAN ROUTE BARU KE RouteServiceProvider
    if ! grep -q "antirusuh.php" "$PTERO/app/Providers/RouteServiceProvider.php"; then
        sed -i "/public function map()/a \        require __DIR__.'/../../routes/antirusuh.php';" "$PTERO/app/Providers/RouteServiceProvider.php"
    fi

    cd $PTERO
    php artisan route:clear
    php artisan cache:clear
    php artisan optimize:clear

    echo ""
    echo "======================================"
    echo "   Anti Rusuh FINAL Terpasang!"
    echo "   Proteksi Admin & Server Aktif"
    echo "======================================"
}

uninstall(){
    banner

    rm -f "$PTERO/routes/antirusuh.php"

    sed -i "/antirusuh/d" "$PTERO/app/Providers/RouteServiceProvider.php"

    cd $PTERO
    php artisan route:clear
    php artisan cache:clear

    echo ""
    echo "======================================"
    echo "   Anti Rusuh FINAL DIHAPUS!"
    echo "======================================"
}

menu(){
    banner
    echo "1) Install"
    echo "2) Uninstall"
    echo "3) Exit g"
    read -p "Pilih: " x

    [ "$x" = 1 ] && install
    [ "$x" = 2 ] && uninstall
}

menu
