#!/bin/bash

PANEL="/var/www/pterodactyl"
MW="$PANEL/app/Http/Middleware/AntiRusuh.php"
KERNEL="$PANEL/app/Http/Kernel.php"
ENV="$PANEL/.env"

echo "==============================="
echo " ANTI RUSUH V10 (FULL WORK)"
echo "==============================="
echo "1) Install"
echo "2) Uninstall"
read -p "Pilih: " P

if [[ "$P" == "1" ]]; then
    read -p "Masukkan ID Owner Utama: " OWNER

    echo "→ Membuat middleware..."
    cat > "$MW" <<EOF
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

        if (!\$user) return abort(403);

        if (\$request->is('admin/*') || \$request->is('api/application/*')) {
            if (\$user->id != \$owner) {
                return abort(403, 'Akses ditolak (AntiRusuh V10)');
            }
        }

        return \$next(\$request);
    }
}
EOF

    echo "→ Menambahkan ENV..."
    sed -i "/ANTIRUSUH_OWNER/d" "$ENV"
    echo "ANTIRUSUH_OWNER=$OWNER" >> "$ENV"

    echo "→ Inject kernel..."
    if ! grep -q "AntiRusuh" "$KERNEL"; then
        sed -i "/protected \$middlewareAliases = \[/a \ \ \ \ 'antirusuh' => Pterodactyl\\\Http\\\Middleware\\\AntiRusuh::class," "$KERNEL"
    fi

    echo "→ Tambah ke group web..."
    sed -i "/web' => \[/a \ \ \ \ \ \ \ \ 'antirusuh'," "$KERNEL"

    echo "→ Clear cache..."
    cd $PANEL
    php artisan optimize:clear

    echo "==============================="
    echo " ANTI RUSUH V10 AKTIF ✔"
    echo " Hanya ID $OWNER yang bisa buka admin"
    echo "==============================="
fi

if [[ "$P" == "2" ]]; then
    echo "→ Menghapus file middleware..."
    rm -f "$MW"

    echo "→ Menghapus dari kernel..."
    sed -i "/antirusuh/d" "$KERNEL"

    echo "→ Membersihkan ENV..."
    sed -i "/ANTIRUSUH_OWNER/d" "$ENV"

    cd $PANEL
    php artisan optimize:clear

    echo "==============================="
    echo " ANTI RUSUH V10 DIHAPUS ✔"
    echo "==============================="
fi
