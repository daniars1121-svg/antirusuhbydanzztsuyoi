#!/bin/bash

PTERO="/var/www/pterodactyl"
ROUTES="$PTERO/routes/admin.php"
MIDDLEWARE="$PTERO/app/Http/Middleware/WhitelistAdmin.php"
KERNEL="$PTERO/app/Http/Kernel.php"
USERCTL="$PTERO/app/Http/Controllers/Admin/UserController.php"
SERVERDIR="$PTERO/app/Http/Controllers/Admin/Servers"

install_antirusuh() {
    echo "Masukkan ID Owner:"
    read OWNER_ID

    # Buat middleware dengan namespace PTERODACTYL (fix utama)
    cat > $MIDDLEWARE << EOF
<?php

namespace Pterodactyl\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

class WhitelistAdmin
{
    public function handle(Request \$request, Closure \$next)
    {
        \$allowedAdmins = [$OWNER_ID];

        if (!in_array(\$request->user()->id, \$allowedAdmins)) {
            abort(403, 'ngapain wok');
        }

        return \$next(\$request);
    }
}
EOF

    # Tambah alias ke kernel (namespace sudah benar)
    if ! grep -q "whitelistadmin" "$KERNEL"; then
        sed -i "/protected \$middlewareAliases = \[/a\        'whitelistadmin' => \\\\Pterodactyl\\\\Http\\\\Middleware\\\\WhitelistAdmin::class," $KERNEL
    fi

    lock_route() {
        sed -i "s/\['prefix' => '$1'\]/['prefix' => '$1', 'middleware' => ['whitelistadmin']]/g" $ROUTES
    }

    lock_route "nodes"
    lock_route "locations"
    lock_route "databases"
    lock_route "mounts"
    lock_route "nests"

    # Proteksi delete user
    sed -i "/public function delete/!b;n;/}/i\        \$allowedAdmins = [$OWNER_ID];\n        if (!in_array(auth()->user()->id, \$allowedAdmins)) abort(403, 'ngapain wok');" $USERCTL

    # Proteksi server actions
    for file in $SERVERDIR/*.php; do
        sed -i "/public function delete/!b;n;/}/i\        \$allowedAdmins = [$OWNER_ID];\n        if (!in_array(auth()->user()->id, \$allowedAdmins)) abort(403, 'ngapain wok');" $file
        sed -i "/public function destroy/!b;n;/}/i\        \$allowedAdmins = [$OWNER_ID];\n        if (!in_array(auth()->user()->id, \$allowedAdmins)) abort(403, 'ngapain wok');" $file
        sed -i "/public function view/!b;n;/}/i\        \$allowedAdmins = [$OWNER_ID];\n        if (!in_array(auth()->user()->id, \$allowedAdmins)) abort(403, 'ngapain wok');" $file
        sed -i "/public function details/!b;n;/}/i\        \$allowedAdmins = [$OWNER_ID];\n        if (!in_array(auth()->user()->id, \$allowedAdmins)) abort(403, 'ngapain wok');" $file
    done

    cd $PTERO
    php artisan route:clear
    php artisan config:clear
    php artisan view:clear
    php artisan cache:clear
    systemctl restart pteroq
}

add_owner() {
    echo "Masukkan ID Owner Baru:"
    read NEW_OWNER
    sed -i "s/\$allowedAdmins = \[\(.*\)\];/\$allowedAdmins = [\1, $NEW_OWNER];/" $MIDDLEWARE
    cd $PTERO
    php artisan route:clear
}

uninstall_antirusuh() {
    rm -f $MIDDLEWARE

    sed -i "/'whitelistadmin' =>/d" $KERNEL

    unlock_route() {
        sed -i "s/\['prefix' => '$1', 'middleware' => \['whitelistadmin'\]\]/['prefix' => '$1']/g" $ROUTES
    }

    unlock_route "nodes"
    unlock_route "locations"
    unlock_route "databases"
    unlock_route "mounts"
    unlock_route "nests"

    sed -i "/ngapain wok/d" $USERCTL
    for file in $SERVERDIR/*.php; do
        sed -i "/ngapain wok/d" $file
    done

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
    echo "2. Tambahkan Owner"
    echo "3. Uninstall AntiRusuh"
    echo "4. Exit"
    read choice

    case $choice in
        1) install_antirusuh ;;
        2) add_owner ;;
        3) uninstall_antirusuh ;;
        4) exit ;;
    esac

    read
done
