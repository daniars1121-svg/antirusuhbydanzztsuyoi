#!/bin/bash
set -e

PTERO="/var/www/pterodactyl"

PROVIDER="$PTERO/app/Providers/AntiRusuhProvider.php"
MIDDLEWARE="$PTERO/app/Http/Middleware/AntiRusuhMiddleware.php"

banner() {
    echo "======================================="
    echo "   ANTI RUSUH FINAL v4 — SAFE & WORKING"
    echo "   Tanpa edit admin.php / kernel / packages"
    echo "======================================="
}

install() {
    banner
    read -p "Masukkan ID Owner Utama: " OWNER

    # Buat middleware anti-rusuh
cat > "$MIDDLEWARE" <<EOF
<?php

namespace App\Http\Middleware;

use Closure;

class AntiRusuhMiddleware {

    public function handle(\$req, Closure \$next) {

        \$user = \$req->user();
        if (!\$user) return abort(403, 'ngapain wok');

        \$path = trim(\$req->path(), '/');

        // Proteksi admin panel
        if (str_starts_with(\$path, 'admin') && 
            \$user->id != $OWNER && 
            empty(\$user->root_admin)) {

            return abort(403, 'ngapain wok');
        }

        // Proteksi akses server API
        if (\$req->route()?->parameter('server')) {
            \$srv = \$req->route()->parameter('server');

            if (\$srv->owner_id != \$user->id &&
                empty(\$user->root_admin) &&
                \$user->id != $OWNER) {

                return abort(403, 'ngapain wok');
            }
        }

        return \$next(\$req);
    }
}
EOF

    # Provider yang auto-register middleware via router
cat > "$PROVIDER" <<EOF
<?php

namespace App\Providers;

use Illuminate\Support\ServiceProvider;
use Illuminate\Support\Facades\Route;
use App\Http\Middleware\AntiRusuhMiddleware;

class AntiRusuhProvider extends ServiceProvider {

    public function boot() {

        // Masukkan middleware ke group "web"
        app('router')->pushMiddlewareToGroup('web', AntiRusuhMiddleware::class);

        // Masukkan middleware ke group "client-api"
        app('router')->pushMiddlewareToGroup('client-api', AntiRusuhMiddleware::class);
    }
}
EOF

    echo "→ Membersihkan cache"
    cd "$PTERO"
    php artisan optimize:clear

    echo ""
    echo "======================================="
    echo "  AntiRusuh FINAL v4 TERPASANG!"
    echo "  Semua proteksi aktif."
    echo "======================================="
}

uninstall() {
    banner

    rm -f "$PROVIDER"
    rm -f "$MIDDLEWARE"

    cd "$PTERO"
    php artisan optimize:clear

    echo "======================================="
    echo " AntiRusuh FINAL v4 DIHAPUS!"
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
