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
    [ "$(id -u)" -eq 0 ] || exit 1
}

backup_files() {
    mkdir -p "$BACKUP_DIR"

    cp -a "$KERNEL" "$BACKUP_DIR/" 2>/dev/null || true
    cp -a "$ADMIN_ROUTES" "$BACKUP_DIR/" 2>/dev/null || true
    cp -a "$API_CLIENT" "$BACKUP_DIR/" 2>/dev/null || true
    cp -a "$API_APP" "$BACKUP_DIR/" 2>/dev/null || true
    cp -a "$PTERO/app/Http/Middleware" "$BACKUP_DIR/middleware" 2>/dev/null || true
    cp -a "$PTERO/resources/views/errors" "$BACKUP_DIR/errors" 2>/dev/null || true
}

install_middleware_files() {
mkdir -p "$(dirname "$ADMIN_MW")"
mkdir -p "$(dirname "$CLIENT_MW")"

cat <<'PHP' > "$ADMIN_MW"
<?php
namespace Pterodactyl\Http\Middleware;
use Closure; use Illuminate\Http\Request;

class WhitelistAdmin {
    protected $allowed = [];

    public function handle(Request $r, Closure $n) {
        $u = $r->user();
        if(!$u || !in_array($u->id, $this->allowed)){
            if ($r->wantsJson()) return response()->json(['error'=>'ngapain wok'],403);
            return abort(403,'ngapain wok');
        }
        return $n($r);
    }
}
PHP

cat <<'PHP' > "$CLIENT_MW"
<?php
namespace App\Http\Middleware;
use Closure; use Illuminate\Http\Request;

class ClientLock {
    protected $allowed = [];

    public function handle(Request $r, Closure $n) {
        $u = $r->user();
        if(!$u) abort(403,'ngapain wok');

        if(in_array($u->id,$this->allowed)) return $n($r);

        $s = $r->route('server');
        if($s && $s->owner_id != $u->id){
            abort(403,'ngapain wok');
        }
        return $n($r);
    }
}
PHP
}

inject_allowed_ids() {
    local ids="$1"

    perl -0777 -i -pe "s/protected \\\$allowed = \[.*?\];/protected \\\$allowed = [$ids];/s" "$ADMIN_MW"
    perl -0777 -i -pe "s/protected \\\$allowed = \[.*?\];/protected \\\$allowed = [$ids];/s" "$CLIENT_MW"
}

register_kernel_aliases() {
perl -0777 -i -pe '
if ($_ =~ /protected \$middlewareAliases = \[(.*?)\];/s) {
    if ($_ !~ /whitelistadmin/) {
        s/protected \$middlewareAliases = \[/protected \$middlewareAliases = [\n        '\''whitelistadmin'\'' => \\\\Pterodactyl\\\\Http\\\\Middleware\\\\WhitelistAdmin::class,\n        '\''clientlock'\'' => \\\\App\\\\Http\\\\Middleware\\\\ClientLock::class,\n/s;
    }
}
' "$KERNEL"
}

wrap_admin_routes_global() {
    if grep -q "whitelistadmin" "$ADMIN_ROUTES"; then return; fi

    perl -0777 -i -pe '
    $_ = "Route::middleware([ '\''whitelistadmin'\'' ])->group(function(){\n" . $_ . "\n});\n";
    ' "$ADMIN_ROUTES"
}

add_clientlock_to_api_client() {
    perl -0777 -i -pe "s/'middleware' => \[/'middleware' => ['clientlock',/g" "$API_CLIENT"
}

create_error_view() {
mkdir -p "$ERROR_VIEW_DIR"

cat <<'HTML' > "$ERROR_VIEW_FILE"
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>Akses Ditolak</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
body{background:#121212;color:#eee;text-align:center;font-family:sans-serif;margin-top:10%;}
h1{color:#ff4444;}
</style>
</head>
<body>
<h1>Access Denied</h1>
<p>{{ $message ?? "ngapain wok" }}</p>
</body>
</html>
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
    latest=$(ls -dt "$PTERO"/antirusuh_backup_* 2>/dev/null | head -n1)
    [ -z "$latest" ] && exit 1

    cp -a "$latest/Kernel.php" "$KERNEL" 2>/dev/null || true
    cp -a "$latest/admin.php" "$ADMIN_ROUTES" 2>/dev/null || true
    cp -a "$latest/api-client.php" "$API_CLIENT" 2>/dev/null || true
    cp -a "$latest/api-application.php" "$API_APP" 2>/dev/null || true
    cp -a "$latest/middleware" "$PTERO/app/Http/" 2>/dev/null || true
    cp -a "$latest/errors" "$PTERO/resources/views/" 2>/dev/null || true

    rm -f "$ADMIN_MW" "$CLIENT_MW" "$ERROR_VIEW_FILE"

    refresh_artisan
}

show_menu() {
    echo "1) Install"
    echo "2) Add owner"
    echo "3) Delete owner"
    echo "4) Uninstall"
    echo "5) Exit"
}

add_owner_id() {
    read -p "ID: " id
    perl -0777 -i -pe "s/protected \\\$allowed = \[(.*?)\];/protected \\\$allowed = [\1,$id];/s" "$ADMIN_MW"
    perl -0777 -i -pe "s/protected \\\$allowed = \[(.*?)\];/protected \\\$allowed = [\1,$id];/s" "$CLIENT_MW"
    refresh_artisan
}

remove_owner_id() {
    read -p "ID: " id
    perl -0777 -i -pe "s/\b$id\b//g; s/,,/,/g;" "$ADMIN_MW"
    perl -0777 -i -pe "s/\b$id\b//g; s/,,/,/g;" "$CLIENT_MW"
    refresh_artisan
}

main_install() {
    backup_files
    read -p "Owner ID(s): " owner
    owner=$(echo "$owner" | sed -E 's/[^0-9,]//g')

    install_middleware_files
    inject_allowed_ids "$owner"
    register_kernel_aliases
    wrap_admin_routes_global
    add_clientlock_to_api_client
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
