#!/bin/bash

PTERO="/var/www/pterodactyl"

ADMIN_MW="$PTERO/app/Http/Middleware/WhitelistAdmin.php"
CLIENT_MW="$PTERO/app/Http/Middleware/ClientLock.php"

banner() {
    echo "========================================"
    echo "      ANTI RUSUH UNIVERSAL v7 SAFE"
    echo "========================================"
}

install() {
    banner
    read -p "Masukkan ID Owner Utama: " OWNER

    echo "→ Membuat WhitelistAdmin.php"
cat > "$ADMIN_MW" <<EOF
<?php
namespace Pterodactyl\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

class WhitelistAdmin {
    public function handle(Request \$req, Closure \$next) {

        \$allowed = [$OWNER];
        \$u = \$req->user();
        if (!\$u) abort(403, "ngapain wok");

        \$protect = [
            "admin/nodes",
            "admin/servers",
            "admin/databases",
            "admin/locations",
            "admin/mounts",
            "admin/nests",
            "admin/users",
        ];

        foreach (\$protect as \$p){
            if (str_starts_with(\$req->path(), \$p)){
                if (!in_array(\$u->id, \$allowed)){
                    abort(403, "ngapain wok");
                }
            }
        }

        return \$next(\$req);
    }
}
EOF

echo "→ Membuat ClientLock.php"
cat > "$CLIENT_MW" <<EOF
<?php
namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

class ClientLock {
    public function handle(Request \$req, Closure \$next) {

        \$allowed = [$OWNER];
        \$u = \$req->user();

        if (!\$u) abort(403, "ngapain wok");
        if (in_array(\$u->id, \$allowed)) return \$next(\$req);

        \$srv = \$req->route("server");
        if (\$srv && \$srv->owner_id != \$u->id){
            abort(403, "ngapain wok");
        }

        return \$next(\$req);
    }
}
EOF

    echo "→ Menyuntik middleware ke admin.php (TANPA MERUSAK FILE)"

    ADMIN_ROUTE="$PTERO/routes/admin.php"

    if ! grep -q "middleware(['whitelistadmin'])" "$ADMIN_ROUTE"; then
        sed -i "s#Route::get('/', \[Admin\\\\BaseController::class, 'index'\])#Route::middleware(['whitelistadmin'])->group(function () { Route::get('/', [Admin\\\\BaseController::class, 'index'])#g" "$ADMIN_ROUTE"
        echo "});" >> "$ADMIN_ROUTE"
    fi

    echo "→ Clear cache"
    cd "$PTERO"
    php artisan route:clear
    php artisan config:clear
    php artisan cache:clear

    echo "========================================"
    echo "     ANTI RUSUH v7 TERPASANG!"
    echo "========================================"
}

uninstall() {
    echo "→ Menghapus middleware"
    rm -f "$ADMIN_MW" "$CLIENT_MW"

    ADMIN_ROUTE="$PTERO/routes/admin.php"

    echo "→ Menghapus block group"
    sed -i "/middleware\(\['whitelistadmin'\]\)/,/});/d" "$ADMIN_ROUTE"

    echo "→ Clear cache"
    cd "$PTERO"
    php artisan route:clear
    php artisan config:clear
    php artisan cache:clear

    echo "========================================"
    echo " ANTI RUSUH v7 BERHASIL DIHAPUS!"
    echo "========================================"
}

menu() {
while true; do
    banner
    echo "1) Install Anti-Rusuh"
    echo "2) Uninstall Anti-Rusuh"
    echo "3) Exit"
    read -p "Pilih: " x

    case $x in
        1) install ;;
        2) uninstall ;;
        3) exit ;;
    esac
done
}

menu
