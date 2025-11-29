#!/bin/bash

PANEL="/var/www/pterodactyl"

anti_rusuh_install() {
    echo "==============================="
    echo "  ANTI RUSUH FINAL V11 (STABLE)"
    echo "==============================="
    read -p "Masukkan ID Owner Utama: " OWNER

    echo "[+] Membuat Middleware..."
    cat > $PANEL/app/Http/Middleware/AntiRusuh.php << 'EOF'
<?php

namespace Pterodactyl\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;

class AntiRusuh
{
    public function handle(Request $request, Closure $next)
    {
        $allowedOwner = env('ANTIRUSUH_OWNER');

        if (!$allowedOwner) {
            return $next($request);
        }

        $user = Auth::user();

        if (!$user || $user->id != $allowedOwner) {
            return response()->view('errors.403', [], 403);
        }

        return $next($request);
    }
}
EOF

    echo "[+] Membuat Provider..."
    cat > $PANEL/app/Providers/AntiRusuhProvider.php << 'EOF'
<?php

namespace Pterodactyl\Providers;

use Illuminate\Support\ServiceProvider;

class AntiRusuhProvider extends ServiceProvider
{
    public function boot()
    {
        $router = $this->app['router'];
        $router->aliasMiddleware('anti_rusuh', \Pterodactyl\Http\Middleware\AntiRusuh::class);
    }
}
EOF

    echo "[+] Menambahkan provider ke config/app.php..."
    if ! grep -q "AntiRusuhProvider" $PANEL/config/app.php; then
        sed -i "/'providers' => \[/a \ \ \ \ Pterodactyl\\Providers\\AntiRusuhProvider::class," $PANEL/config/app.php
    fi

    echo "[+] Menambahkan ANTIRUSUH_OWNER ke .env..."
    sed -i '/ANTIRUSUH_OWNER/d' $PANEL/.env
    echo "ANTIRUSUH_OWNER=$OWNER" >> $PANEL/.env

    echo "[+] Patch admin.php route..."
    ADMIN="$PANEL/routes/admin.php"

    if ! grep -q "anti_rusuh" $ADMIN; then
        sed -i "1s/^/Route::middleware(['anti_rusuh'])->group(function () {\n/" $ADMIN
        echo "});" >> $ADMIN
    fi

    echo "[+] Membersihkan cache..."
    cd $PANEL
    composer dump-autoload
    php artisan optimize:clear

    echo "==============================="
    echo "   ANTI RUSUH FINAL V11 AKTIF"
    echo "   Hanya ID $OWNER bisa buka /admin"
    echo "==============================="
}

anti_rusuh_uninstall() {
    echo "[+] Menghapus Anti Rusuh FINAL V11..."

    rm -f $PANEL/app/Http/Middleware/AntiRusuh.php
    rm -f $PANEL/app/Providers/AntiRusuhProvider.php

    sed -i '/AntiRusuhProvider/d' $PANEL/config/app.php
    sed -i '/ANTIRUSUH_OWNER/d' $PANEL/.env

    ADMIN="$PANEL/routes/admin.php"
    sed -i '/anti_rusuh/d' $ADMIN
    sed -i 's/});$//' $ADMIN

    cd $PANEL
    composer dump-autoload
    php artisan optimize:clear

    echo "[✓] Anti Rusuh V11 telah dihapus."
}

echo "==============================="
echo "     ANTI RUSUH FINAL V11"
echo "==============================="
echo "1) Install"
echo "2) Uninstall"
read -p "Pilih: " PIL

if [[ $PIL == "1" ]]; then
    anti_rusuh_install
elif [[ $PIL == "2" ]]; then
    anti_rusuh_uninstall
else
    echo "Pilihan tidak valid!"
fi
