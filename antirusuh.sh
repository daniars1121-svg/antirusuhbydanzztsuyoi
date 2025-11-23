#!/bin/bash
set -e
clear

PANEL_PATH="/var/www/pterodactyl"
CONFIG_FILE="$PANEL_PATH/config/antirusuh.php"
MIDDLEWARE_FILE="$PANEL_PATH/app/Http/Middleware/AntiRusuh.php"
COMMAND_FILE="$PANEL_PATH/app/Console/Commands/AntiRusuhClean.php"
JS_FILE="$PANEL_PATH/public/js/antirusuh.js"
BLADE_FILE="$PANEL_PATH/resources/views/layouts/admin.blade.php"
REPO_URL="https://github.com/daniars1121-svg/antirusuhbydanzztsuyoi"

if [ "$EUID" -ne 0 ]; then echo "Harus root"; exit 1; fi
if [ ! -d "$PANEL_PATH" ]; then echo "Panel tidak ditemukan di $PANEL_PATH"; exit 1; fi

# helper untuk membaca .env
get_env() {
    local key="$1"
    grep -E "^${key}=" "$PANEL_PATH/.env" 2>/dev/null | cut -d= -f2- | sed 's/^["'\'']\(.*\)["'\'']$/\1/'
}

menu() {
clear
echo "1) Install AntiRusuh by tsuyoi idanz"
echo "2) Uninstall AntiRusuh"
echo "3) Kelola Owner (list + add/remove)"
echo "4) Update AntiRusuh (Auto GitHub)"
echo "0) Keluar"
read -p "Pilih: " m

case $m in
1) install ;;
2) uninstall ;;
3) manage_owner ;;
4) update_remote ;;
0) exit ;;
*) menu ;;
esac
}

install() {
OWNER_USER=$(logname 2>/dev/null || whoami)

# buat folder & file kalau belum ada
mkdir -p "$PANEL_PATH/config" "$PANEL_PATH/app/Http/Middleware" "$PANEL_PATH/app/Console/Commands" "$PANEL_PATH/public/js"

cat > "$CONFIG_FILE" <<'EOF'
<?php
return [
    'owners' => [
        'root', // contoh, ubah lewat menu
    ],
    'safe_mode' => true,
];
EOF

# Middleware: gunakan namespace Pterodactyl\Http\Middleware agar cocok dengan Kernel
cat > "$MIDDLEWARE_FILE" <<'EOF'
<?php

namespace Pterodactyl\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;

class AntiRusuh
{
    public function handle(Request \$request, Closure \$next)
    {
        \$user = Auth::user();
        if (!\$user) return \$next(\$request);

        \$owners = config('antirusuh.owners', []);
        \$identifier = \$user->username ?? \$user->email;
        \$isOwner = in_array(\$identifier, \$owners, true);
        \$uri = ltrim(\$request->path(), '/');

        \$block = [
            "admin/nodes",
            "admin/locations",
            "admin/servers/*/build",
            "admin/servers/*/network",
            "nodes/*/settings",
            "nodes/*/allocations"
        ];

        foreach (\$block as \$p) {
            \$pattern = '#^' . str_replace('\*','.*',preg_quote(\$p,'#')) . '\$#';
            if (preg_match(\$pattern, \$uri)) {
                if (!\$isOwner) {
                    if (\$request->wantsJson() || \$request->is('api/*')) {
                        return response()->json(['error' => 'Aksi diblokir AntiRusuh.'], 403);
                    }
                    return redirect('/')->with('error','Aksi diblokir AntiRusuh.');
                }
            }
        }

        // akses server by uuid check
        if (preg_match('#^server/([a-zA-Z0-9-]+)#', \$uri, \$m)) {
            \$uuid = \$m[1];
            if (class_exists('\\Pterodactyl\\Models\\Server')) {
                try {
                    \$server = \\Pterodactyl\\Models\\Server::where('uuid', \$uuid)
                        ->orWhere('uuidShort', \$uuid)->first();
                    if (\$server && \$server->owner_id !== \$user->id && !\$isOwner) {
                        if (\$request->wantsJson() || \$request->is('api/*')) {
                            return response()->json(['error'=>'Tidak boleh akses server orang.'],403);
                        }
                        return redirect('/')->with('error','Tidak boleh akses server orang.');
                    }
                } catch (\Throwable \$e) {
                    // jangan crash app
                }
            }
        }

        return \$next(\$request);
    }
}
EOF

# Console command (namespace sesuai Pterodactyl)
cat > "$COMMAND_FILE" <<'EOF'
<?php

namespace Pterodactyl\Console\Commands;

use Illuminate\Console\Command;
use Pterodactyl\Models\User;
use Pterodactyl\Models\Server;

class AntiRusuhClean extends Command
{
    protected $signature = 'antirusuh:clean {--force}';
    protected $description = 'Hapus user/server non-owner';

    public function handle()
    {
        if (config('antirusuh.safe_mode')) {
            $this->error("SAFE MODE aktif - non destructive mode");
            return 1;
        }

        $owners = config('antirusuh.owners', []);
        $users = User::whereNotIn('username', $owners)
                    ->whereNotIn('email', $owners)
                    ->get();

        $this->info("User non-owner: ".$users->count());

        if (!$this->option('force')) {
            $this->warn("Gunakan --force untuk menghapus");
            return 0;
        }

        foreach ($users as $u) {
            Server::where('owner_id', $u->id)->delete();
            $u->delete();
        }

        $this->info("Selesai");
        return 0;
    }
}
EOF

# JS yang simple (letakkan di public/js agar bisa diakses)
cat > "$JS_FILE" <<'EOF'
document.addEventListener("DOMContentLoaded", function(){
    const isOwner = document.querySelector('meta[name="antirusuh-owner"]')?.content === "1";
    if (isOwner) return;
    const disabled = [
        ".btn-location",".btn-network",".btn-build",
        ".btn-allocations",".danger-zone",".btn-admin",".btn-delete"
    ];
    disabled.forEach(s=>{
        document.querySelectorAll(s).forEach(b=>{
            b.style.opacity = "0.5";
            b.style.pointerEvents = "none";
            b.addEventListener("click", function(e){
                e.preventDefault();
                alert("Aksi diblokir AntiRusuh!");
            });
        });
    });
});
EOF

# Daftar/inject ke Kernel.php: cari protected $middlewareAliases (nama di Pterodactyl: $middlewareAliases)
KERNEL="$PANEL_PATH/app/Http/Kernel.php"
if grep -q "protected \$middlewareAliases" "$KERNEL"; then
    # jika antirusuh belum ada, insert
    if ! grep -q "antirusuh" "$KERNEL"; then
        sed -i "/protected \$middlewareAliases = \[/,/\];/{
            /protected \$middlewareAliases = \[/a\        'antirusuh' => \Pterodactyl\\Http\\Middleware\\AntiRusuh::class,
        }" "$KERNEL"
        echo "[OK] Middleware alias ditambahkan ke Kernel.php"
    else
        echo "[OK] Middleware alias sudah ada di Kernel.php"
    fi
else
    echo "[WARN] Struktur Kernel.php tidak terduga - manual cek: $KERNEL"
fi

# Tambah meta + script ke layout admin.blade.php sebelum </head> dan sebelum </body> untuk script
META='<meta name="antirusuh-owner" content="{{ in_array(auth()->user()->username ?? auth()->user()->email, config('\''antirusuh.owners'\'')) ? '\''1'\'' : '\''0'\'' }}">'
SCRIPT='<script src="{{ asset('\''js/antirusuh.js'\'') }}"></script>'

if [ -f "$BLADE_FILE" ]; then
    if ! grep -q "antirusuh-owner" "$BLADE_FILE"; then
        sed -i "/<\/head>/i $META" "$BLADE_FILE"
        echo "[OK] Meta antirusuh ditambahkan ke $BLADE_FILE"
    fi
    if ! grep -q "js/antirusuh.js" "$BLADE_FILE"; then
        sed -i "/<\/body>/i $SCRIPT" "$BLADE_FILE" || echo "[WARN] Gagal sisip script ke blade (cek manual)"
        echo "[OK] Script antirusuh ditambahkan ke $BLADE_FILE"
    fi
else
    echo "[WARN] Blade file tidak ditemukan: $BLADE_FILE"
fi

# clear & cache
cd "$PANEL_PATH"
php artisan cache:clear || true
php artisan config:clear || true
php artisan route:clear || true
php artisan config:cache || true

# restart php-fpm jika ada
systemctl restart php8.1-fpm 2>/dev/null || true
systemctl restart php8.2-fpm 2>/dev/null || true
systemctl restart php8.3-fpm 2>/dev/null || true

echo "AntiRusuh terinstall."
echo "Catatan:"
echo "- Pastikan owner di $CONFIG_FILE berisi username=email yang benar."
echo "- Untuk test: login sebagai non-owner dan akses /admin/nodes (seharusnya redirect/forbidden)."
sleep 2
menu
}

uninstall() {
rm -f "$CONFIG_FILE" "$MIDDLEWARE_FILE" "$COMMAND_FILE" "$JS_FILE"

# hapus alias antirusuh dari Kernel.php
sed -i "/antirusuh/d" "$PANEL_PATH/app/Http/Kernel.php" || true

# hapus meta/script dari blade
if [ -f "$BLADE_FILE" ]; then
    sed -i "/antirusuh-owner/d" "$BLADE_FILE" || true
    sed -i "/js\/antirusuh.js/d" "$BLADE_FILE" || true
fi

cd "$PANEL_PATH"
php artisan cache:clear || true
php artisan config:clear || true
php artisan route:clear || true
php artisan config:cache || true

echo "AntiRusuh dihapus."
sleep 2
menu
}

manage_owner() {
# ambil DB creds
DB_HOST=$(get_env "DB_HOST")
DB_NAME=$(get_env "DB_DATABASE")
DB_USER=$(get_env "DB_USERNAME")
DB_PASS=$(get_env "DB_PASSWORD")

echo
echo "Daftar User Panel:"
# coba ambil user dari DB MySQL (kolom username, email)
if [ -z "$DB_USER" ] || [ -z "$DB_PASS" ]; then
    echo "[ERROR] DB creds kosong di .env"
else
    # gunakan mysql cli untuk list user (toleransi)
    mysql -h "$DB_HOST" -u "$DB_USER" -p"$DB_PASS" -D "$DB_NAME" -e "SELECT id, username, email FROM users LIMIT 100;" 2>/tmp/antirusuh_mysql.err \
    || { echo "[ERROR] gagal akses DB. cek /tmp/antirusuh_mysql.err"; sed -n '1,120p' /tmp/antirusuh_mysql.err; }
fi

echo
echo "1) Tambah owner dari daftar (masukkan username persis)"
echo "2) Hapus owner (masukkan username)"
echo "3) Tampilkan config saat ini"
echo "0) Kembali"
read -p "Pilih: " op
case $op in
1)
    read -p "Masukkan username yang mau jadi owner: " un
    if [ -z "$un" ]; then echo "Kosong"; sleep 1; manage_owner; fi
    # masukkan ke config file
    sed -i "/'owners' => \[/a\        '$un'," "$CONFIG_FILE"
    echo "Owner $un ditambahkan."
    php artisan config:clear || true
    php artisan config:cache || true
    sleep 1
    manage_owner
    ;;
2)
    read -p "Masukkan username yang mau dihapus dari owners: " un
    if [ -z "$un" ]; then manage_owner; fi
    # hapus baris owner dari config
    sed -i "/'$un'/d" "$CONFIG_FILE"
    echo "Owner $un dihapus."
    php artisan config:clear || true
    php artisan config:cache || true
    sleep 1
    manage_owner
    ;;
3)
    echo "Isi $CONFIG_FILE:"
    sed -n '1,200p' "$CONFIG_FILE"
    read -p "Tekan Enter..." dummy
    manage_owner
    ;;
0) menu ;;
*) manage_owner ;;
esac
}

update_remote() {
cd /root/antirusuh 2>/dev/null || git clone "$REPO_URL" /root/antirusuh
cd /root/antirusuh
git pull || true
# jalankan skrip installer terbaru jika ada
if [ -f ./antirusuh.sh ]; then
    bash ./antirusuh.sh
else
    echo "Tidak menemukan antirusuh.sh di repo."
fi
menu
}

# jalanin menu
menu
