#!/bin/bash
set -e

PTERO="/var/www/pterodactyl"
MW="$PTERO/app/Http/Middleware/AntiRusuh.php"
WRAP="$PTERO/routes/admin-protect.php"
ADMIN="$PTERO/routes/admin.php"

banner(){
echo "=========================================="
echo "     ANTI RUSUH FINAL UNIVERSAL"
echo "  Support Pterodactyl 1.10 – 1.11.11"
echo "  Tanpa edit core • Tanpa 500 error"
echo "=========================================="
}

install(){
    banner
    read -p "Masukkan ID Owner: " OWNER

    echo "[INFO] Membuat AntiRusuh.php..."
cat > "$MW" <<EOF
<?php

namespace Pterodactyl\Http\Middleware;

use Closure;

class AntiRusuh
{
    public function handle(\$req, Closure \$next)
    {
        \$u = \$req->user();
        if (!\$u) return \$next(\$req);

        \$owner = $OWNER;
        \$path = ltrim(\$req->path(), '/');

        \$block = [
            'admin/nodes',
            'admin/servers',
            'admin/locations',
            'admin/databases',
            'admin/mounts',
            'admin/nests',
            'admin/users',
        ];

        foreach (\$block as \$b) {
            if (str_starts_with(\$path, \$b)) {
                if (\$u->id != \$owner && !\$u->root_admin) {
                    abort(403, "ngapain wok");
                }
            }
        }

        if (\$req->route()?->parameter('server')) {
            \$srv = \$req->route()->parameter('server');
            if (\$srv->owner_id != \$u->id && !\$u->root_admin && \$u->id != \$owner) {
                abort(403, "ngapain wok");
            }
        }

        return \$next(\$req);
    }
}
EOF

    echo "[INFO] Membuat admin-protect.php..."
cat > "$WRAP" <<EOF
<?php

use Pterodactyl\Http\Middleware\AntiRusuh;
use Illuminate\Support\Facades\Route;

Route::middleware([AntiRusuh::class])->group(function () {
    require base_path('routes/admin.php');
});
EOF

    echo "[INFO] Mengganti loader admin.php..."

    sed -i "s#require __DIR__.'/admin.php'#require __DIR__.'/admin-protect.php'#" "$PTERO/routes/base.php"

    echo "[INFO] Clear cache..."
    cd $PTERO
    php artisan optimize:clear

    echo "=========================================="
    echo "  ANTI RUSUH FINAL UNIVERSAL DIPASANG!"
    echo "  Owner ID: $OWNER"
    echo "=========================================="
}

uninstall(){
    banner
    echo "[INFO] Menghapus file middleware..."
    rm -f "$MW"
    rm -f "$WRAP"

    echo "[INFO] Mengembalikan admin loader..."
    sed -i "s#admin-protect.php#admin.php#" "$PTERO/routes/base.php"

    cd $PTERO
    php artisan optimize:clear

    echo "=========================================="
    echo "  ANTI RUSUH FINAL DIHAPUS!"
    echo "=========================================="
}

menu(){
    banner
    echo "1) Install AntiRusuh"
    echo "2) Uninstall AntiRusuh"
    echo "3) Exit"
    read -p "Pilih: " x
    case $x in
        1) install ;;
        2) uninstall ;;
        3) exit ;;
    esac
}

menu
