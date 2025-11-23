#!/bin/bash

PTERO="/var/www/pterodactyl"
ROUTES="$PTERO/routes/admin.php"
KERNEL="$PTERO/app/Http/Kernel.php"
MW="$PTERO/app/Http/Middleware/WhitelistAdmin.php"

###################################################
# AUTO FIX admin.php
###################################################
autofix_routes() {
    echo "[AUTO-FIX] Memperbaiki admin.php..."

    # Perbaiki koma ganda
    sed -i 's/,,/,/g' $ROUTES

    # Perbaiki kurung array yang rusak
    sed -i 's/\],]/],/g' $ROUTES
    sed -i 's/\],,/\],/g' $ROUTES

    # Perbaiki route 'middleware' => []
    sed -i "s/'middleware' => \[\],//g" $ROUTES

    # Perbaiki prefix yang hilang
    sed -i "s/'prefix' => 'nodes', 'middleware/'prefix' => 'nodes','middleware/g" $ROUTES
    sed -i "s/'prefix' => 'locations', 'middleware/'prefix' => 'locations','middleware/g" $ROUTES
    sed -i "s/'prefix' => 'nests', 'middleware/'prefix' => 'nests','middleware/g" $ROUTES
    sed -i "s/'prefix' => 'mounts', 'middleware/'prefix' => 'mounts','middleware/g" $ROUTES
    sed -i "s/'prefix' => 'databases', 'middleware/'prefix' => 'databases','middleware/g" $ROUTES

    echo "[OK] admin.php diperbaiki"
}

###################################################
# AUTO FIX Kernel.php
###################################################
autofix_kernel() {
    echo "[AUTO-FIX] Memperbaiki Kernel.php..."

    # Hapus baris rusak
    sed -i "/WhitelistAdm in/d" $KERNEL

    # Pastikan entry bersih
    sed -i "/whitelistadmin/d" $KERNEL

    # Tambahkan middleware fresh
    sed -i "/'throttle' =>/a \ \ \ \ 'whitelistadmin' => \App\\\Http\\\Middleware\\\WhitelistAdmin::class," $KERNEL

    echo "[OK] Kernel.php aman"
}

###################################################
# AUTO FIX Middleware
###################################################
autofix_middleware() {
    echo "[AUTO-FIX] Memeriksa WhitelistAdmin.php..."

    if ! grep -q "WhitelistAdmin" $MW; then
        echo "[AUTO-FIX] Middleware hilang, membuat ulang..."

cat > $MW <<EOF
<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

class WhitelistAdmin
{
    public function handle(Request \$request, Closure \$next)
    {
        \$allowedAdmins = [1];

        if (!in_array(\$request->user()->id, \$allowedAdmins)) {
            abort(403, 'ngapain wok');
        }

        return \$next(\$request);
    }
}
EOF

    fi

    echo "[OK] Middleware verified"
}

###################################################
# INSTALL ANTI RUSUH
###################################################
install_antirusuh() {
    echo "Masukkan ID Owner:"
    read OWNER_ID

cat > $MW <<EOF
<?php

namespace App\Http\Middleware;

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

    autofix_kernel

    sed -i "s/Route::group(['prefix' => 'nodes'],/Route::group(['prefix' => 'nodes','middleware' => ['whitelistadmin']],/g" $ROUTES
    sed -i "s/Route::group(['prefix' => 'locations'],/Route::group(['prefix' => 'locations','middleware' => ['whitelistadmin']],/g" $ROUTES
    sed -i "s/Route::group(['prefix' => 'databases'],/Route::group(['prefix' => 'databases','middleware' => ['whitelistadmin']],/g" $ROUTES
    sed -i "s/Route::group(['prefix' => 'mounts'],/Route::group(['prefix' => 'mounts','middleware' => ['whitelistadmin']],/g" $ROUTES
    sed -i "s/Route::group(['prefix' => 'nests'],/Route::group(['prefix' => 'nests','middleware' => ['whitelistadmin']],/g" $ROUTES

    autofix_routes

    cd $PTERO && php artisan optimize:clear

    echo "AntiRusuh berhasil diinstall!"
}

###################################################
# TAMBAH OWNER
###################################################
add_owner() {
    echo "Masukkan ID Owner tambahan:"
    read NEW_ID
    sed -i "s/\[\(.*\)\]/[\1,$NEW_ID]/" $MW
    cd $PTERO && php artisan optimize:clear
    echo "Owner baru berhasil ditambahkan!"
}

###################################################
# UNINSTALL (ADA AUTO-FIX)
###################################################
uninstall_antirusuh() {
    sed -i "/whitelistadmin/d" $KERNEL
    sed -i "s/,'middleware' => \['whitelistadmin'\]//g" $ROUTES
    rm -f $MW

    autofix_routes
    autofix_kernel

    cd $PTERO && php artisan optimize:clear

    echo "AntiRusuh berhasil dihapus!"
}

###################################################
# MENU
###################################################
menu() {
    clear
    echo "1. Install AntiRusuh"
    echo "2. Tambahkan Owner"
    echo "3. Uninstall AntiRusuh"
    echo "4. Exit"
    read -p "Pilih menu: " pil

    case $pil in
        1) install_antirusuh ;;
        2) add_owner ;;
        3) uninstall_antirusuh ;;
        4) exit ;;
        *) echo "Pilihan salah" ;;
    esac
}

menu
