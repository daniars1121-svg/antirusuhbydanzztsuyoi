#!/bin/bash

PANEL_PATH="/var/www/pterodactyl"
MW_PATH="$PANEL_PATH/app/Http/Middleware/AntiRusuh.php"
PROVIDER_PATH="$PANEL_PATH/app/Providers/AntiRusuhProvider.php"
CONFIG_APP="$PANEL_PATH/config/app.php"

echo "==============================="
echo " ANTI RUSUH FINAL V9 (AMANKAN)"
echo "==============================="
echo "1) Install"
echo "2) Uninstall"
read -p "Pilih: " P

if [[ "$P" == "1" ]]; then
    read -p "Masukkan ID Owner Utama: " OWNER

    echo "→ Membuat AntiRusuh Middleware..."
    cat > "$MW_PATH" <<EOF
<?php

namespace Pterodactyl\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;

class AntiRusuh
{
    public function handle(Request \$request, Closure \$next)
    {
        \$owner = env('ANTIRUSUH_OWNER', 1);
        \$user = Auth::user();

        if (!\$user) return abort(403, 'Forbidden');

        // Boleh akses admin hanya pemilik
        if (\$request->is('admin/*') || \$request->is('api/application/*')) {
            if (\$user->id != \$owner) {
                return abort(403, 'Akses ditolak: Kamu bukan owner.');
            }
        }

        return \$next(\$request);
    }
}
EOF

    echo "→ Membuat Provider..."
    cat > "$PROVIDER_PATH" <<EOF
<?php

namespace Pterodactyl\Providers;

use Illuminate\Support\ServiceProvider;
use Illuminate\Support\Facades\Route;

class AntiRusuhProvider extends ServiceProvider
{
    public function boot()
    {
        Route::middlewareGroup('web', array_merge(
            Route::getMiddlewareGroups()['web'],
            [\Pterodactyl\Http\Middleware\AntiRusuh::class]
        ));
    }
}
EOF

    echo "→ Register provider..."
    if ! grep -q "AntiRusuhProvider" "$CONFIG_APP"; then
        sed -i "/App\\\Providers\\\RouteServiceProvider::class,/a \ \ \ \ Pterodactyl\\\Providers\\\AntiRusuhProvider::class," "$CONFIG_APP"
    fi

    echo "→ Menambah ENV..."
    if ! grep -q "ANTIRUSUH_OWNER" "$PANEL_PATH/.env"; then
        echo "ANTIRUSUH_OWNER=$OWNER" >> "$PANEL_PATH/.env"
    else
        sed -i "s/ANTIRUSUH_OWNER=.*/ANTIRUSUH_OWNER=$OWNER/" "$PANEL_PATH/.env"
    fi

    echo "→ Membersihkan cache..."
    cd $PANEL_PATH
    php artisan optimize:clear

    echo "==============================="
    echo "   ANTI RUSUH AKTIF V9 ✔"
    echo "   Hanya ID = $OWNER yg bisa buka admin"
    echo "==============================="

elif [[ "$P" == "2" ]]; then
    echo "→ Menghapus Anti Rusuh..."
    rm -f "$MW_PATH"
    rm -f "$PROVIDER_PATH"

    sed -i "/AntiRusuhProvider/d" "$CONFIG_APP"
    sed -i "/ANTIRUSUH_OWNER/d" "$PANEL_PATH/.env"

    cd $PANEL_PATH
    php artisan optimize:clear

    echo "==============================="
    echo "   ANTI RUSUH DIHAPUS ✔"
    echo "==============================="
else
    echo "Pilihan salah!"
fi
