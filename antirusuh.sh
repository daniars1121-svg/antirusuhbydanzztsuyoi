#!/bin/bash

PTERO="/var/www/pterodactyl"

ADMIN_MW="$PTERO/app/Http/Middleware/WhitelistAdmin.php"
CLIENT_MW="$PTERO/app/Http/Middleware/ClientLock.php"
KERNEL="$PTERO/app/Http/Kernel.php"
CLIENT_ROUTE="$PTERO/routes/api-client.php"

banner(){
    echo "======================================="
    echo "      ANTI RUSUH UNIVERSAL PTERO"
    echo "======================================="
}

install_antirusuh(){
    banner
    read -p "Masukkan ID Owner Utama: " OWNER

    echo "→ Membuat WhitelistAdmin.php"
cat > "$ADMIN_MW" <<EOF
<?php
namespace Pterodactyl\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

class WhitelistAdmin {
    public function handle(Request \$request, Closure \$next) {
        \$allowed = [$OWNER];
        \$u = \$request->user();
        if (!\$u) abort(403, "ngapain wok");

        \$protect = [
            '/admin/servers',
            '/admin/nodes',
            '/admin/databases',
            '/admin/locations',
            '/admin/mounts',
            '/admin/nests'
        ];

        foreach (\$protect as \$p) {
            if (str_starts_with(\$request->path(), ltrim(\$p, '/'))) {
                if (!in_array(\$u->id, \$allowed)) abort(403, "ngapain wok");
            }
        }

        return \$next(\$request);
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

    echo "→ Register middleware di Kernel.php"

    sed -i "/middlewareAliases/ a\        'whitelistadmin' => \\\\Pterodactyl\\\\Http\\\\Middleware\\\\WhitelistAdmin::class," "$KERNEL"
    sed -i "/middlewareAliases/ a\        'clientlock' => \\\\App\\\\Http\\\\Middleware\\\\ClientLock::class," "$KERNEL"

    echo "→ Menambahkan whitelistadmin ke web middleware group"
    sed -i "/'web' => \[/ a\        \\\\Pterodactyl\\\\Http\\\\Middleware\\\\WhitelistAdmin::class," "$KERNEL"

    echo "→ Menambahkan clientlock ke api-client route"
    sed -i "s/AuthenticateServerAccess::class,/AuthenticateServerAccess::class, 'clientlock',/g" "$CLIENT_ROUTE"

    echo "→ Clear cache"
    cd "$PTERO"
    php artisan route:clear
    php artisan config:clear
    php artisan cache:clear
    systemctl restart pteroq

    echo "======================================="
    echo "    ANTI RUSUH UNIVERSAL TERPASANG!"
    echo "======================================="
}

add_owner(){
    read -p "Masukkan ID Owner Baru: " ID
    sed -i "s/\[\(.*\)\]/[\1,$ID]/" "$ADMIN_MW"
    sed -i "s/\[\(.*\)\]/[\1,$ID]/" "$CLIENT_MW"
    php "$PTERO/artisan" route:clear
    echo "Owner berhasil ditambah!"
}

del_owner(){
    read -p "Masukkan ID Owner yang ingin dihapus: " ID
    sed -i "s/\b$ID\b//g" "$ADMIN_MW"
    sed -i "s/\b$ID\b//g" "$CLIENT_MW"
    sed -i "s/,,/,/g" "$ADMIN_MW"
    sed -i "s/,,/,/g" "$CLIENT_MW"
    php "$PTERO/artisan" route:clear
    echo "Owner berhasil dihapus!"
}

uninstall_antirusuh(){
    echo "→ Menghapus middleware"
    rm -f "$ADMIN_MW" "$CLIENT_MW"

    echo "→ Menghapus middlewareAliases di Kernel"
    sed -i "/whitelistadmin/d" "$KERNEL"
    sed -i "/clientlock/d" "$KERNEL"

    echo "→ Menghapus whitelistadmin dari web group"
    sed -i "/WhitelistAdmin/d" "$KERNEL"

    echo "→ Menghapus clientlock dari api-client"
    sed -i "s/'clientlock',//g" "$CLIENT_ROUTE"

    cd "$PTERO"
    php artisan route:clear
    php artisan config:clear
    php artisan cache:clear
    systemctl restart pteroq

    echo "======================================="
    echo "        ANTI RUSUH DIHAPUS!"
    echo "======================================="
}

menu(){
while true; do
    banner
    echo "1) Install Anti-Rusuh rial cuyk"
    echo "2) Tambah Owner"
    echo "3) Hapus Owner"
    echo "4) Uninstall Anti-Rusuh"
    echo "5) Exit"
    read -p "Pilih: " x

    case $x in
        1) install_antirusuh ;;
        2) add_owner ;;
        3) del_owner ;;
        4) uninstall_antirusuh ;;
        5) exit ;;
    esac
done
}

menu
