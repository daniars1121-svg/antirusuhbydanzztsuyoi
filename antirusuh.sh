#!/bin/bash
set -e

PANEL_PATH="/var/www/pterodactyl"
CONFIG_FILE="$PANEL_PATH/config/antirusuh.php"
KERNEL_FILE="$PANEL_PATH/app/Http/Kernel.php"
MIDDLEWARE_FILE="$PANEL_PATH/app/Http/Middleware/AntiRusuh.php"
BLADE_FILE="$PANEL_PATH/resources/views/layouts/admin.blade.php"

# 🔥 Load DB credentials
DB_HOST=$(grep -E '^DB_HOST=' $PANEL_PATH/.env | cut -d '=' -f2)
DB_DATABASE=$(grep -E '^DB_DATABASE=' $PANEL_PATH/.env | cut -d '=' -f2)
DB_USERNAME=$(grep -E '^DB_USERNAME=' $PANEL_PATH/.env | cut -d '=' -f2)
DB_PASSWORD=$(grep -E '^DB_PASSWORD=' $PANEL_PATH/.env | cut -d '=' -f2)

if [ "$EUID" -ne 0 ]; then
    echo "Harus sebagai root!"
    exit 1
fi

menu() {
    clear
    echo "1) Install AntiRusuh by tsuyoi danz"
    echo "2) Uninstall AntiRusuh"
    echo "3) Kelola Owner"
    echo "4) Update AntiRusuh (Auto GitHub)"
    echo "0) Keluar"
    echo -n "Pilih: "
    read x

    case $x in
        1) install ;;
        2) uninstall ;;
        3) manage_owner ;;
        4) update ;;
        0) exit ;;
        *) menu ;;
    esac
}

#############################################
# 🔥 INSTALL SYSTEM
#############################################
install() {

    echo "→ Menginstall AntiRusuh..."

    mkdir -p $PANEL_PATH/config
    mkdir -p $PANEL_PATH/app/Http/Middleware

    # CONFIG FILE
    cat > $CONFIG_FILE <<EOF
<?php
return [
    'owners' => [
        'root'
    ],
    'safe_mode' => true,
];
EOF

    # MIDDLEWARE
    cat > $MIDDLEWARE_FILE <<'EOF'
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
            "admin/nodes",
            "admin/locations",
            "admin/servers/*/build",
            "admin/servers/*/network",
        ];

        foreach ($block as $p) {
            $regex = "#^" . str_replace('\*','.*',preg_quote($p,'#')) . "$#";
            if (preg_match($regex,$uri)) {
                if (!$isOwner) return redirect("/")->with("error","Aksi diblokir AntiRusuh.");
            }
        }

        return $next($request);
    }
}
EOF

    # Tambahkan middleware ke Kernel
    if ! grep -q "AntiRusuh" "$KERNEL_FILE"; then
        sed -i "/protected \$middlewareAliases = \[/a\        'antirusuh' => App\\\Http\\\Middleware\\\AntiRusuh::class," "$KERNEL_FILE"
    fi

    # Tambahkan META ke blade admin
    META='<meta name="antirusuh-owner" content="{{ in_array(auth()->user()->username ?? auth()->user()->email, config('\''antirusuh.owners'\'')) ? '\''1'\'' : '\''0'\'' }}">'
    if ! grep -q "antirusuh-owner" "$BLADE_FILE"; then
        sed -i "/<\/head>/i $META" "$BLADE_FILE"
    fi

    cd $PANEL_PATH
    php artisan config:clear
    php artisan cache:clear
    php artisan route:clear
    php artisan config:cache

    systemctl restart php8.2-fpm 2>/dev/null || true
    systemctl restart php8.3-fpm 2>/dev/null || true

    echo "✔ AntiRusuh berhasil diinstall!"
    sleep 2
    menu
}

#############################################
# 🔥 UNINSTALL SYSTEM
#############################################
uninstall() {

    echo "→ Menghapus AntiRusuh..."

    rm -f $CONFIG_FILE
    rm -f $MIDDLEWARE_FILE

    sed -i "/antirusuh/d" "$KERNEL_FILE"
    sed -i "/antirusuh-owner/d" "$BLADE_FILE"

    cd $PANEL_PATH
    php artisan config:clear
    php artisan cache:clear
    php artisan route:clear
    php artisan config:cache

    echo "✔ AntiRusuh berhasil dihapus!"
    sleep 2
    menu
}

#############################################
# 🔥 K E L O L A   O W N E R
#############################################
manage_owner() {

    echo ""
    echo "Daftar User Panel:"
    echo ""

    USERS=$(mysql -u "$DB_USERNAME" -p"$DB_PASSWORD" -h "$DB_HOST" -D "$DB_DATABASE" \
        -se "SELECT id, username, email FROM users;")

    if [ -z "$USERS" ]; then
        echo "❌ Tidak ada user ditemukan!"
        sleep 2
        menu
        return
    fi

    IFS=$'\n' read -rd '' -a USER_LIST <<< "$USERS"

    idx=1
    for u in "${USER_LIST[@]}"; do
        uid=$(echo "$u" | awk '{print $1}')
        uname=$(echo "$u" | awk '{print $2}')
        uemail=$(echo "$u" | awk '{print $3}')
        echo "$idx) $uname ($uemail)"
        idx=$((idx+1))
    done

    echo ""
    read -p "Pilih nomor user: " pilih
    selected="${USER_LIST[$((pilih-1))]}"

    if [ -z "$selected" ]; then
        echo "❌ Pilihan invalid!"
        sleep 2
        menu
        return
    fi

    uname=$(echo "$selected" | awk '{print $2}')

    echo "→ Menambahkan $uname sebagai OWNER..."
    sed -i "/'owners' => \[/a\        '$uname'," "$CONFIG_FILE"

    php artisan config:clear

    echo "✔ Owner berhasil ditambahkan!"
    sleep 2
    menu
}

#############################################
# 🔥 UPDATE DARI GITHUB
#############################################
update() {

    echo "→ Mengunduh update dari GitHub..."

    cd /root
    if [ ! -d "/root/antirusuh" ]; then
        git clone https://github.com/daniars1121-svg/antirusuhbydanzztsuyoi /root/antirusuh
    fi

    cd /root/antirusuh
    git pull

    cp -f antirusuh.sh /usr/local/bin/antirusuh
    chmod +x /usr/local/bin/antirusuh

    echo "✔ AntiRusuh berhasil diperbarui!"
    sleep 2
    menu
}

menu
