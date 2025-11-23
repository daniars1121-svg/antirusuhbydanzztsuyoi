#!/bin/bash

PTERO="/var/www/pterodactyl"
ROUTES_ADMIN="$PTERO/routes/admin.php"
ROUTES_CLIENT="$PTERO/routes/client.php"
MIDDLEWARE_ADMIN="$PTERO/app/Http/Middleware/WhitelistAdmin.php"
MIDDLEWARE_CLIENT="$PTERO/app/Http/Middleware/ClientServerWhitelist.php"
KERNEL="$PTERO/app/Http/Kernel.php"
USERCTL="$PTERO/app/Http/Controllers/Admin/UserController.php"
SERVERDIR="$PTERO/app/Http/Controllers/Admin/Servers"

# ========= GET CURRENT OWNERS FROM FILE =========
get_owners() {
    grep "\$allowedAdmins" $MIDDLEWARE_ADMIN | sed -E "s/.*\[(.*)\].*/\1/" | tr -d ' '
}

# ========= SAVE NEW OWNERS TO BOTH FILES =========
save_owners() {
    sed -i "s/\$allowedAdmins = \[.*\];/\$allowedAdmins = [$1];/" $MIDDLEWARE_ADMIN
    sed -i "s/\$allowedAdmins = \[.*\];/\$allowedAdmins = [$1];/" $MIDDLEWARE_CLIENT
}

# =================================================
# INSTALL ANTI RUSUH
# =================================================

install_antirusuh() {
    echo "Masukkan ID Owner:"
    read OWNER_ID

    # =========================
    # 1. Middleware Admin
    # =========================
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

    # =========================
    # 2. Middleware Client Lock
    # =========================
    cat > $MIDDLEWARE_CLIENT << EOF
<?php

namespace Pterodactyl\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

class ClientServerWhitelist
{
    public function handle(Request \$request, Closure \$next)
    {
        \$allowedAdmins = [$OWNER_ID];
        \$user = \$request->user();

        if (in_array(\$user->id, \$allowedAdmins))
            return \$next(\$request);

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

    # =========================
    # 3. Register Middleware
    # =========================
    grep -q "whitelistadmin" $KERNEL || \
        sed -i "/protected \$middlewareAliases = \[/a\        'whitelistadmin' => \\\\Pterodactyl\\\\Http\\\\Middleware\\\\WhitelistAdmin::class," $KERNEL

    grep -q "clientlock" $KERNEL || \
        sed -i "/protected \$middlewareAliases = \[/a\        'clientlock' => \\\\Pterodactyl\\\\Http\\\\Middleware\\\\ClientServerWhitelist::class," $KERNEL

    # =========================
    # 4. Lock Admin Routes
    # =========================
    lock_route() {
        sed -i "s/\['prefix' => '$1'\]/['prefix' => '$1', 'middleware' => ['whitelistadmin']]/" $ROUTES_ADMIN
    }
    lock_route "nodes"
    lock_route "locations"
    lock_route "databases"
    lock_route "mounts"
    lock_route "nests"

    # =========================
    # 5. Lock Client Route
    # =========================
    sed -i "s/Route::group(\['prefix' => '\/servers'/Route::group(['prefix' => '\/servers', 'middleware' => ['clientlock']]/" $ROUTES_CLIENT

    # =========================
    # 6. Lock Server Actions
    # =========================
    for file in $SERVERDIR/*.php; do
        sed -i "/public function delete/!b;n;/}/i\        \$allowedAdmins = [$OWNER_ID];\n        if(!in_array(auth()->user()->id,\$allowedAdmins)) abort(403,'ngapain wok');" $file
        sed -i "/public function destroy/!b;n;/}/i\        \$allowedAdmins = [$OWNER_ID];\n        if(!in_array(auth()->user()->id,\$allowedAdmins)) abort(403,'ngapain wok');" $file
        sed -i "/public function view/!b;n;/}/i\        \$allowedAdmins = [$OWNER_ID];\n        if(!in_array(auth()->user()->id,\$allowedAdmins)) abort(403,'ngapain wok');" $file
        sed -i "/public function details/!b;n;/}/i\        \$allowedAdmins = [$OWNER_ID];\n        if(!in_array(auth()->user()->id,\$allowedAdmins)) abort(403,'ngapain wok');" $file
    done

    # =========================
    # 7. Lock User Delete
    # =========================
    sed -i "/public function delete/!b;n;/}/i\        \$allowedAdmins = [$OWNER_ID];\n        if(!in_array(auth()->user()->id,\$allowedAdmins)) abort(403,'ngapain wok');" $USERCTL

    cd $PTERO
    php artisan route:clear
    php artisan cache:clear
    php artisan config:clear
    systemctl restart pteroq
}

# =================================================
# TAMBAH OWNER
# =================================================

add_owner() {
    echo "Masukkan ID Owner Baru:"
    read NEW_OWNER

    CURRENT=$(get_owners)
    NEW="$CURRENT,$NEW_OWNER"

    save_owners "$NEW"

    cd $PTERO
    php artisan route:clear
}

# =================================================
# DELETE OWNER
# =================================================

delete_owner() {
    echo "Masukkan ID Owner yang ingin dihapus:"
    read DEL_OWNER

    CURRENT=$(get_owners)

    # hapus ID
    NEW=$(echo "$CURRENT" | sed "s/\b$DEL_OWNER\b//" | sed 's/,,/,/g' | sed 's/^,//' | sed 's/,$//')

    save_owners "$NEW"

    cd $PTERO
    php artisan route:clear
}

# =================================================
# UNINSTALL
# =================================================

uninstall_antirusuh() {
    rm -f $MIDDLEWARE_ADMIN
    rm -f $MIDDLEWARE_CLIENT

    sed -i "/'whitelistadmin' =>/d" $KERNEL
    sed -i "/'clientlock' =>/d" $KERNEL

    sed -i "s/'middleware' => \['clientlock'\]//" $ROUTES_CLIENT

    for prefix in nodes locations databases mounts nests; do
        sed -i "s/'middleware' => \['whitelistadmin'\]//" $ROUTES_ADMIN
    done

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

# =================================================
# MENU
# =================================================

while true
do
    clear
    echo "1. Install AntiRusuh rial cuy"
    echo "2. Tambah Owner"
    echo "3. Hapus Owner"
    echo "4. Uninstall AntiRusuh"
    echo "5. Exit"
    read choice

    case $choice in
        1) install_antirusuh ;;
        2) add_owner ;;
        3) delete_owner ;;
        4) uninstall_antirusuh ;;
        5) exit ;;
    esac

    read
done
