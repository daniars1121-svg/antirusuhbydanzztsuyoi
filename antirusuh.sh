#!/usr/bin/env bash
# Antirusuh installer - robust, safe, reversible
# - wraps entire admin.php in middleware group (safe)
# - creates WhitelistAdmin and ClientLock middleware
# - registers aliases in Kernel (only once)
# - injects clientlock into api-client servers group (only if missing)
# - makes backups and restores them on uninstall
# - avoids in-place controller edits (no protect_delete)
# Tested logic for varied Pterodactyl layouts. Use as root.

set -euo pipefail
IFS=$'\n\t'

PTERO="/var/www/pterodactyl"
ADMIN_ROUTES="$PTERO/routes/admin.php"
API_CLIENT="$PTERO/routes/api-client.php"
KERNEL="$PTERO/app/Http/Kernel.php"
ADMIN_MW="$PTERO/app/Http/Middleware/WhitelistAdmin.php"
CLIENT_MW="$PTERO/app/Http/Middleware/ClientLock.php"
BACKUP_DIR="$PTERO/antirusuh_backups_$(date +%s)"
TMP="/tmp/antirusuh.$$"

mkdir -p "$BACKUP_DIR"
echo "Backups will be stored in: $BACKUP_DIR"

die() { echo "ERROR: $*" >&2; exit 1; }

ensure_root() {
    if [ "$EUID" -ne 0 ]; then
        die "Run script as root."
    fi
}

backup_if_exist() {
    local f="$1"
    if [ -f "$f" ]; then
        cp -a "$f" "$BACKUP_DIR/$(basename "$f").bak"
        echo "Backed up $f -> $BACKUP_DIR/$(basename "$f").bak"
    fi
}

# Insert middleware aliases into Kernel in a safe way (only if missing)
register_kernel_aliases() {
    local k="$KERNEL"
    [ -f "$k" ] || die "Kernel not found at $k"
    grep -q "whitelistadmin" "$k" || {
        # insert aliases right after the line containing "protected \$middlewareAliases = ["
        awk -v a="        'clientlock' => \\\\App\\\\Http\\\\Middleware\\\\ClientLock::class," \
            -v b="        'whitelistadmin' => \\\\Pterodactyl\\\\Http\\\\Middleware\\\\WhitelistAdmin::class," \
            '{
                print $0
                if (!done && $0 ~ /protected[[:space:]]+\$middlewareAliases[[:space:]]*=/) {
                    # print a and b on next lines
                    print a
                    print b
                    done=1
                }
            }' "$k" > "$TMP.kern" && mv "$TMP.kern" "$k"
        echo "Inserted middleware aliases into Kernel."
    } || echo "Kernel already contains aliases; skipping."
}

# Create WhitelistAdmin middleware file
create_whitelist_admin() {
    mkdir -p "$(dirname "$ADMIN_MW")"
    cat > "$ADMIN_MW" <<'PHP'
<?php
namespace Pterodactyl\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

class WhitelistAdmin
{
    /**
     * Expected: $allowed replaced at install-time by installer.
     */
    public function handle(Request $request, Closure $next)
    {
        // installer will populate $allowed array literal
        $allowed = [__PTERO_OWNER_PLACEHOLDER__];

        if (!$request->user() || !in_array($request->user()->id, $allowed)) {
            // Return proper 403 response; keep abort to let laravel handle
            abort(403, 'Access denied.');
        }

        return $next($request);
    }
}
PHP
    echo "Created WhitelistAdmin middleware at $ADMIN_MW (placeholder owner)."
}

# Create ClientLock middleware file
create_client_lock() {
    mkdir -p "$(dirname "$CLIENT_MW")"
    cat > "$CLIENT_MW" <<'PHP'
<?php
namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

class ClientLock
{
    public function handle(Request $request, Closure $next)
    {
        // installer will populate $allowed array literal
        $allowed = [__PTERO_OWNER_PLACEHOLDER__];

        $u = $request->user();
        if (!$u) {
            abort(403, 'Access denied.');
        }

        if (in_array($u->id, $allowed)) {
            return $next($request);
        }

        $server = $request->route('server');
        if ($server && isset($server->owner_id) && $server->owner_id != $u->id) {
            abort(403, 'Access denied.');
        }

        return $next($request);
    }
}
PHP
    echo "Created ClientLock middleware at $CLIENT_MW (placeholder owner)."
}

# Replace placeholder owner in created middleware files with actual id(s)
populate_owner_in_middleware() {
    local owner_literal="$1" # e.g. 1 or 1,2,3
    # make sure we replace the placeholder array content with a proper number list
    sed -i "s/__PTERO_OWNER_PLACEHOLDER__/$owner_literal/g" "$ADMIN_MW" "$CLIENT_MW"
    echo "Populated owner(s) [$owner_literal] into middleware files."
}

# Wrap admin.php contents inside Route::middleware(['whitelistadmin'])->group(function () { ... });
wrap_admin_routes() {
    local f="$ADMIN_ROUTES"
    [ -f "$f" ] || die "admin.php not found at $f"

    # Check if already wrapped
    if grep -q "Route::middleware.*whitelistadmin" "$f"; then
        echo "admin.php already wrapped with whitelistadmin. Skipping wrapper."
        return 0
    fi

    # create backup before modifying
    backup_if_exist "$f"

    # We will insert the wrapper after the first occurrence of line containing
    # "Route::get('/', [Admin\BaseController::class, 'index'])->name('admin.index');"
    # If that exact line isn't present, fallback to inserting at top after opening PHP tag.

    awk '
    BEGIN { inserted=0; foundIndexRoute=0; }
    {
        lines[NR]=$0
        if (!foundIndexRoute && $0 ~ /Route::get.*index.*name\([[:space:]]*'\''admin\.index'\''\)/) {
            idx=NR
            foundIndexRoute=1
        }
    }
    END {
        if (foundIndexRoute) {
            for (i=1;i<=NR;i++) {
                print lines[i]
                if (i==idx) {
                    print ""
                    print "Route::middleware([\"whitelistadmin\"])->group(function () {"
                }
            }
            print "});"
        } else {
            # fallback: put wrapper after first non-empty line after <?php
            inserted=0
            for (i=1;i<=NR;i++) {
                print lines[i]
                if (!inserted && lines[i] ~ /<\?php/) {
                    print ""
                    print "Route::middleware([\"whitelistadmin\"])->group(function () {"
                    inserted=1
                }
            }
            print "});"
        }
    }' "$f" > "$TMP.admin" && mv "$TMP.admin" "$f"

    echo "Wrapped admin.php with Route::middleware(['whitelistadmin'])->group(...). Backup at $BACKUP_DIR/$(basename "$f").bak"
}

# Add clientlock to api-client servers group safely
inject_clientlock_api_client() {
    local f="$API_CLIENT"
    [ -f "$f" ] || { echo "api-client.php not found, skipping clientlock injection."; return 0; }

    # if already contains clientlock, skip
    if grep -q "clientlock" "$f"; then
        echo "api-client.php already contains clientlock. Skipping."
        return 0
    fi

    # Replace "'prefix' => '/servers/{server}'," with the same + middleware
    # only if that exact prefix exists and not already a middleware key.
    perl -0777 -pe '
      if ( $_ =~ /'\''prefix'\''\s*=>\s*'\''\/servers\/\{server\}'\''/s ) {
         s/('\''prefix'\''\s*=>\s*'\''\/servers\/\{server\}'\''\s*,)/$1 . " '\''middleware'\'' => [ '\''clientlock'\'' ], "/e;
      }
    ' "$f" > "$TMP.api" && mv "$TMP.api" "$f"

    echo "Injected clientlock middleware into api-client servers prefix (if matched)."
}

# restore backups on uninstall
restore_backup() {
    local file="$1"
    local bak="$BACKUP_DIR/$(basename "$file").bak"
    if [ -f "$bak" ]; then
        cp -a "$bak" "$file"
        echo "Restored $file from $bak"
    else
        echo "No backup found for $file at $bak (skipping)."
    fi
}

install_flow() {
    ensure_root
    read -p "Masukkan ID owner utama (angka): " OWNERID
    if ! [[ "$OWNERID" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
        die "Owner ID harus angka atau daftar angka dipisah koma (contoh: 1 atau 1,2,3)."
    fi

    # backup originals
    backup_if_exist "$ADMIN_ROUTES"
    backup_if_exist "$API_CLIENT"
    backup_if_exist "$KERNEL"

    # create middleware files
    create_whitelist_admin
    create_client_lock

    # populate owners in middleware
    populate_owner_in_middleware "$OWNERID"

    # register aliases in kernel
    register_kernel_aliases

    # wrap admin.php (safe wrapper)
    wrap_admin_routes

    # inject clientlock to api-client
    inject_clientlock_api_client

    # clear caches and restart queue
    if [ -d "$PTERO" ]; then
        pushd "$PTERO" >/dev/null || true
        php artisan route:clear || true
        php artisan cache:clear || true
        php artisan config:clear || true
        php artisan view:clear || true
        popd >/dev/null || true
    fi

    # restart pteroq if systemd unit exists
    if systemctl list-units --type=service --all | grep -q "pteroq.service"; then
        systemctl restart pteroq || echo "Warning: failed to restart pteroq, check systemctl status pteroq.service"
    fi

    echo "Install selesai. Jika ada error, periksa log: $PTERO/storage/logs/laravel-*.log"
    echo "Backups stored in $BACKUP_DIR"
}

uninstall_flow() {
    ensure_root
    echo "Restoring backups (if present)..."
    restore_backup "$ADMIN_ROUTES"
    restore_backup "$API_CLIENT"
    restore_backup "$KERNEL"

    # remove middleware files if exist
    rm -f "$ADMIN_MW" "$CLIENT_MW" || true

    # clear caches and restart queue
    if [ -d "$PTERO" ]; then
        pushd "$PTERO" >/dev/null || true
        php artisan route:clear || true
        php artisan cache:clear || true
        php artisan config:clear || true
        php artisan view:clear || true
        popd >/dev/null || true
    fi

    if systemctl list-units --type=service --all | grep -q "pteroq.service"; then
        systemctl restart pteroq || echo "Warning: failed to restart pteroq"
    fi

    echo "Uninstall selesai. Jika restore gagal, restore manual from $BACKUP_DIR"
}

show_help() {
cat <<EOF
Usage: $0 [install|uninstall|help]
  install    -> install AntiRusuh (creates middleware, wraps admin routes)
  uninstall  -> restore backups and remove created middleware files
  help       -> show this help
EOF
}

main() {
    case "${1:-}" in
        install) install_flow ;;
        uninstall) uninstall_flow ;;
        help|"") show_help ;;
        *) show_help ;;
    esac
}

main "$@"
