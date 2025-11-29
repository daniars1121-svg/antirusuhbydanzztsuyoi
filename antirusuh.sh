#!/bin/bash
set -e

PTERO="/var/www/pterodactyl"
MW="$PTERO/app/Http/Middleware/AntiRusuh.php"
PROVIDER="$PTERO/app/Providers/AntiRusuhProvider.php"
CONFIG="$PTERO/config/antirusuh.php"

banner(){
    echo "==============================="
    echo "  ANTI RUSUH FINAL V8 (STABLE)"
    echo "==============================="
}

install(){
    banner
    read -p "Masukkan ID Owner Utama: " OWNER
    mkdir -p "$PTERO/config"

cat > "$CONFIG" <<EOF
<?php
return [
    "owner" => $OWNER,
    "blocked" => [
        "admin/nodes",
        "admin/servers",
        "admin/databases",
        "admin/users",
        "admin/locations",
        "admin/mounts",
        "admin/nests",
    ],
];
EOF

cat > "$MW" <<EOF
<?php
namespace Pterodactyl\Http\Middleware;

use Closure;

class AntiRusuh
{
    public function handle(\$req, Closure \$next)
    {
        \$cfg = config("antirusuh");
        \$owner = \$cfg["owner"];
        \$blocked = \$cfg["blocked"];

        \$u = \$req->user();
        if (!\$u) return \$next(\$req);

        \$path = ltrim(\$req->path(), "/");

        foreach (\$blocked as \$b){
            if (strpos(\$path, \$b) === 0){
                if (\$u->id != \$owner && !\$u->root_admin){
                    abort(403, "Tidak diizinkan.");
                }
            }
        }

        if (\$req->route()?->parameter("server")){
            \$s = \$req->route()->parameter("server");
            if (\$s->owner_id != \$u->id && !\$u->root_admin && \$u->id != \$owner){
                abort(403, "Tidak diizinkan.");
            }
        }

        return \$next(\$req);
    }
}
EOF

cat > "$PROVIDER" <<EOF
<?php
namespace App\Providers;

use Illuminate\Support\ServiceProvider;
use Pterodactyl\Http\Middleware\AntiRusuh;

class AntiRusuhProvider extends ServiceProvider
{
    public function boot()
    {
        if (file_exists(config_path("antirusuh.php"))){
            app("router")->pushMiddlewareToGroup("web", AntiRusuh::class);
        }
    }
}
EOF

echo "App\\Providers\\AntiRusuhProvider" >> "$PTERO/config/app.php"

cd "$PTERO"
composer dump-autoload -o
php artisan optimize:clear
systemctl restart pteroq

echo "==============================="
echo "  Anti Rusuh Final V8 Terpasang"
echo "==============================="
}

uninstall(){
    rm -f "$MW" "$PROVIDER" "$CONFIG"
    sed -i "/AntiRusuhProvider/d" "$PTERO/config/app.php"

    cd "$PTERO"
    composer dump-autoload -o
    php artisan optimize:clear
    systemctl restart pteroq

    echo "Anti Rusuh Final V8 dihapus."
}

banner
echo "1) Instal"
echo "2) Uninstall"
read -p "Pilih: " x

[ "$x" = "1" ] && install
[ "$x" = "2" ] && uninstall
