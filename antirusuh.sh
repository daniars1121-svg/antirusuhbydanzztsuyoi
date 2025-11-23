#!/bin/bash

PTERO="/var/www/pterodactyl"
ROUTES="$PTERO/routes/admin.php"
MIDDLEWARE="$PTERO/app/Http/Middleware/AntiRusuh.php"
KERNEL="$PTERO/app/Http/Kernel.php"

install_antirusuh() {
    echo "Masukkan ID Owner:"
    read OWNER_ID

    cat > $MIDDLEWARE << EOF
<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

class AntiRusuh
{
    public function handle(Request \$request, Closure \$next)
    {
        \$allowed = [$OWNER_ID];

        if (!in_array(\$request->user()->id, \$allowed)) {
            abort(403, 'ngapain wok');
        }

        return \$next(\$request);
    }
}
EOF

    if ! grep -q "antirusuh" "$KERNEL"; then
        sed -i "/protected \$middlewareAliases = \[/a\        'antirusuh' => \\\\App\\\\Http\\\\Middleware\\\\AntiRusuh::class," $KERNEL
    fi

    patch_route() {
        prefix=$1
        sed -i "s/\['prefix' => '$prefix'\]/['prefix' => '$prefix', 'middleware' => ['antirusuh']]/g" $ROUTES
    }

    patch_route "nodes"
    patch_route "locations"
    patch_route "databases"
    patch_route "servers"
    patch_route "users"
    patch_route "mounts"
    patch_route "nests"
    patch_route "settings"

    cd $PTERO
    php artisan route:clear
    php artisan config:clear
    php artisan view:clear
    php artisan cache:clear
    systemctl restart pteroq
}

add_owner() {
    echo "Masukkan ID Owner baru:"
    read NEW_OWNER

    sed -i "s/\$allowed = \[\(.*\)\];/\$allowed = [\1, $NEW_OWNER];/" $MIDDLEWARE

    cd $PTERO
    php artisan route:clear
    php artisan cache:clear
}

uninstall_antirusuh() {
    rm -f $MIDDLEWARE

    sed -i "/'antirusuh' =>/d" $KERNEL

    restore_route() {
        prefix=$1
        sed -i "s/\['prefix' => '$prefix', 'middleware' => \['antirusuh'\]\]/['prefix' => '$prefix']/g" $ROUTES
    }

    restore_route "nodes"
    restore_route "locations"
    restore_route "databases"
    restore_route "servers"
    restore_route "users"
    restore_route "mounts"
    restore_route "nests"
    restore_route "settings"

    cd $PTERO
    php artisan route:clear
    php artisan config:clear
    php artisan view:clear
    php artisan cache:clear
    systemctl restart pteroq
}

while true
do
    clear
    echo "1. Install AntiRusuh"
    echo "2. Tambah Owner"
    echo "3. Uninstall AntiRusuh"
    echo "4. Exit"
    read choice

    case $choice in
        1) install_antirusuh ;;
        2) add_owner ;;
        3) uninstall_antirusuh ;;
        4) exit ;;
    esac
done
