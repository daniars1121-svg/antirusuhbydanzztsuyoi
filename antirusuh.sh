#!/bin/bash
set -e

PTERO="/var/www/pterodactyl"

banner() {
    echo "====================================="
    echo "     ANTI RUSUH FINAL – STABLE"
    echo " (Tanpa edit admin.php / kernel.php)"
    echo "====================================="
}

install() {
    banner
    read -p "Masukkan ID Owner Utama: " OWNER

    # Buat Middleware
    mkdir -p "$PTERO/app/Http/Middleware"

cat > "$PTERO/app/Http/Middleware/AntiRusuh.php" <<EOF
<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

class AntiRusuh
{
    public function handle(Request \$req, Closure \$next)
    {
        \$owner = $OWNER;
        \$u = \$req->user();

        if (!\$u) 
            return \$next(\$req);

        \$path = ltrim(\$req->path(), '/');

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

        if (\$req->route()?->parameter('server')) {
            \$srv = \$req->route()->parameter('server');

            if (\$srv->owner_id != \$u->id && empty(\$u->root_admin) && \$u->id != \$owner) {
                abort(403, "ngapain wok");
            }
        }

        return \$next(\$req);
    }
}
EOF

    echo "[OK] Middleware dibuat"

    # Provider
    mkdir -p "$PTERO/app/Providers"

cat > "$PTERO/app/Providers/AntiRusuhServiceProvider.php" <<EOF
<?php

namespace App\Providers;

use Illuminate\Support\ServiceProvider;
use App\Http\Middleware\AntiRusuh;

class AntiRusuhServiceProvider extends ServiceProvider
{
    public function boot()
    {
        app('router')->pushMiddlewareToGroup('web', AntiRusuh::class);
        app('router')->pushMiddlewareToGroup('client-api', AntiRusuh::class);
    }

    public function register() {}
}
EOF

    echo "[OK] Provider dibuat"

    # Daftarkan Provider dengan benar (tidak pakai bootstrap/cache!)
    if ! grep -q "AntiRusuhServiceProvider" "$PTERO/config/app.php"; then
        sed -i "/App\\\\Providers\\\\RouteServiceProvider::class,/ a\        App\\\\Providers\\\\AntiRusuhServiceProvider::class," "$PTERO/config/app.php"
    fi

    echo "[OK] Provider diregistrasi di config/app.php"

    cd "$PTERO"
    php artisan optimize:clear

    echo "====================================="
    echo " ANTI RUSUH FINAL TERINSTAL!"
    echo "====================================="
}

uninstall() {
    banner
    rm -f "$PTERO/app/Http/Middleware/AntiRusuh.php"
    rm -f "$PTERO/app/Providers/AntiRusuhServiceProvider.php"

    sed -i "/AntiRusuhServiceProvider/d" "$PTERO/config/app.php"

    cd "$PTERO"
    php artisan optimize:clear

    echo "====================================="
    echo " ANTI RUSUH FINAL DIHAPUS!"
    echo "====================================="
}

menu() {
    banner
    echo "1) Install"
    echo "2) Uninstall"
    echo "3) Exit"
    read -p "Pilih: " x

    [ "$x" = "1" ] && install
    [ "$x" = "2" ] && uninstall
}

menu
