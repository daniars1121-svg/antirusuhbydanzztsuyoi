#!/bin/bash

PTERO="/var/www/pterodactyl"
ADMIN_MW="$PTERO/app/Http/Middleware/WhitelistAdmin.php"
CLIENT_MW="$PTERO/app/Http/Middleware/ClientLock.php"
KERNEL="$PTERO/app/Http/Kernel.php"
ADMIN_ROUTES="$PTERO/routes/admin.php"
USERCTL="$PTERO/app/Http/Controllers/Admin/UserController.php"
SERVERCTL="$PTERO/app/Http/Controllers/Admin/Servers"

banner() {
    echo "======================================="
    echo "    ANTIRUSUH CUSTOM • FIXED"
    echo "======================================="
}

install_antirusuh() {
    banner
    read -p "Masukkan ID Owner Utama: " OWNER

# ============================
# WHITELIST ADMIN
# ============================
cat > "$ADMIN_MW" <<EOF
<?php
namespace Pterodactyl\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

class WhitelistAdmin {
    public function handle(Request \$request, Closure \$next) {
        \$allowed = [$OWNER];
        if (!\$request->user() || !in_array(\$request->user()->id, \$allowed)) {
            abort(403, "ngapain wok");
        }
        return \$next(\$request);
    }
}
EOF

# ============================
# CLIENT LOCK (blok akses panel orang)
# ============================
cat > "$CLIENT_MW" <<EOF
<?php
namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

class ClientLock {
    public function handle(Request \$request, Closure \$next) {
        \$allowed = [$OWNER];
        \$u = \$request->user();

        if (!\$u) abort(403, "ngapain wok");
        if (in_array(\$u->id, \$allowed)) return \$next(\$request);

        \$server = \$request->route("server");
        if (\$server && \$server->owner_id != \$u->id) abort(403, "ngapain wok");

        return \$next(\$request);
    }
}
EOF

# ============================
# REGISTER MIDDLEWARE
# ============================
sed -i "/middlewareAliases = \[/a\        'whitelistadmin' => \\\\Pterodactyl\\\\Http\\\\Middleware\\\\WhitelistAdmin::class," "$KERNEL"
sed -i "/middlewareAliases = \[/a\        'clientlock' => \\\\App\\\\Http\\\\Middleware\\\\ClientLock::class," "$KERNEL"

# ============================
# PROTECT ADMIN ROUTES (SESUI PERMINTAAN LO)
# ============================
lock() {
    sed -i "s/Route::group(\['prefix' => '$1'\]/Route::group(['prefix' => '$1', 'middleware' => ['whitelistadmin']]/" "$ADMIN_ROUTES"
}

lock "nodes"
lock "locations"
lock "nests"
lock "mounts"
lock "databases"
lock "users"
lock "servers"

# ============================
# PROTECT DELETE (HANYA OWNER BOLEH)
# ============================
protect_delete() {
    sed -i "/public function delete/,/}/ { /public function delete/!b; n; i\        \\\$allowed = [$OWNER]; if (!in_array(auth()->user()->id,\\\$allowed)) abort(403,'ngapain wok');" "$1"
}

protect_delete "$USERCTL"

for f in "$SERVERCTL"/*.php; do
    protect_delete "$f"
done

# ============================
# CLEAR CACHE
# ============================
cd "$PTERO"
php artisan route:clear
php artisan cache:clear
php artisan config:clear
systemctl restart pteroq

echo "AntiRusuh installed!"
}

# ============================
# UNINSTALL
# ============================
uninstall_antirusuh() {
    rm -f "$ADMIN_MW" "$CLIENT_MW"
    sed -i "/whitelistadmin/d" "$KERNEL"
    sed -i "/clientlock/d" "$KERNEL"

    sed -i "s/'middleware' => \['whitelistadmin'\]//g" "$ADMIN_ROUTES"

    php "$PTERO/artisan" route:clear
    systemctl restart pteroq
    echo "AntiRusuh dihapus!"
}

# ============================
# MENU
# ============================
menu() {
    while true; do
        banner
        echo "1. Install AntiRusuh"
        echo "2. Uninstall"
        echo "3. Exit"
        read -p "Pilih: " x

        case $x in
            1) install_antirusuh ;;
            2) uninstall_antirusuh ;;
            3) exit ;;
        esac
    done
}

menu
