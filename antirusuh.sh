#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

PTERO="/var/www/pterodactyl"
ADMIN_MW="$PTERO/app/Http/Middleware/WhitelistAdmin.php"
CLIENT_MW="$PTERO/app/Http/Middleware/ClientLock.php"
KERNEL="$PTERO/app/Http/Kernel.php"
USERCTL="$PTERO/app/Http/Controllers/Admin/UserController.php"
SERVERCTL="$PTERO/app/Http/Controllers/Admin/Servers"
BACKUP_DIR="$PTERO/antirusuh_backup_$(date +%s)"
TMP="/tmp/antirusuh.$$"

mkdir -p "$BACKUP_DIR"

banner() {
    cat <<'B'
======================================
        ANTIRUSUH PTERODACTYL
======================================
B
}

die() { echo "ERROR: $*" >&2; exit 1; }

backup_file() {
    local f="$1"
    [ -f "$f" ] && cp -a "$f" "$BACKUP_DIR/$(basename "$f").bak"
}

# safer protect_delete: insert check only if file exists and not already inserted
protect_delete() {
    local file="$1"
    local owner_arr="$2"
    [ -f "$file" ] || return 0

    # check if marker already present
    if grep -q "ANTI_RUSUH_PROTECT" "$file"; then
        echo "Protect already present in $file - skipping"
        return 0
    fi

    # Insert protection after function delete opening brace (best-effort)
    perl -0777 -i -pe '
      my $owner = shift;
      s/(public\s+function\s+delete\s*\([^\)]*\)\s*\{)/$1\n        // ANTI_RUSUH_PROTECT\n        $allowed = ['.$owner.']; if (! auth()->user() || ! in_array(auth()->user()->id, $allowed)) abort(403, "ngapain wok");/g
    ' "$owner_arr" "$file" 2>/dev/null || true
}

# create middleware files
create_middlewares() {
    local owner="$1"
    mkdir -p "$(dirname "$ADMIN_MW")"
    mkdir -p "$(dirname "$CLIENT_MW")"

    backup_file "$ADMIN_MW"
    backup_file "$CLIENT_MW"
    backup_file "$KERNEL"

    cat > "$ADMIN_MW" <<EOF
<?php
namespace Pterodactyl\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

class WhitelistAdmin {
    public function handle(Request \$request, Closure \$next) {
        \$allowed = [$owner];
        if (!\$request->user() || !in_array(\$request->user()->id, \$allowed)) {
            // use abort - Laravel will handle presentation
            abort(403, "ngapain wok");
        }
        return \$next(\$request);
    }
}
EOF

    cat > "$CLIENT_MW" <<EOF
<?php
namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

class ClientLock {
    public function handle(Request \$request, Closure \$next) {
        \$allowed = [$owner];
        \$u = \$request->user();

        if (!\$u) abort(403, "ngapain wok");
        if (in_array(\$u->id, \$allowed)) return \$next(\$request);

        \$server = \$request->route("server");
        if (\$server && property_exists(\$server, "owner_id") && \$server->owner_id != \$u->id) {
            abort(403, "ngapain wok");
        }

        return \$next(\$request);
    }
}
EOF
    echo "Middleware files created: $ADMIN_MW and $CLIENT_MW"
}

# register aliases in Kernel (idempotent and safe)
register_kernel_aliases() {
    [ -f "$KERNEL" ] || { echo "Kernel not found at $KERNEL - skipping kernel registration"; return 0; }

    if ! grep -q "whitelistadmin" "$KERNEL"; then
        awk -v ins1="        'whitelistadmin' => \\\\Pterodactyl\\\\Http\\\\Middleware\\\\WhitelistAdmin::class," \
            -v ins2="        'clientlock' => \\\\App\\\\Http\\\\Middleware\\\\ClientLock::class," \
            '{
                print $0
                if (!done && $0 ~ /protected[[:space:]]+\$middlewareAliases[[:space:]]*=/) {
                    print ins1
                    print ins2
                    done=1
                }
            }' "$KERNEL" > "$TMP.k" && mv "$TMP.k" "$KERNEL"
        echo "Registered middleware aliases in Kernel."
    else
        echo "Kernel already contains whitelistadmin/clientlock entries - skipping."
    fi
}

# try to wrap admin.php safely (best-effort)
wrap_admin_routes() {
    local f="$PTERO/routes/admin.php"
    [ -f "$f" ] || { echo "admin.php not found - skipping wrapper"; return 0; }
    # skip if already wrapped
    if grep -q "Route::middleware.*whitelistadmin" "$f"; then
        echo "admin.php already wrapped with whitelistadmin - skipping."
        return 0
    fi

    backup_file "$f"

    # find the line with admin.index route
    local idx_line
    idx_line=$(nl -ba "$f" | sed -n "1,200p" | grep -n "name('admin.index')" | head -n1 | cut -d: -f1 || true)
    if [ -n "$idx_line" ]; then
        # insert wrapper after that line
        awk -v n="$idx_line" 'NR==n{print; print ""; print "Route::middleware([\x27whitelistadmin\x27])->group(function () {"; next} {print}' "$f" > "$TMP.admin"
        # append closing at end
        printf "\n});\n" >> "$TMP.admin"
        mv "$TMP.admin" "$f"
        echo "Wrapped admin.php with whitelistadmin group."
    else
        # fallback: insert after <?php
        awk 'NR==1{print; print "Route::middleware([\x27whitelistadmin\x27])->group(function () {"; next} {print}' "$f" > "$TMP.admin"
        printf "\n});\n" >> "$TMP.admin"
        mv "$TMP.admin" "$f"
        echo "Wrapped admin.php (fallback method)."
    fi
}

# inject clientlock into api-client.php servers group (safe, best-effort)
inject_clientlock_api_client() {
    local f="$PTERO/routes/api-client.php"
    [ -f "$f" ] || { echo "api-client.php not found - skipping clientlock injection"; return 0; }

    if grep -q "clientlock" "$f"; then
        echo "clientlock already present in api-client.php - skipping."
        return 0
    fi

    # attempt several patterns
    # pattern 1: 'prefix' => '/servers/{server}',
    perl -0777 -pe 's/(\x27prefix\x27\s*=>\s*\x27\/servers\/\{server\}\x27\s*,\s*)(?![^[]*\bmiddleware\b)/$1 . "\x27middleware\x27 => [\x27clientlock\x27], "/ge' "$f" > "$TMP.api" && mv "$TMP.api" "$f" || true

    # pattern 2: 'prefix' => '/servers',
    perl -0777 -pe 's/(\x27prefix\x27\s*=>\s*\x27\/servers\x27\s*,\s*)(?![^[]*\bmiddleware\b)/$1 . "\x27middleware\x27 => [\x27clientlock\x27], "/ge' "$f" > "$TMP.api" && mv "$TMP.api" "$f" || true

    echo "Attempted to inject clientlock into api-client.php (if pattern matched)."
}

clear_and_restart() {
    [ -d "$PTERO" ] || return 0
    pushd "$PTERO" >/dev/null || return 0
    php artisan route:clear || true
    php artisan cache:clear || true
    php artisan config:clear || true
    php artisan view:clear || true
    popd >/dev/null || true

    if command -v systemctl >/dev/null 2>&1 && systemctl list-units --type=service --all | grep -q "pteroq.service"; then
        systemctl restart pteroq || true
    fi
}

install_antirusuh() {
    banner
    read -p "Masukkan ID Owner Utama: " OWNER
    if ! [[ "$OWNER" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
        echo "ID owner harus angka atau koma-separator (contoh: 1 atau 1,2)"
        return 1
    fi

    backup_file "$KERNEL"
    backup_file "$PTERO/routes/admin.php"
    backup_file "$PTERO/routes/api-client.php"

    create_middlewares "$OWNER"
    register_kernel_aliases
    wrap_admin_routes
    inject_clientlock_api_client

    clear_and_restart

    echo "ANTIRUSUH TERPASANG. Backups: $BACKUP_DIR"
}

add_owner() {
    read -p "Masukkan ID Owner Baru: " NEW
    if ! [[ "$NEW" =~ ^[0-9]+$ ]]; then echo "ID harus angka"; return 1; fi
    if [ -f "$ADMIN_MW" ]; then
        # insert if not present
        if ! grep -q "\b$NEW\b" "$ADMIN_MW"; then
            perl -0777 -i -pe "s/\\[(.*?)\\]/'[' . \$1 . ',' . '$NEW' . ']' /es" "$ADMIN_MW" || true
        fi
    fi
    if [ -f "$CLIENT_MW" ]; then
        if ! grep -q "\b$NEW\b" "$CLIENT_MW"; then
            perl -0777 -i -pe "s/\\[(.*?)\\]/'[' . \$1 . ',' . '$NEW' . ']' /es" "$CLIENT_MW" || true
        fi
    fi
    clear_and_restart
    echo "Owner $NEW ditambahkan."
}

delete_owner() {
    read -p "Masukkan ID Owner yang ingin dihapus: " DEL
    if ! [[ "$DEL" =~ ^[0-9]+$ ]]; then echo "ID harus angka"; return 1; fi
    if [ -f "$ADMIN_MW" ]; then
        perl -0777 -i -pe "s/\\b$DEL\\b//g; s/,\\s*,/,/g; s/\\[\\s*,/[/g; s/,\\s*\\]/]/g;" "$ADMIN_MW" || true
    fi
    if [ -f "$CLIENT_MW" ]; then
        perl -0777 -i -pe "s/\\b$DEL\\b//g; s/,\\s*,/,/g; s/\\[\\s*,/[/g; s/,\\s*\\]/]/g;" "$CLIENT_MW" || true
    fi
    clear_and_restart
    echo "Owner $DEL dihapus."
}

uninstall_antirusuh() {
    echo "Uninstalling: restoring backups if available..."
    if [ -f "$BACKUP_DIR/Kernel.php.bak" ]; then cp -a "$BACKUP_DIR/Kernel.php.bak" "$KERNEL"; fi
    if [ -f "$BACKUP_DIR/admin.php.bak" ]; then cp -a "$BACKUP_DIR/admin.php.bak" "$PTERO/routes/admin.php"; fi
    if [ -f "$BACKUP_DIR/api-client.php.bak" ]; then cp -a "$BACKUP_DIR/api-client.php.bak" "$PTERO/routes/api-client.php"; fi

    rm -f "$ADMIN_MW" "$CLIENT_MW" || true

    clear_and_restart

    echo "Uninstall finished. Check $BACKUP_DIR if restore required."
}

menu() {
    while true; do
        banner
        echo "1) Install AntiRusuh"
        echo "2) Tambah Owner"
        echo "3) Hapus Owner"
        echo "4) Uninstall"
        echo "5) Exit"
        read -p "Pilih: " x
        case "$x" in
            1) install_antirusuh ;;
            2) add_owner ;;
            3) delete_owner ;;
            4) uninstall_antirusuh ;;
            5) exit 0 ;;
            *) echo "Pilihan tidak valid." ;;
        esac
    done
}

menu

