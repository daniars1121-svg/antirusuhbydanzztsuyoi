#!/bin/bash

PTERO="/var/www/pterodactyl"
ADMIN_MW="$PTERO/app/Http/Middleware/WhitelistAdmin.php"
CLIENT_MW="$PTERO/app/Http/Middleware/ClientLock.php"
KERNEL="$PTERO/app/Http/Kernel.php"


banner() {
echo "======================================="
echo "         ANTI RUSUH v4 STABIL"
echo "======================================="
}


install_antirusuh() {
    banner
    read -p "Masukkan ID Owner Utama: " OWNER

# ==========================
# MIDDLEWARE ADMIN
# ==========================
cat > "$ADMIN_MW" <<EOF
<?php
namespace Pterodactyl\Http\Middleware;
use Closure;
use Illuminate\Http\Request;

class WhitelistAdmin {
    public function handle(Request \$req, Closure \$next) {
        \$allowed = [$OWNER];

        if (!\$req->user() || !in_array(\$req->user()->id, \$allowed)) {
            abort(403, "ngapain wok");
        }

        return \$next(\$req);
    }
}
EOF

# ==========================
# MIDDLEWARE CLIENT (SERVER PROTECT)
# ==========================
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

        # Owner full akses
        if (in_array(\$u->id, \$allowed)) return \$next(\$req);

        # Cek server user
        \$server = \$req->route("server");
        if (\$server && \$server->owner_id != \$u->id)
            abort(403, "ngapain wok");

        return \$next(\$req);
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
# CLEAR CACHE
# ==========================
cd "$PTERO"
php artisan route:clear
php artisan cache:clear
php artisan config:clear
systemctl restart pteroq

echo "ANTIRUSUH v4 TERPASANG!"
}

# ==========================
# TAMBAH OWNER
# ==========================
add_owner() {
    read -p "ID Owner Baru: " NEW
    sed -i "s/\[\(.*\)\]/[\1,$NEW]/" "$ADMIN_MW"
    sed -i "s/\[\(.*\)\]/[\1,$NEW]/" "$CLIENT_MW"
    echo "Owner ditambahkan!"
}

# ==========================
# HAPUS OWNER
# ==========================
delete_owner() {
    read -p "ID Owner Hapus: " DEL
    sed -i "s/\b$DEL\b//g" "$ADMIN_MW"
    sed -i "s/\b$DEL\b//g" "$CLIENT_MW"
    sed -i "s/,,/,/g" "$ADMIN_MW"
    sed -i "s/,,/,/g" "$CLIENT_MW"
    echo "Owner dihapus!"
}

# ==========================
# UNINSTALL BERSIH
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

    echo "AntiRusuh DIHAPUS BERSIH!"
}

# ==========================
# MENU
# ==========================
menu() {
while true; do
    banner
    echo "1) Install AntiRusuh"
    echo "2) Tambah Owner"
    echo "3) Hapus Owner"
    echo "4) Uninstall"
    echo "5) Exit"
    read -p "Pilih : " x

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
