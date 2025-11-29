#!/bin/bash
set -e

PTERO="/var/www/pterodactyl"
MW="$PTERO/app/Http/Middleware/AntiRusuh.php"
WRAPPER="$PTERO/routes/admin-protected.php"
WEB="$PTERO/routes/web.php"

banner(){
echo "========================================"
echo "      ANTI RUSUH FINAL – CLEAN MODE"
echo "  Tidak edit core • Tidak rusak panel"
echo "========================================"
}

install(){
    banner
    read -p "Masukkan ID Owner: " OWNER

    echo "[INFO] Membuat middleware AntiRusuh..."
    cat > "$MW" <<EOF
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

        \$blocked = [
            'admin/nodes',
            'admin/servers',
            'admin/databases',
            'admin/locations',
            'admin/mounts',
            'admin/nests',
            'admin/users',
        ];

        foreach (\$blocked as \$b){
            if (str_starts_with(\$path,\$b) && \$u->id != \$owner && !\$u->root_admin){
                abort(403, "ngapain wok");
            }
        }

        if (\$req->route()?->parameter('server')){
            \$srv = \$req->route()->parameter('server');
            if (\$srv->owner_id != \$u->id && !\$u->root_admin && \$u->id != \$owner){
                abort(403, "ngapain wok");
            }
        }

        return \$next(\$req);
    }
}
EOF

    echo "[INFO] Membuat wrapper admin-protected.php..."
    cat > "$WRAPPER" <<EOF
<?php
use Pterodactyl\Http\Middleware\AntiRusuh;

Route::middleware([AntiRusuh::class])->group(function () {
    require base_path('routes/admin.php');
});
EOF

    echo "[INFO] Mengaktifkan wrapper di web.php..."
    if ! grep -q "admin-protected.php" "$WEB"; then
        sed -i "s|require __DIR__.'/admin.php';|require __DIR__.'/admin-protected.php';|" "$WEB"
    fi

    echo "[INFO] Membersihkan cache..."
    cd $PTERO
    php artisan optimize:clear

    echo "========================================"
    echo "AntiRusuh FINAL berhasil DIPASANG!"
    echo "========================================"
}

uninstall(){
    banner
    echo "[INFO] Menghapus middleware..."
    rm -f "$MW"
    rm -f "$WRAPPER"

    echo "[INFO] Mengembalikan web.php..."
    sed -i "s|admin-protected.php|admin.php|" "$WEB"

    cd $PTERO
    php artisan optimize:clear

    echo "========================================"
    echo "AntiRusuh FINAL berhasil DIHAPUS!"
    echo "========================================"
}

menu(){
    banner
    echo "1) Install AntiRusuh"
    echo "2) Uninstall AntiRusuh"
    echo "3) Exit"
    read -p "Pilih: " x

    case $x in
        1) install ;;
        2) uninstall ;;
        3) exit ;;
    esac
}

menu
