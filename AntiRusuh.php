#!/bin/bash

PANEL="/var/www/pterodactyl"
ENV_FILE="$PANEL/.env"
KERNEL_FILE="$PANEL/app/Http/Kernel.php"
ROUTE_ADMIN="$PANEL/routes/admin.php"

watermark() {
    echo "         DANZZ TSUYOI"
}

menu() {
    clear
    echo "==========================="
    echo "   Anti Rusuh Installer FIX"
    watermark
    echo "==========================="
    echo
    echo "1. Install Anti Rusuh"
    echo "2. Tambahkan Owner"
    echo "3. Hapus Owner"
    echo "4. Ubah Owner"
    echo "5. Lihat Daftar Owner"
    echo "6. Remove Anti Rusuh"
    echo "7. Exit"
    echo
    read -p "Masukkan pilihan: " menu_choice

    case $menu_choice in
        1) install_antirusuh ;;
        2) tambah_owner ;;
        3) hapus_owner ;;
        4) ubah_owner ;;
        5) list_owner ;;
        6) remove_antirusuh ;;
        7) exit 0 ;;
        *) menu ;;
    esac
}

install_antirusuh() {
    read -p "Masukkan email owner utama: " email

    if grep -q "^OWNERS=" "$ENV_FILE"; then
        sed -i "s/^OWNERS=.*/OWNERS=$email/" "$ENV_FILE"
    else
        echo "OWNERS=$email" >> "$ENV_FILE"
    fi

    mkdir -p "$PANEL/app/Http/Middleware"

cat > "$PANEL/app/Http/Middleware/AntiRusuh.php" << 'EOF'
<?php

namespace Pterodactyl\Http\Middleware;

use Closure;
use Illuminate\Support\Facades\Auth;
use Pterodactyl\Models\Server;

class AntiRusuh
{
    protected function ownersList()
    {
        $owners = env('OWNERS', '');
        if ($owners === '') return [];
        return array_filter(array_map('trim', explode(',', $owners)));
    }

    public function handle($request, Closure $next)
    {
        $user = Auth::user();
        if (!$user) return $next($request);

        $owners = $this->ownersList();
        $isOwner = in_array($user->email, $owners);

        if ($isOwner) return $next($request);

        $path = $request->path();
        $method = strtoupper($request->method());

        $protectedMenus = [
            "admin/nodes",
            "admin/locations",
            "admin/nests",
            "admin/eggs",
            "admin/settings",
            "admin/allocations",
        ];

        foreach ($protectedMenus as $menu) {
            if (str_starts_with($path, $menu)) {
                return response()->view("errors.protect", [
                    "title" => "Akses Ditolak",
                    "message" => "NGAPAIN? NO RUSUH YA WOK."
                ], 403);
            }
        }

        if (preg_match("/server[s]?\/(\d+)/", $path, $m)) {
            $server = Server::find($m[1]);
            if ($server && $server->owner_id !== $user->id) {
                return response()->view("errors.protect", [
                    "title" => "Akses Ditolak",
                    "message" => "WADUH BRE NGAPAIN, GA BISA WOK."
                ], 403);
            }
        }

        if (preg_match("/admin\/users\/(\d+)/", $path) && $method === "DELETE") {
            return response()->view("errors.protect", [
                "title" => "Akses Ditolak",
                "message" => "APALAH NO DEL DEL YACH."
            ], 403);
        }

        if (preg_match("/admin\/servers\/(\d+)/", $path) && $method === "DELETE") {
            return response()->view("errors.protect", [
                "title" => "Akses Ditolak",
                "message" => "APALAH NO DEL DEL YACH."
            ], 403);
        }

        return $next($request);
    }
}
EOF

    mkdir -p "$PANEL/resources/views/errors"

cat > "$PANEL/resources/views/errors/protect.blade.php" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>{{ $title }}</title>
    <style>
        body { background:#0b1220; color:#e6eef8; font-family:Arial; display:flex; justify-content:center; align-items:center; height:100vh; }
        .box { background:#0f1724; padding:30px; border-radius:12px; text-align:center; width:400px; }
        h1 { color:#ff7b72; }
        p { color:#9fb0c8; }
    </style>
</head>
<body>
    <div class="box">
        <h1>{{ $title }}</h1>
        <p>{{ $message }}</p>
        <small>Protected by DANZZ TSUYOI</small>
    </div>
</body>
</html>
EOF

echo "🔧 Mem-patch Kernel.php..."
if ! grep -q "owner.menu" "$KERNEL_FILE"; then
    sed -i '/protected \$routeMiddleware = \[/a\        '\''owner.menu'\'' => \Pterodactyl\\Http\\Middleware\\AntiRusuh::class,' "$KERNEL_FILE"
fi

echo "🔧 Mem-patch admin.php..."
if [ -f "$ROUTE_ADMIN" ]; then
    sed -i 's/Route::middleware(\["auth"\])/Route::middleware(["auth","owner.menu"])/' "$ROUTE_ADMIN"
fi

cd "$PANEL"
php artisan config:clear
php artisan config:cache
php artisan route:clear
php artisan route:cache

echo "✔️ Anti Rusuh berhasil dipasang!"
sleep 1
menu
}

list_owner() {
    clear
    echo "Daftar Owner:"
    IFS=',' read -ra owners <<< "$(grep '^OWNERS=' "$ENV_FILE" | cut -d '=' -f2)"
    idx=1
    for mail in "${owners[@]}"; do
        echo "$idx. $mail"
        idx=$((idx+1))
    done
    echo
    read -p "Enter untuk kembali..." x
    menu
}

tambah_owner() {
    read -p "Masukkan email owner baru: " email
    old=$(grep '^OWNERS=' "$ENV_FILE" | cut -d '=' -f2)
    sed -i "s/^OWNERS=.*/OWNERS=$old,$email/" "$ENV_FILE"
    echo "Owner ditambahkan"
    sleep 1
    menu
}

hapus_owner() {
    IFS=',' read -ra owners <<< "$(grep '^OWNERS=' "$ENV_FILE" | cut -d '=' -f2)"

    echo "Pilih owner yang dihapus:"
    idx=1
    for o in "${owners[@]}"; do
        echo "$idx. $o"
        idx=$((idx+1))
    done
    read -p "Nomor: " pick

    removed="${owners[$pick-1]}"
    new_list=""

    for o in "${owners[@]}"; do
        if [ "$o" != "$removed" ]; then
            if [ -z "$new_list" ]; then new_list="$o"
            else new_list="$new_list,$o"
            fi
        fi
    done

    sed -i "s/^OWNERS=.*/OWNERS=$new_list/" "$ENV_FILE"

    echo "Owner dihapus"
    sleep 1
    menu
}

ubah_owner() {
    IFS=',' read -ra owners <<< "$(grep '^OWNERS=' "$ENV_FILE" | cut -d '=' -f2)"

    echo "Pilih owner yang mau diubah:"
    idx=1
    for o in "${owners[@]}"; do
        echo "$idx. $o"
        idx=$((idx+1))
    done
    read -p "Nomor: " pick
    read -p "Email baru: " new_email

    owners[$pick-1]=$new_email
    new_list=""
    for o in "${owners[@]}"; do
        if [ -z "$new_list" ]; then new_list="$o"
        else new_list="$new_list,$o"
        fi
    done

    sed -i "s/^OWNERS=.*/OWNERS=$new_list/" "$ENV_FILE"
    echo "Owner diubah"
    sleep 1
    menu
}

remove_antirusuh() {
    echo "Menghapus Anti Rusuh..."

    rm -f "$PANEL/app/Http/Middleware/AntiRusuh.php"
    rm -f "$PANEL/resources/views/errors/protect.blade.php"

    sed -i '/owner.menu/d' "$KERNEL_FILE"
    sed -i 's/Route::middleware(\["auth","owner.menu"\])/Route::middleware(["auth"])/' "$ROUTE_ADMIN"
    sed -i '/OWNERS=/d' "$ENV_FILE"

    cd "$PANEL"
    php artisan config:clear
    php artisan config:cache
    php artisan route:clear
    php artisan route:cache

    echo "✔️ Anti Rusuh berhasil dihapus!"
    sleep 1
    menu
}

menu
