#!/bin/bash

PTERO="/var/www/pterodactyl"
ADMIN_ROUTE="$PTERO/routes/admin.php"

MW="$PTERO/app/Http/Middleware/WhitelistAdmin.php"

banner(){
    echo "======================================="
    echo "   ANTI RUSUH PTERODACTYL v6 (WORKING)"
    echo "======================================="
}

install(){
    banner
    read -p "Masukkan ID Owner Utama: " OWNER

    mkdir -p "$PTERO/antirusuh_backup"
    cp "$ADMIN_ROUTE" "$PTERO/antirusuh_backup/admin_$(date +%s).php"

    echo "→ Membuat middleware WhitelistAdmin.php"

cat > "$MW" <<EOF
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
                if (!in_array(\$u->id, \$allowed))
                    abort(403, "ngapain wok");
            }
        }

        return \$next(\$req);
    }
}
EOF

    echo "→ Menyuntikkan middleware ke admin.php"

    if ! grep -q "WhitelistAdmin" "$ADMIN_ROUTE"; then
        sed -i "1i <?php\nuse Pterodactyl\Http\Middleware\WhitelistAdmin;\nRoute::middleware([WhitelistAdmin::class])->group(function() {" "$ADMIN_ROUTE"
        echo "});" >> "$ADMIN_ROUTE"
    fi

    cd "$PTERO"
    php artisan route:clear
    php artisan cache:clear

    echo "======================================="
    echo " ANTI RUSUH v6 TERPASANG DENGAN SUKSES!"
    echo "======================================="
}

uninstall(){
    banner
    echo "→ Menghapus middleware"
    rm -f "$MW"

    echo "→ Mengembalikan admin.php ke normal"
    sed -i '/WhitelistAdmin/d' "$ADMIN_ROUTE"
    sed -i '/Route::middleware/d' "$ADMIN_ROUTE"
    sed -i '/});$/d' "$ADMIN_ROUTE"

    cd "$PTERO"
    php artisan route:clear
    php artisan cache:clear

    echo "======================================="
    echo " ANTI RUSUH v6 DIHAPUS!"
    echo "======================================="
}

menu(){
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
