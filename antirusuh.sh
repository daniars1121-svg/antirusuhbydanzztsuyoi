#!/bin/bash
set -e
clear

PANEL_PATH="/var/www/pterodactyl"
CONFIG_FILE="$PANEL_PATH/config/antirusuh.php"
BLADE_FILE="$PANEL_PATH/resources/views/layouts/app.blade.php"

if [ "$EUID" -ne 0 ]; then echo "Harus sebagai root"; exit 1; fi
if [ ! -d "$PANEL_PATH" ]; then echo "Panel tidak ditemukan"; exit 1; fi

menu() {
clear
echo "1) Install AntiRusuh"
echo "2) Hapus AntiRusuh"
echo "3) Tambah Owner"
echo "4) Update AntiRusuh"
echo "0) Keluar"
read -p "Pilih menu: " opt
case $opt in
    1) install ;;
    2) uninstall ;;
    3) addowner ;;
    4) update ;;
    0) exit ;;
    *) menu ;;
esac
}

install() {

OWNER=$(logname 2>/dev/null || whoami)

mkdir -p $PANEL_PATH/config
mkdir -p $PANEL_PATH/app/Http/Middleware
mkdir -p $PANEL_PATH/app/Console/Commands
mkdir -p $PANEL_PATH/resources/js

# CONFIG
cat > $PANEL_PATH/config/antirusuh.php <<EOF
<?php

return [
    'owners' => [
        '$OWNER'
    ],
    'safe_mode' => true,
];
EOF

# MIDDLEWARE
cat > $PANEL_PATH/app/Http/Middleware/AntiRusuh.php <<'EOF'
<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;

class AntiRusuh
{
    public function handle(Request $request, Closure $next)
    {
        $user = Auth::user();
        if (!$user) return $next($request);

        $owners = config('antirusuh.owners', []);
        $isOwner = in_array($user->username ?? $user->email, $owners, true);
        $uri = $request->path();

        $block = [
            'admin/nodes',
            'admin/locations',
            'admin/servers/*/build',
            'admin/servers/*/network',
            'nodes/*/settings',
            'nodes/*/allocations'
        ];

        foreach ($block as $p) {
            $regex = '#^' . str_replace('\*','.*',preg_quote($p,'#')) . '$#';
            if (preg_match($regex,$uri)) {
                if (!$isOwner) return redirect('/')->with('error','Aksi diblokir AntiRusuh.');
            }
        }

        if (preg_match('#^server/([a-zA-Z0-9-]+)#',$uri,$m)) {
            $uuid=$m[1];
            $server=\App\Models\Server::where('uuid',$uuid)
                     ->orWhere('uuidShort',$uuid)->first();
            if ($server && $server->owner_id !== $user->id && !$isOwner)
                return redirect('/')->with('error','Tidak boleh akses server orang.');
        }

        return $next($request);
    }
}
EOF

# CLEAN COMMAND
cat > $PANEL_PATH/app/Console/Commands/AntiRusuhClean.php <<'EOF'
<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use App\Models\User;
use App\Models\Server;

class AntiRusuhClean extends Command
{
    protected $signature = 'antirusuh:clean {--force}';
    protected $description = 'Hapus semua user/server non-owner';

    public function handle()
    {
        if (config('antirusuh.safe_mode')) {
            $this->error("SAFE MODE aktif.");
            return;
        }

        $owners = config('antirusuh.owners');
        $users = User::whereNotIn('username',$owners)
                     ->whereNotIn('email',$owners)
                     ->get();

        $this->info("User non-owner: ".$users->count());

        if (!$this->option('force')) {
            $this->warn("Gunakan --force untuk melanjutkan.");
            return;
        }

        foreach ($users as $u) {
            Server::where('owner_id',$u->id)->delete();
            $u->delete();
        }

        $this->info("Selesai.");
    }
}
EOF

# JS FILE
cat > $PANEL_PATH/resources/js/antirusuh.js <<'EOF'
document.addEventListener("DOMContentLoaded",()=>{

    const owner=document
        .querySelector('meta[name="antirusuh-owner"]')
        ?.content==="1";

    if(owner) return;

    const block=[
        ".btn-location",".btn-network",".btn-build",
        ".btn-allocations",".danger-zone",".btn-admin"
    ];

    block.forEach(sel=>{
        document.querySelectorAll(sel).forEach(btn=>{
            btn.style.opacity="0.5";
            btn.style.pointerEvents="none";
            btn.onclick=()=>alert("Aksi diblokir AntiRusuh!");
        });
    });
});
EOF

# REGISTER MIDDLEWARE
if ! grep -q "antirusuh" $PANEL_PATH/app/Http/Kernel.php; then
    sed -i "/protected \$routeMiddleware = \[/a\\        'antirusuh' => \App\Http\Middleware\AntiRusuh::class," $PANEL_PATH/app/Http/Kernel.php
fi

# BLADE META INJECT
META='<meta name="antirusuh-owner" content="{{ in_array(auth()->user()->username ?? auth()->user()->email, config('\''antirusuh.owners'\'')) ? '\''1'\'' : '\''0'\'' }}">'
if ! grep -q "antirusuh-owner" "$BLADE_FILE"; then
    sed -i "/<\/head>/i $META" "$BLADE_FILE"
fi

cd $PANEL_PATH
php artisan cache:clear
php artisan config:clear
php artisan route:clear
php artisan config:cache

systemctl restart php8.1-fpm 2>/dev/null || true
systemctl restart php8.2-fpm 2>/dev/null || true

echo "AntiRusuh terinstall"
sleep 2
menu
}

uninstall() {

rm -f $PANEL_PATH/config/antirusuh.php
rm -f $PANEL_PATH/app/Http/Middleware/AntiRusuh.php
rm -f $PANEL_PATH/app/Console/Commands/AntiRusuhClean.php
rm -f $PANEL_PATH/resources/js/antirusuh.js

sed -i "/antirusuh/d" $PANEL_PATH/app/Http/Kernel.php
sed -i "/antirusuh-owner/d" $BLADE_FILE

cd $PANEL_PATH
php artisan cache:clear
php artisan config:clear
php artisan route:clear
php artisan config:cache

echo "AntiRusuh dihapus"
sleep 2
menu
}

addowner() {

if [ ! -f "$CONFIG_FILE" ]; then echo "Belum terinstall"; sleep 2; menu; fi
read -p "Owner baru: " NEW
sed -i "/'owners' => \[/a\        '$NEW'," $CONFIG_FILE
echo "Owner ditambahkan"
sleep 2
menu
}

update() {
cd /root/antirusuh 2>/dev/null || git clone https://github.com/daniars1121-svg/antirusuhbydanzztsuyoi /root/antirusuh
cd /root/antirusuh
git pull
bash antirusuh.sh
}

menu
