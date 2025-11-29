#!/usr/bin/env bash
set -euo pipefail

PT_PATH="${PT_PATH:-/var/www/pterodactyl}"
BACKUP_DIR="${PT_PATH}/.antirusuh_backups_$(date +%s)"
KERNEL="${PT_PATH}/app/Http/Kernel.php"
ROUTES_DIR="${PT_PATH}/routes"
MD_DIR="${PT_PATH}/app/Http/Middleware"

backup_file(){ [ -f "$1" ] && mkdir -p "$(dirname "$BACKUP_DIR/$1")" && cp -a "$1" "$BACKUP_DIR/$1"; }

ensure(){
    [ -d "$PT_PATH" ] || { echo "PT_PATH not found: $PT_PATH"; exit 1; }
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$MD_DIR"
}

create_whitelist(){
    f="$MD_DIR/WhitelistAdmin.php"
    backup_file "$f"
    cat > "$f" <<'PHP'
<?php
namespace Pterodactyl\Http\Middleware;
use Closure;
use Illuminate\Http\Request;
class WhitelistAdmin{
    public function handle(Request $request, Closure $next){
        $user = $request->user();
        if(!$user) abort(403,'Access denied.');
        if(!empty($user->root_admin) && $user->root_admin) return $next($request);
        abort(403,'Ngapain njir');
    }
}
PHP
    chmod 0644 "$f"
}

create_clientlock(){
    f="$MD_DIR/ClientLock.php"
    backup_file "$f"
    cat > "$f" <<'PHP'
<?php
namespace Pterodactyl\Http\Middleware;
use Closure;
use Illuminate\Http\Request;
class ClientLock{
    public function handle(Request $request, Closure $next){
        $user = $request->user();
        $server = $request->route('server');
        if(!$user) abort(403,'Unauthorized.');
        if($server && isset($server->owner_id) && $user->id !== $server->owner_id) abort(403,'Access denied.');
        return $next($request);
    }
}
PHP
    chmod 0644 "$f"
}

register_kernel(){
    [ -f "$KERNEL" ] || { echo "Kernel not found: $KERNEL"; return 1; }
    backup_file "$KERNEL"
    if ! grep -q "WhitelistAdmin::class" "$KERNEL"; then
        sed -i "/protected \$middlewareAliases = \[/a\        'whitelistadmin' => \\\\Pterodactyl\\\\Http\\\\Middleware\\\\WhitelistAdmin::class," "$KERNEL"
    fi
    if ! grep -q "ClientLock::class" "$KERNEL"; then
        sed -i "/protected \$middlewareAliases = \[/a\        'clientlock' => \\\\Pterodactyl\\\\Http\\\\Middleware\\\\ClientLock::class," "$KERNEL"
    fi
}

inject_clientlock(){
    files=$(grep -RIl "prefix' => '\/servers" "$ROUTES_DIR" || true)
    if [ -z "$files" ]; then
        echo "No routes file with prefix '/servers' found; skipping route injection."
        return 0
    fi
    for f in $files; do
        backup_file "$f"
        if grep -q "'clientlock'" "$f"; then
            echo "clientlock already present in $f"
            continue
        fi
        if grep -q "'middleware' => *\[" "$f"; then
            lineno=$(grep -n "'middleware' => *\[" "$f" | head -n1 | cut -d: -f1)
            if [ -n "$lineno" ]; then
                sed -i "${lineno}a\\        'clientlock'," "$f"
                echo "Inserted clientlock into existing middleware array in $f"
            fi
        else
            lineno=$(grep -n "prefix' => '\/servers" "$f" | head -n1 | cut -d: -f1 || true)
            if [ -n "$lineno" ]; then
                sed -n "1,${lineno}p" "$f" > "$f.tmp"
                printf "    'middleware' => [\n        'clientlock',\n    ],\n" >> "$f.tmp"
                sed -n "$((lineno+1)),\$p" "$f" >> "$f.tmp"
                mv "$f.tmp" "$f"
                echo "Inserted clientlock middleware block into $f"
            else
                echo "No prefix line matched in $f; skipped"
            fi
        fi
        perl -0777 -pe "s/('clientlock'\s*,\s*){2,}/'clientlock',/s" -i "$f" || true
    done
}

clear_cache(){
    if [ -d "$PT_PATH" ] && command -v php >/dev/null 2>&1; then
        cd "$PT_PATH"
        php artisan route:clear || true
        php artisan cache:clear || true
        php artisan config:clear || true
        php artisan view:clear || true
    fi
}

repair_perm(){
    if id -u www-data >/dev/null 2>&1; then
        chown -R www-data:www-data "$PT_PATH" || true
    fi
}

install_all(){
    ensure
    create_whitelist
    create_clientlock
    register_kernel
    inject_clientlock
    clear_cache
    repair_perm
    echo "$BACKUP_DIR"
}

uninstall_all(){
    rm -f "$MD_DIR/ClientLock.php" "$MD_DIR/WhitelistAdmin.php" || true
    if [ -f "$KERNEL" ]; then
        backup_file "$KERNEL"
        sed -i "/clientlock/d" "$KERNEL" || true
        sed -i "/whitelistadmin/d" "$KERNEL" || true
    fi
    clear_cache
}

menu(){
    echo "1) Install d"
    echo "2) Uninstall"
    echo "3) Repair"
    echo "4) Exit"
    read -r c
    case "$c" in
        1) install_all ;;
        2) uninstall_all ;;
        3) register_kernel; inject_clientlock; clear_cache ;;
        *) exit 0 ;;
    esac
}

[ "$(id -u)" -ne 0 ] && echo "run as root" && exit 1
ensure
menu
