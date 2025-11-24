#!/usr/bin/env bash
set -euo pipefail

PTERO="/var/www/pterodactyl"
BACKUP_DIR="$PTERO/antirusuh_backup_$(date +%s)"
ADMIN_MW="$PTERO/app/Http/Middleware/WhitelistAdmin.php"
CLIENT_MW="$PTERO/app/Http/Middleware/ClientLock.php"
KERNEL="$PTERO/app/Http/Kernel.php"
ADMIN_ROUTES="$PTERO/routes/admin.php"
API_CLIENT="$PTERO/routes/api-client.php"
API_APP="$PTERO/routes/api-application.php"
ERROR_VIEW_DIR="$PTERO/resources/views/errors"
ERROR_VIEW_FILE="$ERROR_VIEW_DIR/antirusuh.blade.php"
SERVERCTLDIR="$PTERO/app/Http/Controllers/Admin/Servers"
USERCTL="$PTERO/app/Http/Controllers/Admin/UserController.php"

ensure_root() {
    if [ "$(id -u)" -ne 0 ]; then exit 1; fi
}

backup_files() {
    mkdir -p "$BACKUP_DIR"
    cp -a "$KERNEL" "$BACKUP_DIR/" 2>/dev/null || true
    mkdir -p "$BACKUP_DIR/appMiddleware"
    cp -a "$PTERO/app/Http/Middleware" "$BACKUP_DIR/appMiddleware/" 2>/dev/null || true
    cp -a "$ADMIN_ROUTES" "$BACKUP_DIR/" 2>/dev/null || true
    cp -a "$API_CLIENT" "$BACKUP_DIR/" 2>/dev/null || true
    cp -a "$API_APP" "$BACKUP_DIR/" 2>/dev/null || true
    mkdir -p "$BACKUP_DIR/routes"
    cp -a "$PTERO/routes" "$BACKUP_DIR/routes/" 2>/dev/null || true
    cp -a "$PTERO/resources/views/errors" "$BACKUP_DIR/errors_backup" 2>/dev/null || true
}

install_middleware_files() {
    mkdir -p "$(dirname "$ADMIN_MW")"
    mkdir -p "$(dirname "$CLIENT_MW")"

cat > "$ADMIN_MW" <<'PHP'
<?php
namespace Pterodactyl\Http\Middleware;
use Closure; use Illuminate\Http\Request;
class WhitelistAdmin {
public function handle(Request $r, Closure $n) {
$a = property_exists($this,'allowed') ? $this->allowed : [];
$u = $r->user(); if(!$u || !in_array($u->id,$a)) {
if(view()->exists('errors.antirusuh')) return response()->view('errors.antirusuh',['message'=>'ngapain wok'],403);
if($r->wantsJson()) return response()->json(['error'=>'ngapain wok'],403);
abort(403);
} return $n($r);
}}
PHP

cat > "$CLIENT_MW" <<'PHP'
<?php
namespace App\Http\Middleware;
use Closure; use Illuminate\Http\Request;
class ClientLock {
public function handle(Request $r, Closure $n) {
$a = property_exists($this,'allowed') ? $this->allowed : [];
$u = $r->user(); if(!$u) {
if($r->wantsJson()) return response()->json(['error'=>'ngapain wok'],403);
abort(403);
}
if(in_array($u->id,$a)) return $n($r);
$s = $r->route('server');
if($s && isset($s->owner_id) && $s->owner_id != $u->id) {
if(view()->exists('errors.antirusuh')) return response()->view('errors.antirusuh',['message'=>'ngapain wok'],403);
if($r->wantsJson()) return response()->json(['error'=>'ngapain wok'],403);
abort(403);
}
return $n($r);
}}
PHP
}

inject_allowed_ids() {
    local ids="$1"
    if grep -q "protected \$allowed" "$ADMIN_MW"; then
        perl -0777 -pe "s/protected \\\$allowed\s*=\s*\[.*?\];/protected \\\$allowed = [$ids];/s" -i "$ADMIN_MW"
    else
        perl -0777 -pe "s/class WhitelistAdmin\s*\{\/?n?/class WhitelistAdmin {\n    protected \\\$allowed = [$ids];\n/s" -i "$ADMIN_MW"
    fi
    if grep -q "protected \$allowed" "$CLIENT_MW"; then
        perl -0777 -pe "s/protected \\\$allowed\s*=\s*\[.*?\];/protected \\\$allowed = [$ids];/s" -i "$CLIENT_MW"
    else
        perl -0777 -pe "s/class ClientLock\s*\{\/?n?/class ClientLock {\n    protected \\\$allowed = [$ids];\n/s" -i "$CLIENT_MW"
    fi
}

register_kernel_aliases() {
    if ! grep -q "whitelistadmin" "$KERNEL"; then
        perl -0777 -pe '
            if (m/protected\s+\$middlewareAliases\s*=\s*\[(.*?)\];/s) {
                $inner = $1;
                $add = "\n        \x27whitelistadmin\x27 => \\\\Pterodactyl\\\\Http\\\\Middleware\\\\WhitelistAdmin::class,\n        \x27clientlock\x27 => \\\\App\\\\Http\\\\Middleware\\\\ClientLock::class,\n";
                s/protected\s+\$middlewareAliases\s*=\s*\[(.*?)\];/protected \$middlewareAliases = [$inner$add    ];/s;
            }
        ' -i "$KERNEL"
    fi
}

wrap_admin_routes_global() {
    if ! grep -q "whitelistadmin" "$ADMIN_ROUTES"; then
        perl -0777 -pe '
        if (!m/Route::middleware\(\[.*?whitelistadmin.*?\]\)->group/s) {
            if (m/(.*?)(Route::get\(|Route::group\(|Route::prefix\(|Route::middleware\()/s) {
                $pre=$1; $rest=substr($_,length($pre));
                $_=$pre."Route::middleware([\'whitelistadmin\'])->group(function () {\n".$rest."\n});\n";
            }
        }' -i "$ADMIN_ROUTES"
    fi
}

add_clientlock_to_api_client() {
    perl -0777 -i -pe '
    s/(\bprefix\'\s*=>\s*'\''\/servers\/\{server\}'\''\s*,\s*\'middleware\'\s*=>\s*\[)(\s*(?:[^\]]*?))/$1.(index($2,"\'clientlock\'")==-1?"\'clientlock\', ":"").$2/ge;
    ' "$API_CLIENT"
}

protect_delete_methods() {
    if [ -f "$USERCTL" ]; then
        if ! grep -q "ngapain wok" "$USERCTL"; then
            perl -0777 -i -pe '
            s/(public\s+function\s+delete\s*\([^\)]*\)\s*\{)/$1\n        \$a=(isset(\$this->allowed)?\$this->allowed:[]); if(!in_array(auth()->user()->id,\$a)){ if(request()->wantsJson()){return response()->json(["error"=>"ngapain wok"],403);} if(view()->exists("errors.antirusuh")){return response()->view("errors.antirusuh",["message"=>"ngapain wok"],403);} abort(403);} /s;
            ' "$USERCTL"
        fi
    fi
    if [ -d "$SERVERCTLDIR" ]; then
        for f in "$SERVERCTLDIR"/*.php; do
            if ! grep -q "ngapain wok" "$f"; then
                perl -0777 -i -pe '
                s/(public\s+function\s+delete\s*\([^\)]*\)\s*\{)/$1\n        \$a=(isset(\$this->allowed)?\$this->allowed:[]); if(!in_array(auth()->user()->id,\$a)){ if(request()->wantsJson()){return response()->json(["error"=>"ngapain wok"],403);} if(view()->exists("errors.antirusuh")){return response()->view("errors.antirusuh",["message"=>"ngapain wok"],403);} abort(403);} /s;
                ' "$f"
            fi
        done
    fi
}

create_error_view() {
    mkdir -p "$ERROR_VIEW_DIR"
cat > "$ERROR_VIEW_FILE" <<'HTML'
<!doctype html><html><head><meta charset=utf-8><title>Akses Ditolak</title>
<meta name=viewport content="width=device-width,initial-scale=1">
<style>
body{background:#141A20;color:#E6EEF3;text-align:center;font-family:sans-serif}
.box{margin:10% auto;max-width:720px}
h1{color:#F85A3E}
</style></head><body>
<div class=box><h1>Access Denied</h1><p>{{ $message ?? 'ngapain wok' }}</p></div>
</body></html>
HTML
}

refresh_artisan() {
    cd "$PTERO"
    php artisan route:clear || true
    php artisan config:clear || true
    php artisan cache:clear || true
    php artisan view:clear || true
    systemctl restart pteroq || true
}

uninstall_restore() {
    latest=$(ls -dt "$PTERO"/antirusuh_backup_* 2>/dev/null | head -n1 || true)
    [ -z "$latest" ] && exit 1
    cp -a "$latest/Kernel.php" "$KERNEL" 2>/dev/null || true
    cp -a "$latest/appMiddleware/Middleware" "$PTERO/app/Http/" 2>/dev/null || true
    cp -a "$latest/routes/admin.php" "$ADMIN_ROUTES" 2>/dev/null || true
    cp -a "$latest/routes/api-client.php" "$API_CLIENT" 2>/dev/null || true
    cp -a "$latest/routes/api-application.php" "$API_APP" 2>/dev/null || true
    cp -a "$latest/errors_backup"/* "$PTERO/resources/views/errors/" 2>/dev/null || true
    rm -f "$ADMIN_MW" "$CLIENT_MW" "$ERROR_VIEW_FILE"
    refresh_artisan
}

show_menu() {
    echo "1) Install danz tsu"
    echo "2) Add owner"
    echo "3) Delete owner"
    echo "4) Uninstall"
    echo "5) Exit"
}

add_owner_id() {
    read -p "ID: " NEWID
    for f in "$ADMIN_MW" "$CLIENT_MW"; do
        [ -f "$f" ] && perl -0777 -i -pe "s/protected \\\$allowed\s*=\s*\[(.*?)\];/protected \\\$allowed = [\1,$NEWID];/s" "$f"
    done
    refresh_artisan
}

remove_owner_id() {
    read -p "ID: " DELID
    for f in "$ADMIN_MW" "$CLIENT_MW"; do
        [ -f "$f" ] && perl -0777 -i -pe "s/\b$DELID\b//g; s/,,/,/g; s/\[,\[/[/g" "$f"
    done
    refresh_artisan
}

main_install() {
    backup_files
    read -p "Owner ID(s): " OWNER_IDS
    OWNER_IDS=$(echo "$OWNER_IDS" | sed -E 's/[^0-9,]//g')
    install_middleware_files
    inject_allowed_ids "$OWNER_IDS"
    register_kernel_aliases
    wrap_admin_routes_global
    add_clientlock_to_api_client
    protect_delete_methods
    create_error_view
    refresh_artisan
}

ensure_root

while true; do
    show_menu
    read -p "Pilih: " x
    case "$x" in
        1) main_install ;;
        2) add_owner_id ;;
        3) remove_owner_id ;;
        4) uninstall_restore ;;
        5) exit 0 ;;
    esac
done
