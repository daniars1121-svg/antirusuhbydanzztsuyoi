#!/usr/bin/env bash
set -euo pipefail

PT_PATH="/var/www/pterodactyl"
BACKUP_DIR="${PT_PATH}/.antirusuh_backups_$(date +%s)"
KERNEL="${PT_PATH}/app/Http/Kernel.php"
ROUTES_DIR="${PT_PATH}/routes"
MD="${PT_PATH}/app/Http/Middleware"

info(){ echo "$1"; }

backup_file(){
    [ -f "$1" ] && mkdir -p "$(dirname "$BACKUP_DIR/$1")" && cp -a "$1" "$BACKUP_DIR/$1"
}

ensure(){
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$MD"
}

create_wla(){
    f="$MD/WhitelistAdmin.php"
    backup_file "$f"
    cat > "$f" <<'PHP'
<?php
namespace Pterodactyl\Http\Middleware;
use Closure;
use Illuminate\Http\Request;
class WhitelistAdmin{
    public function handle(Request $r, Closure $n){
        $u=$r->user();
        if(!$u) abort(403,'Access denied.');
        if(!empty($u->root_admin)&&$u->root_admin) return $n($r);
        abort(403,'Ngapain njir');
    }
}
PHP
}

create_cl(){
    f="$MD/ClientLock.php"
    backup_file "$f"
    cat > "$f" <<'PHP'
<?php
namespace Pterodactyl\Http\Middleware;
use Closure;
use Illuminate\Http\Request;
class ClientLock{
    public function handle(Request $r, Closure $n){
        $u=$r->user();
        $s=$r->route('server');
        if(!$u) abort(403,'Unauthorized.');
        if($s && isset($s->owner_id) && $u->id!==$s->owner_id) abort(403,'Access denied.');
        return $n($r);
    }
}
PHP
}

reg_kernel(){
    backup_file "$KERNEL"
    grep -q "WhitelistAdmin::class" "$KERNEL" || sed -i "/middlewareAliases = \[/a\        'whitelistadmin' => \\\\Pterodactyl\\\\Http\\\\Middleware\\\\WhitelistAdmin::class," "$KERNEL"
    grep -q "ClientLock::class" "$KERNEL" || sed -i "/middlewareAliases = \[/a\        'clientlock' => \\\\Pterodactyl\\\\Http\\\\Middleware\\\\ClientLock::class," "$KERNEL"
}

inject_routes(){
    files=$(grep -RIl "prefix' => '\/servers" "$ROUTES_DIR" || true)
    [ -z "$files" ] && return 0
    for f in $files; do
        backup_file "$f"
        if grep -q "'middleware' => *\[" "$f"; then
            grep -q "'clientlock'" "$f" || perl -0777 -pe "s/('middleware' =>\s*\[)/\1\n        'clientlock',/s" -i "$f"
        else
            if ! grep -q "'clientlock'" "$f"; then
                awk '{
                    print
                    if(!x && $0 ~ /'\''prefix'\''\s*=>\s*'\''\/servers/){
                        print "    '\''middleware'\'' => ["
                        print "        '\''clientlock'','"
                        print "    ],"
                        x=1
                    }
                }' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
            fi
        fi
        perl -0777 -pe "s/(('clientlock'\s*,\s*){2,})/'clientlock',/s" -i "$f"
    done
}

clear_cache(){
    cd "$PT_PATH"
    php artisan route:clear || true
    php artisan cache:clear || true
    php artisan config:clear || true
    php artisan view:clear || true
}

repair_perm(){
    id -u www-data >/dev/null 2>&1 && chown -R www-data:www-data "$PT_PATH"
}

install(){
    ensure
    create_wla
    create_cl
    reg_kernel
    inject_routes
    clear_cache
    repair_perm
    echo "$BACKUP_DIR"
}

uninstall(){
    rm -f "$MD/ClientLock.php" "$MD/WhitelistAdmin.php"
    backup_file "$KERNEL"
    sed -i "/clientlock/d" "$KERNEL" || true
    sed -i "/whitelistadmin/d" "$KERNEL" || true
    cd "$PT_PATH"
    php artisan route:clear || true
    php artisan cache:clear || true
    php artisan config:clear || true
}

menu(){
    echo "1) Install"
    echo "2) Uninstall"
    echo "3) Repair"
    echo "4) Exit"
    read -r c
    case "$c" in
        1) install ;;
        2) uninstall ;;
        3) reg_kernel; inject_routes; clear_cache ;;
        *) exit 0 ;;
    esac
}

[ "$(id -u)" -ne 0 ] && echo "run as root" && exit 1
ensure
menu
