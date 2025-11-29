#!/bin/bash
set -e

PTERO="/var/www/pterodactyl"
KERNEL="$PTERO/app/Http/Kernel.php"
MW="$PTERO/app/Http/Middleware/AntiRusuhMiddleware.php"

banner() {
    echo "======================================="
    echo "     ANTI RUSUH KERNEL FINAL (WORKING)"
    echo "======================================="
}

install(){
    banner
    read -p "Masukkan ID Owner Utama: " OWNER

cat > "$MW" <<EOF
<?php
namespace App\Http\Middleware;

use Closure;

class AntiRusuhMiddleware {

    public function handle(\$req, Closure \$next) {

        \$u = \$req->user();
        if (!\$u) return abort(403,"ngapain wok");

        \$path = trim(\$req->path(), '/');

        // Proteksi semua halaman admin (kecuali owner)
        if (strpos(\$path, 'admin') === 0 &&
            \$u->id != $OWNER &&
            empty(\$u->root_admin)) {

            return abort(403,"ngapain wok");
        }

        // Proteksi akses server API
        if (\$req->route()?->parameter('server')) {
            \$srv = \$req->route()->parameter('server');

            if (\$srv->owner_id != \$u->id &&
                empty(\$u->root_admin) &&
                \$u->id != $OWNER) {

                return abort(403,"ngapain wok");
            }
        }

        return \$next(\$req);
    }
}
EOF

    echo "[+] Menambahkan alias ke Kernel.php..."
    if ! grep -q "antirusuh" "$KERNEL"; then
        sed -i "/protected \$middlewareAliases/a\        'antirusuh' => \\\\App\\\\Http\\\\Middleware\\\\AntiRusuhMiddleware::class," "$KERNEL"
    fi

    echo "[+] Menambahkan middleware ke group web..."
    if ! grep -q "AntiRusuhMiddleware" "$KERNEL"; then
        sed -i "/'web' => \[/a\            \\\\App\\\\Http\\\\Middleware\\\\AntiRusuhMiddleware::class," "$KERNEL"
    fi

    echo "[+] Menambahkan middleware ke group client-api..."
    sed -i "/'client-api' => \[/a\            \\\\App\\\\Http\\\\Middleware\\\\AntiRusuhMiddleware::class," "$KERNEL"

    cd "$PTERO"
    php artisan optimize:clear

    echo "======================================="
    echo " ANTI RUSUH KERNEL FINAL TERPASANG!"
    echo "======================================="
}

uninstall(){
    banner

    rm -f "$MW"

    sed -i "/AntiRusuhMiddleware/d" "$KERNEL"
    sed -i "/antirusuh/d" "$KERNEL"

    cd "$PTERO"
    php artisan optimize:clear

    echo "======================================="
    echo " ANTI RUSUH DIHAPUS!"
    echo "======================================="
}

menu(){
    banner
    echo "1) Install"
    echo "2) Uninstall"
    echo "3) Exit"
    read -p "Pilih: " x

    case $x in
        1) install ;;
        2) uninstall ;;
        3) exit ;;
    esac
}

menu
