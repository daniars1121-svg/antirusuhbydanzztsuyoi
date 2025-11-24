#!/usr/bin/env bash
# antirusuh.sh — robust universal installer for Pterodactyl AntiRusuh
set -euo pipefail

PTERO="${PTERO:-/var/www/pterodactyl}"
BACKUP_DIR="$PTERO/antirusuh_backup_$(date +%s)"
KERNEL="$PTERO/app/Http/Kernel.php"
ADMIN_MW="$PTERO/app/Http/Middleware/WhitelistAdmin.php"
CLIENT_MW="$PTERO/app/Http/Middleware/ClientLock.php"
API_CLIENT="$PTERO/routes/api-client.php"
ADMIN_ROUTES="$PTERO/routes/admin.php"
USERCTL="$PTERO/app/Http/Controllers/Admin/UserController.php"
SERVERCTL_DIR="$PTERO/app/Http/Controllers/Admin/Servers"

mkdir -p "$BACKUP_DIR"

backup() {
  local f="$1"
  if [ -f "$f" ]; then
    cp -a "$f" "$BACKUP_DIR/$(basename "$f").bak" || true
  fi
}

backup_all() {
  backup "$KERNEL"
  backup "$API_CLIENT"
  backup "$ADMIN_ROUTES"
  backup "$USERCTL"
  if [ -d "$SERVERCTL_DIR" ]; then
    for f in "$SERVERCTL_DIR"/*.php; do backup "$f"; done
  fi
}

echo_banner() {
  cat <<'B'
==========================================
        ANTI RUSUH INSTALLER (UNIVERSAL)
==========================================
B
}

# safe-insert alias into Kernel (only if not present)
kernel_add_alias() {
  local key="$1" class="$2"
  if [ ! -f "$KERNEL" ]; then
    echo "Kernel file not found: $KERNEL"
    return 1
  fi
  if grep -qF "$key" "$KERNEL"; then
    return 0
  fi
  # insert after the line that begins "protected $middlewareAliases = ["
  perl -0777 -i -pe "s/(protected\\s+\\\$middlewareAliases\\s*=\\s*\\[\\s*)/\$1\n        '$key' => $class,\n/s" "$KERNEL"
}

# add clientlock middleware to api-client route group(s) that have /servers prefix
api_client_add_clientlock() {
  [ -f "$API_CLIENT" ] || return 0
  # Add middleware to group headers that contain prefix => '/servers' or '/servers/{server}'
  # but only if that header doesn't already contain 'clientlock' or a 'middleware' key.
  perl -0777 -i -pe '
    s/(\[\s*(["](?:\\.|[^"\\])*["]|[\x27](?:\\.|[^'"'"'\\])*[\x27])\s*=>\s*([\"\x27])\/servers(?:\/\{server\})?\3\s*)(?![^]]*middleware)([^]]*?)(\])/ $1 . ", '\''middleware'\'' => [ '\''clientlock'\'' ]" . $4 . "]" /ges
  ' "$API_CLIENT" 2>/dev/null || true

  # Also handle patterns where prefix is on same line like "'prefix' => '/servers', 'as' => ..."
  perl -0777 -i -pe '
    s/((["'\''"])prefix\2\s*=>\s*([\"\x27])\/servers(?:\/\{server\})?\3\s*,\s*)(?=(?:[^]]*\]))(?![^]]*middleware)/ $1 . "\x27middleware\x27 => [\x27clientlock\x27], " /ges
  ' "$API_CLIENT" 2>/dev/null || true
}

# add whitelistadmin to admin route group headers for common prefixes (only if missing)
admin_add_whitelist() {
  [ -f "$ADMIN_ROUTES" ] || return 0
  prefixes=(servers nodes databases users mounts locations)
  for p in "${prefixes[@]}"; do
    # if prefix exists and group header does not contain middleware, add middleware entry
    perl -0777 -i -pe '
      $p = shift;
      s/(\[\s*(["'\'']?)prefix\2\s*=>\s*([\"\x27])' . $p . '\3\s*)(?![^]]*middleware)([^]]*?)(\])/ $1 . ", '\''middleware'\'' => [ '\''whitelistadmin'\'' ]" . $4 . "]" /ges
    ' "$p" "$ADMIN_ROUTES" 2>/dev/null || true
  done
  # cleanup possible double-commas left behind by earlier modifications
  perl -0777 -i -pe 's/,\s*,/,/g; s/\[\s*,/[/g; s/,(\s*[\]\}])/ $1/g;' "$ADMIN_ROUTES" 2>/dev/null || true
}

# safely insert protection into delete functions in controllers
protect_delete_insert() {
  local file="$1"
  [ -f "$file" ] || return 0
  # insert check right after opening brace of public function delete(...) {
  perl -0777 -i -pe '
    s/(public\s+function\s+delete\s*\(.*?\)\s*\{)/$1\n        // ANTI_RUSUH_PROTECT\n        $allowed = ['"$OWNER"']; if (! auth()->user() || ! in_array(auth()->user()->id, $allowed)) abort(403, "ngapain wok");/g;
  ' "$file" 2>/dev/null || true
}

# cleanup routes to avoid empty array elements / double-commas
cleanup_routes() {
  for f in "$@"; do
    [ -f "$f" ] || continue
    # remove stray ,, and fix [, ] patterns
    perl -0777 -i -pe 's/,\s*,/,/g; s/\[\s*,/[/g; s/,\s*\]/]/g; s/\{\s*,/\{/g;' "$f" 2>/dev/null || true
  done
}

install() {
  echo_banner
  read -p "Masukkan ID Owner utama (angka): " OWNER
  if ! [[ "$OWNER" =~ ^[0-9]+$ ]]; then
    echo "Owner ID harus angka"; return 1
  fi

  echo "Backup files to $BACKUP_DIR"
  mkdir -p "$BACKUP_DIR"
  backup_all

  mkdir -p "$(dirname "$ADMIN_MW")"

  cat > "$ADMIN_MW" <<EOF
<?php

namespace Pterodactyl\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

class WhitelistAdmin
{
    public function handle(Request \$request, Closure \$next)
    {
        \$allowed = [$OWNER];
        if (! \$request->user() || ! in_array(\$request->user()->id, \$allowed)) {
            abort(403, "ngapain wok");
        }
        return \$next(\$request);
    }
}
EOF

  cat > "$CLIENT_MW" <<'EOF'
<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

class ClientLock
{
    public function handle(Request $request, Closure $next)
    {
        $allowed = [__OWNER__];
        $u = $request->user();
        if (! $u) abort(403, "ngapain wok");
        if (in_array($u->id, $allowed)) return $next($request);

        $server = $request->route("server");
        if ($server) {
            $ownerId = $server->owner_id ?? ($server->user_id ?? null);
            if ($ownerId === null || $ownerId != $u->id) abort(403, "ngapain wok");
        } else {
            # fallback: block direct /api/client/servers calls if no route param
            $uri = $request->getRequestUri();
            if (strpos($uri, "/api/client/servers") !== false) abort(403, "ngapain wok");
        }

        return $next($request);
    }
}
EOF
  # replace owner placeholder
  sed -i "s/__OWNER__/$OWNER/" "$CLIENT_MW"

  # register aliases into kernel safely
  kernel_add_alias "clientlock" "\\\\App\\\\Http\\\\Middleware\\\\ClientLock::class"
  kernel_add_alias "whitelistadmin" "\\\\Pterodactyl\\\\Http\\\\Middleware\\\\WhitelistAdmin::class"

  # patch api-client routes robustly
  api_client_add_clientlock

  # patch admin routes to add whitelist admin where applicable
  admin_add_whitelist

  # insert protect-delete into controllers
  protect_delete_insert "$USERCTL"
  if [ -d "$SERVERCTL_DIR" ]; then
    for f in "$SERVERCTL_DIR"/*.php; do protect_delete_insert "$f"; done
  fi

  # cleanup route files to ensure no stray commas
  cleanup_routes "$API_CLIENT" "$ADMIN_ROUTES"

  # refresh laravel caches
  if [ -d "$PTERO" ]; then
    cd "$PTERO"
    php artisan route:clear || true
    php artisan config:clear || true
    php artisan cache:clear || true
    php artisan view:clear || true
    if command -v systemctl >/dev/null 2>&1; then
      systemctl restart pteroq || true
    fi
  fi

  echo "Install selesai. Owner: $OWNER"
  echo "Backups disimpan di: $BACKUP_DIR"
}

add_owner() {
  read -p "Masukkan ID Owner baru: " NEW
  if ! [[ "$NEW" =~ ^[0-9]+$ ]]; then echo "ID harus angka"; return 1; fi
  # add if not present
  if [ -f "$ADMIN_MW" ] && ! grep -q "\b$NEW\b" "$ADMIN_MW"; then
    perl -0777 -i -pe "s/\\[(.*?)\\]/'[' . \$1 . ',' . '$NEW' . ']' /es" "$ADMIN_MW" || true
  fi
  if [ -f "$CLIENT_MW" ] && ! grep -q "\b$NEW\b" "$CLIENT_MW"; then
    perl -0777 -i -pe "s/\\[(.*?)\\]/'[' . \$1 . ',' . '$NEW' . ']' /es" "$CLIENT_MW" || true
  fi
  cd "$PTERO" && php artisan route:clear >/dev/null 2>&1 || true
  echo "Owner $NEW ditambahkan."
}

del_owner() {
  read -p "Masukkan ID Owner yang ingin dihapus: " DEL
  if ! [[ "$DEL" =~ ^[0-9]+$ ]]; then echo "ID harus angka"; return 1; fi
  if [ -f "$ADMIN_MW" ]; then
    perl -0777 -i -pe "s/\\b$DEL\\b//g; s/,\\s*,/,/g; s/\\[\\s*,/[/g; s/,\\s*\\]/]/g;" "$ADMIN_MW" || true
  fi
  if [ -f "$CLIENT_MW" ]; then
    perl -0777 -i -pe "s/\\b$DEL\\b//g; s/,\\s*,/,/g; s/\\[\\s*,/[/g; s/,\\s*\\]/]/g;" "$CLIENT_MW" || true
  fi
  cd "$PTERO" && php artisan route:clear >/dev/null 2>&1 || true
  echo "Owner $DEL dihapus."
}

uninstall() {
  read -p "Yakin uninstall AntiRusuh? (y/N): " C
  if [[ "$C" != "y" && "$C" != "Y" ]]; then echo "Batal."; return 0; fi

  rm -f "$ADMIN_MW" "$CLIENT_MW" || true
  # remove aliases from kernel
  if [ -f "$KERNEL" ]; then
    perl -0777 -i -pe "s/\\s*'clientlock'\\s*=>\\s*[^,\\n]+,?\\n//g; s/\\s*'whitelistadmin'\\s*=>\\s*[^,\\n]+,?\\n//g;" "$KERNEL" || true
  fi
  # remove middleware arrays in routes safely (best-effort)
  for f in "$ADMIN_ROUTES" "$API_CLIENT"; do
    if [ -f "$f" ]; then
      perl -0777 -i -pe "s/,?\\s*'middleware'\\s*=>\\s*\\[[^\\]]*\\]\\s*,?//g; s/,\\s*,/,/g; s/\\[\\s*,/[/g; s/,\\s*\\]/]/g;" "$f" || true
    fi
  done

  cd "$PTERO"
  php artisan route:clear >/dev/null 2>&1 || true
  php artisan cache:clear >/dev/null 2>&1 || true
  if command -v systemctl >/dev/null 2>&1; then systemctl restart pteroq || true; fi

  echo "Uninstall selesai."
}

usage() {
  cat <<'U'
AntiRusuh installer - menu
1) Install
2) Add owner
3) Delete owner
4) Uninstall
5) Exit
U
}

main() {
  while true; do
    echo_banner
    usage
    read -p "Pilih: " CH
    case "$CH" in
      1) install ;;
      2) add_owner ;;
      3) del_owner ;;
      4) uninstall ;;
      5) exit 0 ;;
      *) echo "Pilihan tidak valid." ;;
    esac
  done
}

main
