#!/bin/bash

PTERO="/var/www/pterodactyl"

ADMIN_MW="$PTERO/app/Http/Middleware/WhitelistAdmin.php"
CLIENT_MW="$PTERO/app/Http/Middleware/ClientLock.php"
KERNEL="$PTERO/app/Http/Kernel.php"
API_CLIENT="$PTERO/routes/api-client.php"

banner(){
    echo "======================================="
    echo "     ANTI RUSUH UNIVERSAL v4 (STABLE)"
    echo "======================================="
}

install(){
    banner
    read -p "Masukkan ID Owner Utama: " OWNER

    mkdir -p "$PTERO/antirusuh_backup"
    BKP="$PTERO/antirusuh_backup/backup_$(date +%s)"
    mkdir "$BKP"

    cp "$KERNEL" "$BKP"
    cp "$API_CLIENT" "$BKP"

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

        \$blocked = [
            "admin/nodes",
            "admin/servers",
            "admin/databases",
            "admin/locations",
            "admin/mounts",
            "admin/nests"
        ];

        foreach (\$blocked as \$p){
            if (str_starts_with(\$req->path(), \$p)){
                if (!in_array(\$u->id, \$allowed))
                    abort(403, "ngapain wok");
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
    public function handle(Request \$req, Closure \$next){
        \$allowed = [$OWNER];
        \$u = \$req->user();
        if (!\$u) abort(403, "ngapain wok");

        if (in_array(\$u->id, \$allowed)) 
            return \$next(\$req);

        \$srv = \$req->route("server");
        if (\$srv && \$srv->owner_id != \$u->id)
            abort(403, "ngapain wok");

        return \$next(\$req);
    }
}
EOF

    echo "→ Update Kernel.php"

    # Tambahkan alias jika belum ada
    if ! grep -q "whitelistadmin" "$KERNEL"; then
        sed -i "/middlewareAliases = \[/ a\        'whitelistadmin' => \\\\Pterodactyl\\\\Http\\\\Middleware\\\\WhitelistAdmin::class," "$KERNEL"
    fi

    if ! grep -q "clientlock" "$KERNEL"; then
        sed -i "/middlewareAliases = \[/ a\        'clientlock' => \\\\App\\\\Http\\\\Middleware\\\\ClientLock::class," "$KERNEL"
    fi

    # Tambahkan whitelistadmin ke web group jika belum ada
    if ! grep -q "WhitelistAdmin" "$KERNEL"; then
        sed -i "/'web' => \[/ a\            \\\\Pterodactyl\\\\Http\\\\Middleware\\\\WhitelistAdmin::class," "$KERNEL"
    fi

    echo "→ Menambahkan ClientLock ke api-client"
    if ! grep -q "clientlock" "$API_CLIENT"; then
        sed -i "s/AuthenticateServerAccess::class,/AuthenticateServerAccess::class, 'clientlock',/g" "$API_CLIENT"
    fi

    echo "→ Clear cache"
    cd "$PTERO"
    php artisan route:clear
    php artisan config:clear
    php artisan cache:clear
    systemctl restart pteroq 2>/dev/null

    echo "======================================="
    echo " ANTI RUSUH v4 TERPASANG DENGAN AMAN!"
    echo "======================================="
}

add_owner(){
    read -p "ID Owner baru: " ID
    sed -i "s/\[\(.*\)\]/[\1,$ID]/" "$ADMIN_MW"
    sed -i "s/\[\(.*\)\]/[\1,$ID]/" "$CLIENT_MW"
    php "$PTERO/artisan" route:clear
    echo "Owner baru ditambahkan!"
}

del_owner(){
    read -p "ID Owner yang dihapus: " ID
    sed -i "s/\b$ID\b//g" "$ADMIN_MW"
    sed -i "s/\b$ID\b//g" "$CLIENT_MW"
    sed -i "s/,,/,/g" "$ADMIN_MW"
    sed -i "s/,,/,/g" "$CLIENT_MW"
    php "$PTERO/artisan" route:clear
    echo "Owner berhasil dihapus!"
}

uninstall(){
    echo "→ Menghapus middleware"
    rm -f "$ADMIN_MW" "$CLIENT_MW"

    echo "→ Membersihkan Kernel"
    sed -i "/whitelistadmin/d" "$KERNEL"
    sed -i "/clientlock/d" "$KERNEL"
    sed -i "/WhitelistAdmin/d" "$KERNEL"

    echo "→ Membersihkan api-client"
    sed -i "s/'clientlock',//g" "$API_CLIENT"

    echo "→ Clear cache"
    cd "$PTERO"
    php artisan route:clear
    php artisan config:clear
    php artisan cache:clear
    systemctl restart pteroq 2>/dev/null

    echo "======================================="
    echo " ANTI RUSUH v4 BERHASIL DIHAPUS!"
    echo "======================================="
}

menu(){
while true; do
    banner
    echo "1) Install Anti-Rusuh rial"
    echo "2) Tambah Owner"
    echo "3) Hapus Owner"
    echo "4) Uninstall"
    echo "5) Exit"
    read -p "Pilih: " x

    case $x in
        1) install ;;
        2) add_owner ;;
        3) del_owner ;;
        4) uninstall ;;
        5) exit ;;
    esac
done
}

menu
