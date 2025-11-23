#!/bin/bash

PTERO="/var/www/pterodactyl"
ROUTES="$PTERO/routes/admin.php"
MIDDLEWARE="$PTERO/app/Http/Middleware/WhitelistAdmin.php"
KERNEL="$PTERO/app/Http/Kernel.php"

menu(){
echo "1. Install AntiRusuh"
echo "2. Tambahkan Owner"
echo "3. Uninstall AntiRusuh"
echo "4. Exit"
read -p "Pilih: " p
}

add_mw(){
local p="$1"
if ! grep -q "prefix' => '$p', 'middleware' => \['whitelistadmin'\]" "$ROUTES"; then
sed -i "s|\['prefix' => '$p'\]|\['prefix' => '$p', 'middleware' => ['whitelistadmin']\]|g" "$ROUTES"
fi
}

del_mw(){
local p="$1"
sed -i "s|\['prefix' => '$p', 'middleware' => \['whitelistadmin'\]\]|\['prefix' => '$p'\]|g" "$ROUTES"
}

menu

if [[ $p == 1 ]]; then
read -p "ID Owner: " O

mkdir -p "$PTERO/app/Http/Middleware"

cat > $MIDDLEWARE <<EOF
<?php
namespace App\Http\Middleware;
use Closure;
use Illuminate\Http\Request;
class WhitelistAdmin{
public function handle(Request \$r, Closure \$n){
\$allow=[$O];
if(!in_array(\$r->user()->id,\$allow)){abort(403,'ngapain wok');}
return \$n(\$r);
}}
EOF

if ! grep -q "whitelistadmin" "$KERNEL"; then
sed -i "/protected \$middlewareAliases = \[/a\        'whitelistadmin' => \\\\App\\\\Http\\\\Middleware\\\\WhitelistAdmin::class," "$KERNEL"
fi

add_mw "nodes"
add_mw "locations"
add_mw "databases"
add_mw "mounts"
add_mw "nests"

cd $PTERO
php artisan route:clear
php artisan config:clear
php artisan view:clear
php artisan cache:clear
systemctl restart pteroq
fi

if [[ $p == 2 ]]; then
read -p "ID Owner Baru: " O2
sed -i "s/\[\(.*\)\]/[\1,$O2]/" "$MIDDLEWARE"
cd $PTERO
php artisan route:clear
fi

if [[ $p == 3 ]]; then
rm -f "$MIDDLEWARE"
sed -i "/whitelistadmin/d" "$KERNEL"

del_mw "nodes"
del_mw "locations"
del_mw "databases"
del_mw "mounts"
del_mw "nests"

cd $PTERO
php artisan route:clear
php artisan config:clear
php artisan view:clear
php artisan cache:clear
systemctl restart pteroq
fi
