#!/bin/bash

PTERO="/var/www/pterodactyl"

ADMIN_MW="$PTERO/app/Http/Middleware/WhitelistAdmin.php"
CLIENT_MW="$PTERO/app/Http/Middleware/ClientLock.php"
KERNEL="$PTERO/app/Http/Kernel.php"
USERCTL="$PTERO/app/Http/Controllers/Admin/UserController.php"
SERVERCTL="$PTERO/app/Http/Controllers/Admin/Servers"


banner() {
    echo "======================================="
    echo "         ANTI RUSUH UNIVERSAL"
    echo "======================================="
}


install_antirusuh() {
    banner
    read -p "Masukkan ID Owner Utama: " OWNER

    # ==========================
    # BUAT MIDDLEWARE ADMIN
    # ==========================
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

    # ==========================
    # BUAT MIDDLEWARE CLIENT
    # ==========================
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

    # ==========================
    # REGISTER DI KERNEL
    # ==========================
    if ! grep -q "WhitelistAdmin" "$KERNEL"; then
        sed -i "/middlewareAliases = \[/a\        'whitelistadmin' => \\\\Pterodactyl\\\\Http\\\\Middleware\\\\WhitelistAdmin::class," "$KERNEL"
    fi

    if ! grep -q "ClientLock" "$KERNEL"; then
        sed -i "/middlewareAliases = \[/a\        'clientlock' => \\\\App\\\\Http\\\\Middleware\\\\ClientLock::class," "$KERNEL"
    fi

    # ==========================
    # PROTEKSI DELETE ADMIN
    # ==========================
protect_delete() {
    sed -i "/public function delete/,/}/ { /public function delete/!b; n; i\        \\\$allowed=[$OWNER]; if(!in_array(auth()->user()->id,\\\$allowed)) abort(403,'ngapain wok');" "$1"
}

    protect_delete "$USERCTL"

    for f in "$SERVERCTL"/*.php; do
        protect_delete "$f"
    done

    # ==========================
    # CLEAR CACHE
    # ==========================
    cd "$PTERO"
    php artisan route:clear
    php artisan cache:clear
    php artisan config:clear
    systemctl restart pteroq

    echo "======================================="
    echo "         ANTI RUSUH TERPASANG!"
    echo "======================================="
}

# ==========================
# TAMBAH OWNER
# ==========================
add_owner() {
    read -p "Masukkan ID Owner Baru: " NEW
    sed -i "s/\[\(.*\)\]/[\1,$NEW]/" "$ADMIN_MW"
    sed -i "s/\[\(.*\)\]/[\1,$NEW]/" "$CLIENT_MW"
    php "$PTERO/artisan" route:clear
    echo "Owner ditambahkan."
}

# ==========================
# HAPUS OWNER
# ==========================
delete_owner() {
    read -p "Masukkan ID Owner yang ingin dihapus: " DEL
    sed -i "s/\b$DEL\b//g" "$ADMIN_MW"
    sed -i "s/\b$DEL\b//g" "$CLIENT_MW"
    sed -i "s/,,/,/g" "$ADMIN_MW"
    sed -i "s/,,/,/g" "$CLIENT_MW"
    php "$PTERO/artisan" route:clear
    echo "Owner dihapus!"
}

# ==========================
# UNINSTALL
# ==========================
uninstall_antirusuh() {
    rm -f "$ADMIN_MW" "$CLIENT_MW"
    sed -i "/whitelistadmin/d" "$KERNEL"
    sed -i "/clientlock/d" "$KERNEL"

    cd "$PTERO"
    php artisan route:clear
    php artisan cache:clear
    php artisan config:clear
    systemctl restart pteroq
    echo "AntiRusuh dihapus!"
}

# ==========================
# MENU
# ==========================
menu() {
    while true; do
        banner
        echo "1) Install"
        echo "2) Add Owner"
        echo "3) Delete Owner"
        echo "4) Uninstall"
        echo "5) Exit"
        read -p "Pilih: " x

        case $x in
            1) install_antirusuh ;;
            2) add_owner ;;
            3) delete_owner ;;
            4) uninstall_antirusuh ;;
            5) exit ;;
        esac
    done
}

menu
