#!/bin/bash
set -e

PTERO="/var/www/pterodactyl"

banner() {
    echo "====================================="
    echo "      ANTI RUSUH ULTRA FINAL"
    echo " Protect admin & server API (Stable)"
    echo "====================================="
}

install(){
    banner
    read -p "Masukkan ID Owner Utama: " OWNER

    echo "[INFO] Membuat middleware AntiRusuh..."

    mkdir -p "$PTERO/app/Http/Middleware"

cat > "$PTERO/app/Http/Middleware/AntiRusuh.php" <<EOF
<?php

namespace Pterodactyl\Http\Middleware;

use Closure;

class AntiRusuh
{
    public function handle(\$request, Closure \$next)
    {
        \$u = \$request->user();
        if (!\$u) return \$next(\$request);

        \$owner = $OWNER;
        \$path = ltrim(\$request->path(), '/');

        /* Proteksi halaman admin */
        if (str_starts_with(\$path, 'admin')) {
            if (\$u->id != \$owner && !\$u->root_admin) {
                return abort(403, "ngapain wok");
            }
        }

        /* Proteksi API server */
        if (\$request->route()?->parameter('server')) {
            \$server = \$request->route()->parameter('server');
            if (\$server->owner_id != \$u->id && !\$u->root_admin && \$u->id != \$owner) {
                return abort(403, "ngapain wok");
            }
        }

        return \$next(\$request);
    }
}
EOF

    echo "[INFO] Menyuntik middleware ke Kernel..."

    sed -i "/protected \$middlewareAliases/a\        'antirusuh' => \\Pterodactyl\\\\Http\\\\Middleware\\\\AntiRusuh::class," \
        "$PTERO/app/Http/Kernel.php"

    echo "[INFO] Mengaktifkan AntiRusuh di group 'web' & 'api'..."

    sed -i "/'web' => \[/a\            'antirusuh'," "$PTERO/app/Http/Kernel.php"
    sed -i "/'api' => \[/a\            'antirusuh'," "$PTERO/app/Http/Kernel.php"

    echo "[INFO] Membersihkan cache Laravel..."
    cd "$PTERO"
    php artisan optimize:clear

    echo ""
    echo "====================================="
    echo " ANTI RUSUH ULTRA FINAL TERPASANG!"
    echo "====================================="
}

uninstall(){
    banner

    echo "[INFO] Menghapus file middleware..."
    rm -f "$PTERO/app/Http/Middleware/AntiRusuh.php"

    echo "[INFO] Membersihkan Kernel..."
    sed -i "/antirusuh/d" "$PTERO/app/Http/Kernel.php"

    echo "[INFO] Membersihkan cache..."
    cd "$PTERO"
    php artisan optimize:clear

    echo ""
    echo "====================================="
    echo " ANTI RUSUH ULTRA FINAL DIHAPUS!"
    echo "====================================="
}

menu(){
    banner
    echo "1) Install"
    echo "2) Uninstall"
    echo "3) Exit"
    read -p "Pilih: " x
    [ "$x" = "1" ] && install
    [ "$x" = "2" ] && uninstall
}

menu
