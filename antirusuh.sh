#!/bin/bash

PTERO="/var/www/pterodactyl"
ROUTES="$PTERO/routes/admin.php"
KERNEL="$PTERO/app/Http/Kernel.php"
MW="$PTERO/app/Http/Middleware/WhitelistAdmin.php"
USERCTL="$PTERO/app/Http/Controllers/Admin/UserController.php"
SERVERDIR="$PTERO/app/Http/Controllers/Admin/Servers"

backup(){
    cp $ROUTES $ROUTES.bak_$(date +%s)
    cp $KERNEL $KERNEL.bak_$(date +%s)
}

fix_kernel(){
    sed -i "/whitelistadmin/d" $KERNEL
    sed -i "/'throttle' => ThrottleRequests::class,/a\        'whitelistadmin' => \\\\App\\\\Http\\\\Middleware\\\\WhitelistAdmin::class," $KERNEL
}

fix_routes(){
    perl -0777 -pe "s/Route::group\(\['prefix' => 'nodes'],/Route::group(['prefix' => 'nodes','middleware'=>['whitelistadmin']],/g" -i $ROUTES
    perl -0777 -pe "s/Route::group\(\['prefix' => 'locations'],/Route::group(['prefix' => 'locations','middleware'=>['whitelistadmin']],/g" -i $ROUTES
    perl -0777 -pe "s/Route::group\(\['prefix' => 'databases'],/Route::group(['prefix' => 'databases','middleware'=>['whitelistadmin']],/g" -i $ROUTES
    perl -0777 -pe "s/Route::group\(\['prefix' => 'mounts'],/Route::group(['prefix' => 'mounts','middleware'=>['whitelistadmin']],/g" -i $ROUTES
    perl -0777 -pe "s/Route::group\(\['prefix' => 'nests'],/Route::group(['prefix' => 'nests','middleware'=>['whitelistadmin']],/g" -i $ROUTES
}

block_delete_user(){
    sed -i "s#Route::delete('/view/{user:id}'.*#Route::delete('/view/{user:id}', function(){ abort(403,'ngapain wok'); })->middleware('whitelistadmin');#g" $ROUTES
}

block_server_actions(){
    for file in $SERVERDIR/*.php; do
        sed -i "/public function delete/!b;n;/}/i\        if (!in_array(auth()->user()->id, [OWNER_ID])) abort(403, 'ngapain wok');" $file
        sed -i "/public function destroy/!b;n;/}/i\        if (!in_array(auth()->user()->id, [OWNER_ID])) abort(403, 'ngapain wok');" $file
        sed -i "/public function view/!b;n;/}/i\        if (!in_array(auth()->user()->id, [OWNER_ID])) abort(403, 'ngapain wok');" $file
        sed -i "/public function details/!b;n;/}/i\        if (!in_array(auth()->user()->id, [OWNER_ID])) abort(403, 'ngapain wok');" $file
    done
}

install_antirusuh(){
    backup
    echo -n "Masukkan ID Owner: "
    read OWNER_ID

cat > $MW << EOF
<?php
namespace App\Http\Middleware;
use Closure;
use Illuminate\Http\Request;

class WhitelistAdmin{
    public function handle(Request \$request, Closure \$next){
        \$allowedAdmins = [$OWNER_ID];
        if(!in_array(\$request->user()->id, \$allowedAdmins)){
            abort(403,'ngapain wok');
        }
        return \$next(\$request);
    }
}
EOF

    fix_kernel
    fix_routes
    block_delete_user
    block_server_actions

    cd $PTERO
    php artisan optimize:clear
    echo "AntiRusuh berhasil diinstall"
}

add_owner(){
    echo -n "Masukkan ID Owner tambahan: "
    read NEW
    sed -i "s/\\\$allowedAdmins = \[\(.*\)\];/\$allowedAdmins = [\1,$NEW];/" $MW
    php $PTERO/artisan optimize:clear
}

uninstall_antirusuh(){
    backup
    rm -f $MW
    sed -i "/whitelistadmin/d" $KERNEL
    perl -0777 -pe "s/,'middleware'=>\['whitelistadmin'\]//g" -i $ROUTES
    sed -i "/ngapain wok/d" $ROUTES

    cd $PTERO
    php artisan optimize:clear
    echo "AntiRusuh dihapus, panel kembali seperti semula"
}

while true; do
    clear
    echo "1. Install AntiRusuh anjing"
    echo "2. Tambahkan Owner"
    echo "3. Uninstall AntiRusuh"
    echo "4. Exit"
    read -p "Pilih: " x

    case $x in
        1) install_antirusuh ;;
        2) add_owner ;;
        3) uninstall_antirusuh ;;
        4) exit ;;
    esac
done
