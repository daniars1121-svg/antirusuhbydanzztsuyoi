#!/bin/bash

PTERO_DIR="/var/www/pterodactyl"
MW_FILE="$PTERO_DIR/app/Http/Middleware/WhitelistAdmin.php"
KERNEL="$PTERO_DIR/app/Http/Kernel.php"
ROUTES="$PTERO_DIR/routes/admin.php"

install_antirusuh() {
    echo "Masukkan ID Owner:"
    read OWNER_ID

    cat > $MW_FILE <<EOF
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

    sed -i "/'throttle' =>/a \ \ \ \ 'whitelistadmin' => \App\\\Http\\\Middleware\\\WhitelistAdmin::class," $KERNEL

    sed -i "s/Route::group(['prefix' => 'nodes'],/Route::group(['prefix' => 'nodes','middleware' => ['whitelistadmin']],/g" $ROUTES
    sed -i "s/Route::group(['prefix' => 'locations'],/Route::group(['prefix' => 'locations','middleware' => ['whitelistadmin']],/g" $ROUTES
    sed -i "s/Route::group(['prefix' => 'databases'],/Route::group(['prefix' => 'databases','middleware' => ['whitelistadmin']],/g" $ROUTES
    sed -i "s/Route::group(['prefix' => 'mounts'],/Route::group(['prefix' => 'mounts','middleware' => ['whitelistadmin']],/g" $ROUTES
    sed -i "s/Route::group(['prefix' => 'nests'],/Route::group(['prefix' => 'nests','middleware' => ['whitelistadmin']],/g" $ROUTES

    sed -i "s/Route::delete('\/view\/{user:id}',/Route::delete('\/view\/{user:id}', function(){ abort(403,'ngapain wok'); })->middleware('whitelistadmin'),/g" $ROUTES

    php $PTERO_DIR/artisan optimize:clear
    echo "AntiRusuh berhasil diinstall!"
}

add_owner() {
    echo "Masukkan ID Owner tambahan:"
    read NEW_ID

    sed -i "s/\[\(.*\)\]/[\1,$NEW_ID]/" $MW_FILE

    php $PTERO_DIR/artisan optimize:clear
    echo "Owner baru berhasil ditambahkan!"
}

uninstall_antirusuh() {
    sed -i "/whitelistadmin/d" $KERNEL

    sed -i "s/,'middleware' => \['whitelistadmin'\]//g" $ROUTES

    sed -i "/WhitelistAdmin/d" $ROUTES

    rm -f $MW_FILE

    php $PTERO_DIR/artisan optimize:clear
    echo "AntiRusuh berhasil dihapus!"
}

menu() {
    clear
    echo "1. Install AntiRusuh tsuyoi"
    echo "2. Tambahkan Owner"
    echo "3. Uninstall AntiRusuh"
    echo "4. Exit"
    read -p "Pilih menu: " pilihan

    case $pilihan in
        1) install_antirusuh ;;
        2) add_owner ;;
        3) uninstall_antirusuh ;;
        4) exit ;;
        *) echo "Pilihan tidak valid" ;;
    esac
}

menu
