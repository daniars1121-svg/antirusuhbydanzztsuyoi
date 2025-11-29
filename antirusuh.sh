#!/bin/bash
set -e

PTERO="/var/www/pterodactyl"
PROVIDER="$PTERO/app/Providers/AntiRusuhProvider.php"
BOOT="$PTERO/bootstrap/cache/packages.php"
BACKUP="$BOOT.bak"

banner() {
    echo "======================================="
    echo "     ANTI RUSUH FINAL v3 — WORKING"
    echo "     Protect /admin/* tanpa edit core"
    echo "======================================="
}

install() {
    banner
    read -p "Masukkan ID Owner Utama: " OWNER

    cp "$BOOT" "$BACKUP"

    cat > "$PROVIDER" <<EOF
<?php

namespace App\Providers;

use Illuminate\Support\ServiceProvider;
use Illuminate\Support\Facades\Route;

class AntiRusuhProvider extends ServiceProvider
{
    public function boot()
    {
        \$owner = $OWNER;

        // Proteksi ADMIN PANEL
        Route::middlewareGroup('antirusuh_admin', [
            function (\$req, \$next) use (\$owner) {

                \$u = \$req->user();
                if (!\$u) return abort(403,"ngapain wok");

                \$path = \$req->path();

                if (str_starts_with(\$path, 'admin') && \$u->id != \$owner && empty(\$u->root_admin)) {
                    return abort(403,"ngapain wok");
                }

                return \$next(\$req);
            }
        ]);

        // Tambahkan middleware ke semua route admin tanpa edit admin.php
        app('router')->pushMiddlewareToGroup('web', \App\Http\Middleware\CheckAdminAccess::class);
    }
}
EOF

    # middleware kecil untuk routing admin
    mkdir -p "$PTERO/app/Http/Middleware"
cat > "$PTERO/app/Http/Middleware/CheckAdminAccess.php" <<EOF
<?php

namespace App\Http\Middleware;

use Closure;

class CheckAdminAccess {
    public function handle(\$req, Closure \$next) {

        \$u = \$req->user();
        if (!\$u) return \$next(\$req);

        \$path = \$req->path();

        if (str_starts_with(\$path,'admin') && \$u->id != ${OWNER} && empty(\$u->root_admin)) {
            abort(403, "ngapain wok");
        }

        return \$next(\$req);
    }
}
EOF

    echo "App\\Providers\\AntiRusuhProvider" >> "$BOOT"

    cd "$PTERO"
    php artisan optimize:clear

    echo ""
    echo "======================================="
    echo "  AntiRusuh FINAL v3 TERPASANG!"
    echo "  • /admin/* hanya untuk owner"
    echo "======================================="
}

uninstall() {
    banner

    rm -f "$PROVIDER"
    rm -f "$PTERO/app/Http/Middleware/CheckAdminAccess.php"

    if [ -f "$BACKUP" ]; then
        mv "$BACKUP" "$BOOT"
    fi

    cd "$PTERO"
    php artisan optimize:clear

    echo "======================================="
    echo "  AntiRusuh berhasil DIHAPUS"
    echo "======================================="
}

menu() {
    banner
    echo "1) Install"
    echo "2) Uninstall"
    echo "3) Exit"
    read -p "Pilih: " x

    case $x in
        1) install ;;
        2) uninstall ;;
        3) exit ;;
    esac
}

menu
