#!/bin/bash

PTERO="/var/www/pterodactyl"
ROUTES_ADMIN="$PTERO/routes/admin.php"
ROUTES_CLIENT="$PTERO/routes/client.php"
MIDDLEWARE_ADMIN="$PTERO/app/Http/Middleware/WhitelistAdmin.php"
MIDDLEWARE_CLIENT="$PTERO/app/Http/Middleware/ClientServerWhitelist.php"
KERNEL="$PTERO/app/Http/Kernel.php"
USERCTL="$PTERO/app/Http/Controllers/Admin/UserController.php"
SERVERDIR="$PTERO/app/Http/Controllers/Admin/Servers"

install_antirusuh() {
    echo "Masukkan ID Owner:"
    read OWNER_ID

    # =======================
    # 1. Middleware ADMIN
    # =======================
    cat > $MIDDLEWARE_ADMIN << EOF
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

    # =======================
    # 2. Middleware CLIENT LOCK
    # =======================
    cat > $MIDDLEWARE_CLIENT << EOF
<?php

namespace Pterodactyl\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

class ClientServerWhitelist
{
    public function handle(Request \$request, Closure \$next)
    {
        \$owner = [$OWNER_ID];
        \$user = \$request->user();

        if (in_array(\$user->id, \$owner)) return \$next(\$request);

        if (\$request->route()->parameter('server')) {
            \$server = \$request->route()->parameter('server');

            if (\$server->owner_id !== \$user->id) {
                abort(403, 'ngapain wok');
            }
        }

        return \$next(\$request);
    }
}
EOF

    # =======================
    # 3. Kernel Middleware
    # =======================
    if ! grep -q "whitelistadmin" "$KERNEL"; then
        sed -i "/protected \$middlewareAliases = \[/a\        'whitelistadmin' => \\\\Pterodactyl\\\\Http\\\\Middleware\\\\WhitelistAdmin::class," $KERNEL
    fi

    if ! grep -q "clientlock" "$KERNEL"; then
        sed -i "/protected \$middlewareAliases = \[/a\        'clientlock' => \\\\Pterodactyl\\\\Http\\\\Middleware\\\\ClientServerWhitelist::class," $KERNEL
    fi

    # =======================
    # 4. Admin Route Protection
    # =======================
    lock_admin_route() {
        sed -i "s/\['prefix' => '$1'\]/['prefix' => '$1', 'middleware' => ['whitelistadmin']]/" $ROUTES_ADMIN
    }

    lock_admin_route "nodes"
    lock_admin_route "locations"
    lock_admin_route "databases"
    lock_admin_route "mounts"
    lock_admin_route "nests"

    # =======================
    # 5. Client Panel Lock
    # =======================
    if ! grep -q "clientlock" "$ROUTES_CLIENT"; then
        sed -i "s/Route::group(\['prefix' => '\/servers'/Route::group(['prefix' => '\/servers', 'middleware' => ['clientlock']]/" $ROUTES_CLIENT
    fi

    # =======================
    # 6. Protect delete user
    # =======================
    sed -i "/public function delete/!b;n;/}/i\        \$allowedAdmins = [$OWNER_ID];\n        if (!in_array(auth()->user()->id, \$allowedAdmins)) abort(403, 'ngapain wok');" $USERCTL

    # =======================
    # 7. Protect server actions
    # =======================
    for file in $SERVERDIR/*.php; do
        sed -i "/public function delete/!b;n;/}/i\        \$allowedAdmins = [$OWNER_ID];\n        if (!in_array(auth()->user()->id, \$allowedAdmins)) abort(403, 'ngapain wok');" $file
        sed -i "/public function destroy/!b;n;/}/i\        \$allowedAdmins = [$OWNER_ID];\n        if (!in_array(auth()->user()->id, \$allowedAdmins)) abort(403, 'ngapain wok');" $file
        sed -i "/public function view/!b;n;/}/i\        \$allowedAdmins = [$OWNER_ID];\n        if (!in_array(auth()->user()->id, \$allowedAdmins)) abort(403, 'ngapain wok');" $file
        sed -i "/public function details/!b;n;/}/i\        \$allowedAdmins = [$OWNER_ID];\n        if (!in_array(auth()->user()->id, \$allowedAdmins)) abort(403, 'ngapain wok');" $file
    done

    # =======================
    # 8. Clear Cache
    # =======================
    cd $PTERO
    php artisan route:clear
    php artisan cache:clear
    php artisan config:clear
    systemctl restart pteroq
}

uninstall_antirusuh() {
    rm -f $MIDDLEWARE_ADMIN
    rm -f $MIDDLEWARE_CLIENT

    sed -i "/'whitelistadmin' =>/d" $KERNEL
    sed -i "/'clientlock' =>/d" $KERNEL

    unlock_admin_route() {
        sed -i "s/'middleware' => \['whitelistadmin'\]//" $ROUTES_ADMIN
    }

    unlock_admin_route "nodes"
    unlock_admin_route "locations"
    unlock_admin_route "databases"
    unlock_admin_route "mounts"
    unlock_admin_route "nests"

    sed -i "s/'middleware' => \['clientlock'\]//" $ROUTES_CLIENT

    sed -i "/ngapain wok/d" $USERCTL
    for file in $SERVERDIR/*.php; do
        sed -i "/ngapain wok/d" $file
    done

    cd $PTERO
    php artisan route:clear
    php artisan cache:clear
    php artisan config:clear
    systemctl restart pteroq
}

while true
do
    clear
    echo "1. Install AntiRusuh + Client Lock"
    echo "2. Uninstall AntiRusuh"
    echo "3. Exit"
    read choice

    case $choice in
        1) install_antirusuh ;;
        2) uninstall_antirusuh ;;
        3) exit ;;
    esac

    read
done
