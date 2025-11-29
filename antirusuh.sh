#!/usr/bin/env bash

PT="/var/www/pterodactyl"
M="$PT/app/Http/Middleware"
K="$PT/app/Http/Kernel.php"
R="$PT/routes"

install(){
    echo "[INSTALL] Membuat middleware..."
    mkdir -p "$M"

    cat > "$M/WhitelistAdmin.php" <<'EOF'
<?php
namespace App\Http\Middleware;
use Closure;
class WhitelistAdmin{
    public function handle($r, Closure $n){
        $u=$r->user();
        if(!$u) abort(403,'Access denied');
        if(!empty($u->root_admin)&&$u->root_admin) return $n($r);
        abort(403,'Ngapain njir');
    }
}
EOF

    cat > "$M/ClientLock.php" <<'EOF'
<?php
namespace App\Http\Middleware;
use Closure;
class ClientLock{
    public function handle($r, Closure $n){
        $u=$r->user();
        $s=$r->route('server');
        if(!$u) abort(403,'Unauthorized');
        if($s && $u->id !== $s->owner_id) abort(403,'Access denied');
        return $n($r);
    }
}
EOF

    echo "[INSTALL] Register kernel..."
    sed -i "/middlewareAliases = \[/a\        'whitelistadmin' => \\\\App\\\\Http\\\\Middleware\\\\WhitelistAdmin::class," "$K"
    sed -i "/middlewareAliases = \[/a\        'clientlock' => \\\\App\\\\Http\\\\Middleware\\\\ClientLock::class," "$K"

    echo "[INSTALL] Patch routes..."
    grep -RIl "prefix' => '/servers" "$R" | while read f; do
        sed -i "s/'middleware' => \[/& 'clientlock',/" "$f"
    done

    echo "[INSTALL] Clearing cache..."
    cd "$PT"
    php artisan route:clear
    php artisan cache:clear
    php artisan config:clear

    echo "[DONE] AntiRusuh terpasang!"
}

uninstall(){
    echo "[UNINSTALL] Menghapus middleware..."
    rm -f "$M/WhitelistAdmin.php"
    rm -f "$M/ClientLock.php"

    echo "[UNINSTALL] Membersihkan kernel..."
    sed -i "/clientlock/d" "$K"
    sed -i "/whitelistadmin/d" "$K"

    echo "[UNINSTALL] Done."
}

repair(){
    echo "[REPAIR] Repair kernel dan route..."
    install
}

menu(){
echo "1) Install my"
echo "2) Uninstall"
echo "3) Repair"
echo "4) Exit"
read -p "Choice: " c

case $c in
1) install ;;
2) uninstall ;;
3) repair ;;
*) exit ;;
esac
}

menu
