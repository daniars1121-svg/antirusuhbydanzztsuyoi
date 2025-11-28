#!/bin/bash
set -e

PTERO="/var/www/pterodactyl"

banner() {
    echo "====================================="
    echo "   ANTI RUSUH FINAL — SAFE MODE"
    echo "   (Tanpa edit admin.php / kernel)"
    echo "====================================="
}

install(){
    banner
    read -p "Masukkan ID Owner Utama: " OWNER
    
    mkdir -p "$PTERO/app/Providers"

    cat > "$PTERO/app/Providers/AntiRusuhService.php" <<EOF
<?php

namespace App\Providers;

use Illuminate\Support\ServiceProvider;
use Illuminate\Http\Request;

class AntiRusuhService extends ServiceProvider
{
    public function boot()
    {
        \$owner = $OWNER;

        app('router')->prependMiddlewareToGroup('web', function (\$request, \$next) use (\$owner) {

            \$u = \$request->user();

            if (!\$u) return \$next(\$request);

            \$path = ltrim(\$request->path(), '/');

            \$blocked = [
                'admin/nodes',
                'admin/servers',
                'admin/databases',
                'admin/locations',
                'admin/mounts',
                'admin/nests',
            ];

            foreach (\$blocked as \$p) {
                if (strpos(\$path, \$p) === 0 && \$u->id != \$owner && empty(\$u->root_admin)) {
                    abort(403, "ngapain wok");
                }
            }

            return \$next(\$request);
        });

        app('router')->matched(function (\$event) use (\$owner) {
            \$req = \$event->request;
            \$u = \$req->user();

            if (!\$u) return;

            if (\$req->route()?->parameter('server')) {

                \$srv = \$req->route()->parameter('server');

                if (\$srv->owner_id != \$u->id && empty(\$u->root_admin) && \$u->id != \$owner) {
                    abort(403, "ngapain wok");
                }
            }
        });
    }
}
EOF

    # Register provider via auto-discovery (tidak edit files)
    echo "App\\Providers\\AntiRusuhService" >> "$PTERO/bootstrap/cache/packages.php"

    cd "$PTERO"
    php artisan optimize:clear

    echo ""
    echo "====================================="
    echo " Anti Rusuh FINAL TERPASANG"
    echo " Tidak mengedit file panel"
    echo "====================================="
}

uninstall(){
    banner
    rm -f "$PTERO/app/Providers/AntiRusuhService.php"
    sed -i "/AntiRusuhService/d" "$PTERO/bootstrap/cache/packages.php" 2>/dev/null || true

    cd "$PTERO"
    php artisan optimize:clear

    echo ""
    echo "====================================="
    echo " Anti Rusuh FINAL DIHAPUS"
    echo "====================================="
}

menu(){
    banner
    echo "1) Instalpol"
    echo "2) Uninstall"
    echo "3) Exit"
    read -p "Pilih: " x
    [ "$x" = "1" ] && install
    [ "$x" = "2" ] && uninstall
}

menu
