#!/usr/bin/env bash
set -euo pipefail

PT="/var/www/pterodactyl"
M="$PT/app/Http/Middleware"
K="$PT/app/Http/Kernel.php"
R="$PT/routes"
B="$PT/.antirusuh_backup_$(date +%s)"

backup(){ [ -f "$1" ] && mkdir -p "$(dirname "$B/$1")" && cp -a "$1" "$B/$1"; }

install_wla(){
f="$M/WhitelistAdmin.php"
backup "$f"
cat > "$f" <<'EOF'
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
chmod 644 "$f"
}

install_cl(){
f="$M/ClientLock.php"
backup "$f"
cat > "$f" <<'EOF'
<?php
namespace App\Http\Middleware;
use Closure;
class ClientLock{
    public function handle($r, Closure $n){
        $u=$r->user();
        $s=$r->route('server');
        if(!$u) abort(403,'Unauthorized');
        if($s && $u->id!==$s->owner_id) abort(403,'Access denied');
        return $n($r);
    }
}
EOF
chmod 644 "$f"
}

kernel_reg(){
backup "$K"
grep -q "WhitelistAdmin::class" "$K" || sed -i "s/middlewareAliases = \[/middlewareAliases = \[\n        'whitelistadmin' => \\\\App\\\\Http\\\\Middleware\\\\WhitelistAdmin::class,/g" "$K"
grep -q "ClientLock::class" "$K"    || sed -i "s/middlewareAliases = \[/middlewareAliases = \[\n        'clientlock' => \\\\App\\\\Http\\\\Middleware\\\\ClientLock::class,/g" "$K"
}

inject_cl(){
files=$(grep -RIl "prefix' => '/servers" "$R" || true)
[ -z "$files" ] && return 0
for f in $files; do
    backup "$f"
    grep -q "clientlock" "$f" && continue
    sed -i "s/'middleware' => \[/& 'clientlock',/g" "$f" || true
done
}

clear_cache(){
cd "$PT"
php artisan route:clear || true
php artisan cache:clear || true
php artisan config:clear || true
php artisan view:clear || true
}

install_all(){
mkdir -p "$M"
install_wla
install_cl
kernel_reg
inject_cl
clear_cache
echo "$B"
}

uninstall_all(){
rm -f "$M/ClientLock.php" "$M/WhitelistAdmin.php"
backup "$K"
sed -i "/clientlock/d" "$K"
sed -i "/whitelistadmin/d" "$K"
clear_cache
}

repair(){
kernel_reg
inject_cl
clear_cache
}

menu(){
echo "1) Install"
echo "2) Uninstall"
echo "3) Repair"
echo "4) Exit"
read -r x
case "$x" in
1) install_all ;;
2) uninstall_all ;;
3) repair ;;
*) exit 0 ;;
esac
}

[ "$(id -u)" != "0" ] && echo "run as root" && exit 1
menu
