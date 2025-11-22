#!/bin/bash

PANEL="/var/www/pterodactyl"
ENV_FILE="$PANEL/.env"
KERNEL_FILE="$PANEL/app/Http/Kernel.php"
ROUTE_ADMIN="$PANEL/routes/admin.php"

echo ""
echo "=============================="
echo "   Anti Rusuh Installer FIX"
echo "=============================="
echo ""

read -p "Masukkan email owner utama: " email

# Tambah / Replace OWNER
if grep -q "^OWNERS=" "$ENV_FILE"; then
    sed -i "s/^OWNERS=.*/OWNERS=$email/" "$ENV_FILE"
else
    echo "OWNERS=$email" >> "$ENV_FILE"
fi

# Buat Middleware
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

        if (preg_match("/server[s]?\/(\\d+)/", $path, $m)) {
            $server = Server::find($m[1]);
            if ($server && $server->owner_id !== $user->id) {
                return response()->view("errors.protect", [
                    "title" => "Akses Ditolak",
                    "message" => "WADUH BRE NGAPAIN, GA BISA WOK."
                ], 403);
            }
        }

        if (preg_match("/admin\\/users\\/(\\d+)/", $path) && $method === "DELETE") {
            return response()->view("errors.protect", [
                "title" => "Akses Ditolak",
                "message" => "APALAH NO DEL DEL YACH."
            ], 403);
        }

        if (preg_match("/admin\\/servers\\/(\\d+)/", $path) && $method === "DELETE") {
            return response()->view("errors.protect", [
                "title" => "Akses Ditolak",
                "message" => "APALAH NO DEL DEL YACH."
            ], 403);
        }

        return $next($request);
    }
}
EOF

# Buat blade protect
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

echo ""
echo "🔧 Patch Kernel.php..."

# Tambahkan middlewareAliases
if ! grep -q "owner.menu" "$KERNEL_FILE"; then
    sed -i "/protected \\$middlewareAliases = \\[/a\\        'owner.menu' => \\\\Pterodactyl\\\\Http\\\\Middleware\\\\AntiRusuh::class," "$KERNEL_FILE"
fi

echo ""
echo "🔧 Patch admin.php..."

# Patch admin.php
sed -i "s/Route::middleware(\['auth'\])/Route::middleware(['auth','owner.menu'])/" "$ROUTE_ADMIN"
sed -i "s/Route::middleware(\[\"auth\"\])/Route::middleware([\"auth\",\"owner.menu\"])/" "$ROUTE_ADMIN"

# Bersihkan cache Laravel
cd "$PANEL"
php artisan config:clear
php artisan cache:clear
php artisan route:clear
php artisan view:clear
php artisan config:cache
php artisan route:cache

echo ""
echo "✔️ Anti Rusuh berhasil dipasang wokk!"
echo ""
