#!/bin/bash

PTERO="/var/www/pterodactyl"
ROUTES="$PTERO/routes/admin.php"
API_CLIENT="$PTERO/routes/api-client.php"
MIDDLEWARE_ADMIN="$PTERO/app/Http/Middleware/WhitelistAdmin.php"
MIDDLEWARE_CLIENT="$PTERO/app/Http/Middleware/ClientLock.php"
KERNEL="$PTERO/app/Http/Kernel.php"
USERCTL="$PTERO/app/Http/Controllers/Admin/UserController.php"
SERVERDIR="$PTERO/app/Http/Controllers/Admin/Servers"

# =========================
# GET CURRENT OWNERS
# =========================
get_owners() {
    if [ ! -f "$MIDDLEWARE_ADMIN" ]; then
        echo ""
        return
    fi
    grep "\$allowedAdmins" $MIDDLEWARE_ADMIN | sed -E "s/.*\[(.*)\].*/\1/" | tr -d ' '
}

save_owners() {
    sed -i "s/\$allowedAdmins = \[.*\];/\$allowedAdmins = [$1];/" $MIDDLEWARE_ADMIN
    sed -i "s/\$allowedAdmins = \[.*\];/\$allowedAdmins = [$1];/" $MIDDLEWARE_CLIENT
}

# =========================
# INSTALL
# =========================
install_antirusuh() {
    echo "Masukkan ID Owner:"
    read OWNER_ID

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

cat > $MIDDLEWARE_CLIENT << EOF
<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

class ClientLock
{
    public function handle(Request \$request, Closure \$next)
    {
        \$allowedAdmins = [$OWNER_ID];
        \$user = \$request->user();

        if (!\$user) abort(403, 'ngapain wok');

        if (in_array(\$user->id, \$allowedAdmins)) 
            return \$next(\$request);

        \$server = \$request->route('server');

        if (\$server && \$server->owner_id != \$user->id)
            abort(403, 'ngapain wok');

        return \$next(\$request);
    }
}
EOF

# REGISTER MIDDLEWARE
if ! grep -q "whitelistadmin" "$KERNEL"; then
    sed -i "/protected \$middlewareAliases = \[/a\        'whitelistadmin' => Pterodactyl\\\\Http\\\\Middleware\\\\WhitelistAdmin::class," $KERNEL
fi

if ! grep -q "clientlock" "$KERNEL"; then
    sed -i "/protected \$middlewareAliases = \[/a\        'clientlock' => App\\\\Http\\\\Middleware\\\\ClientLock::class," $KERNEL
fi

# LOCK ADMIN ROUTES
lock_route() {
    sed -i "s/\['prefix' => '$1'\]/['prefix' => '$1', 'middleware' => ['whitelistadmin']]/g" $ROUTES
}
lock_route "nodes"
lock_route "locations"
lock_route "databases"
lock_route "mounts"
lock_route "nests"

# =========================
# PATCH API CLIENT (SAFE)
# =========================
if grep -q "'prefix' => '/servers/{server}'" "$API_CLIENT"; then
    if ! grep -q "clientlock" "$API_CLIENT"; then
        sed -i "s/'prefix' => '\/servers\/{server}'/'prefix' => '\/servers\/{server}', 'middleware' => ['clientlock']/" $API_CLIENT
    fi
fi

# =========================
# PROTECT DELETE FUNCTIONS
# =========================
sed -i "/public function delete/!b;n;/}/i\        \$allowedAdmins = [$OWNER_ID]; if (!in_array(auth()->user()->id, \$allowedAdmins)) abort(403,'ngapain wok');" $USERCTL

for file in $SERVERDIR/*.php; do
    sed -i "/public function delete/!b;n;/}/i\        \$allowedAdmins = [$OWNER_ID]; if (!in_array(auth()->user()->id,\$allowedAdmins)) abort(403,'ngapain wok');" $file
    sed -i "/public function destroy/!b;n;/}/i\        \$allowedAdmins = [$OWNER_ID]; if (!in_array(auth()->user()->id,\$allowedAdmins)) abort(403,'ngapain wok');" $file
    sed -i "/public function details/!b;n;/}/i\         \$allowedAdmins = [$OWNER_ID]; if (!in_array(auth()->user()->id,\$allowedAdmins)) abort(403,'ngapain wok');" $file
done

cd $PTERO
php artisan route:clear
php artisan config:clear
php artisan view:clear
php artisan cache:clear
systemctl restart pteroq
}

# =========================
# ADD OWNER
# =========================
add_owner() {
    echo "Masukkan ID Owner Baru:"
    read NEW

    CUR=$(get_owners)
    if [[ ",$CUR," == *",$NEW,"* ]]; then
        echo "Owner sudah ada."
        return
    fi

    if [ -z "$CUR" ]; then
        NEWLIST="$NEW"
    else
        NEWLIST="$CUR,$NEW"
    fi

    save_owners "$NEWLIST"

    cd $PTERO
    php artisan route:clear
}

# =========================
# DELETE OWNER
# =========================
delete_owner() {
    echo "Masukkan ID Owner yang ingin dihapus:"
    read DEL

    CUR=$(get_owners)

    NEW=$(echo "$CUR" | sed "s/\b$DEL\b//" | sed 's/,,/,/g' | sed 's/^,//' | sed 's/,$//')

    save_owners "$NEW"

    cd $PTERO
    php artisan route:clear
}

# =========================
# UNINSTALL
# =========================
uninstall_antirusuh() {
    rm -f $MIDDLEWARE_ADMIN
    rm -f $MIDDLEWARE_CLIENT

    sed -i "/whitelistadmin/d" $KERNEL
    sed -i "/clientlock/d" $KERNEL

    sed -i "s/'clientlock',//g" $API_CLIENT

    unlock_route() {
        sed -i "s/'middleware' => \['whitelistadmin'\],//g" $ROUTES
    }
    unlock_route

    sed -i "/ngapain wok/d" $USERCTL
    for file in $SERVERDIR/*.php; do
        sed -i "/ngapain wok/d" $file
    done

    cd $PTERO
    php artisan route:clear
    php artisan config:clear
    php artisan cache:clear
    php artisan view:clear
    systemctl restart pteroq
}

# =========================
# MENU
# =========================
while true
do
    clear
    echo "1. Install AntiRusuh"
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
