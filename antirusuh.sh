#!/bin/bash
set -e

PTERO="/var/www/pterodactyl"

banner() {
    echo "====================================="
    echo "  ANTI RUSUH FINAL — FULL WORK"
    echo "  Compatible semua versi Pterodactyl"
    echo "====================================="
}

install() {
    banner
    read -p "Masukkan ID Owner: " OWNER

    echo "[INFO] Membuat middleware AntiRusuh..."
    mkdir -p $PTERO/app/Http/Middleware

cat > $PTERO/app/Http/Middleware/AntiRusuh.php <<EOF
<?php

namespace Pterodactyl\Http\Middleware;
use Closure;

class AntiRusuh
{
    public function handle(\$req, Closure \$next)
    {
        \$u = \$req->user();
        if (!\$u) return \$next(\$req);

        \$owner = $OWNER;
        \$path = ltrim(\$req->path(), '/');

        if (str_starts_with(\$path, "admin")) {
            if (\$u->id != \$owner && !\$u->root_admin) {
                abort(403, "ngapain wok");
            }
        }

        return \$next(\$req);
    }
}
EOF

    echo "[INFO] Membuat admin-wrapper.php..."
cat > $PTERO/routes/admin-wrapper.php <<EOF
<?php

use Illuminate\Support\Facades\Route;
use Pterodactyl\Http\Middleware\AntiRusuh;

Route::middleware([AntiRusuh::class])->group(function () {
    require base_path('routes/admin.php');
});
EOF

    echo "[INFO] Mengganti loader admin di base.php..."

    sed -i \
        's/require __DIR__ . .admin.php./require __DIR__ . "\/admin-wrapper.php";/g' \
        $PTERO/routes/base.php || true

    cd $PTERO
    php artisan optimize:clear

    echo "====================================="
    echo "  AntiRusuh Berhasil DIPASANG!"
    echo "====================================="
}

uninstall() {
    banner

    echo "[INFO] Menghapus AntiRusuh..."
    rm -f $PTERO/app/Http/Middleware/AntiRusuh.php
    rm -f $PTERO/routes/admin-wrapper.php

    sed -i \
        's/admin-wrapper.php/admin.php/g' \
        $PTERO/routes/base.php || true

    cd $PTERO
    php artisan optimize:clear

    echo "====================================="
    echo "  AntiRusuh berhasil DIHAPUS!"
    echo "====================================="
}

menu() {
    banner
    echo "1) Install AntiRusuh"
    echo "2) Uninstall AntiRusuh"
    echo "3) Exit"
    read -p "Pilih: " x
    [ "$x" = "1" ] && install
    [ "$x" = "2" ] && uninstall
}

menu
