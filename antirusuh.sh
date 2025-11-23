#!/usr/bin/env bash
# antirusuh.sh — Safe Pterodactyl "AntiRusuh" installer (install / add-owner / del-owner / uninstall)
# Usage: bash antirusuh.sh
set -euo pipefail

PTERO="/var/www/pterodactyl"
ROUTES_DIR="$PTERO/routes"
KERNEL="$PTERO/app/Http/Kernel.php"
MIDDLEWARE_DIR="$PTERO/app/Http/Middleware"
MIDDLEWARE_ADMIN="$MIDDLEWARE_DIR/WhitelistAdmin.php"
MIDDLEWARE_CLIENT="$MIDDLEWARE_DIR/ClientLock.php"
USER_CONTROLLER="$PTERO/app/Http/Controllers/Admin/UserController.php"
SERVER_CONTROLLERS_DIR="$PTERO/app/Http/Controllers/Admin/Servers"

backup_file() {
    local file="$1"
    if [ -f "$file" ]; then
        cp -a "$file" "$file.bak.$(date +%s)" || true
    fi
}

# Read current owners (comma separated, no spaces)
get_owners_from_file() {
    if [ -f "$MIDDLEWARE_ADMIN" ]; then
        grep "\$allowedAdmins" "$MIDDLEWARE_ADMIN" 2>/dev/null | sed -E "s/.*\[(.*)\].*/\1/" | tr -d ' ' || true
    else
        echo ""
    fi
}

save_owners_to_files() {
    local owners="$1"
    # Ensure files exist before trying to replace
    if [ -f "$MIDDLEWARE_ADMIN" ]; then
        sed -i "s/\\\$allowedAdmins = \\[.*\\];/\\\$allowedAdmins = [$owners];/" "$MIDDLEWARE_ADMIN"
    fi
    if [ -f "$MIDDLEWARE_CLIENT" ]; then
        sed -i "s/\\\$allowedAdmins = \\[.*\\];/\\\$allowedAdmins = [$owners];/" "$MIDDLEWARE_CLIENT"
    fi
}

install() {
    echo "[1/8] Validating paths..."
    if [ ! -d "$PTERO" ]; then
        echo "Error: pterodactyl path $PTERO not found." >&2
        exit 1
    fi
    mkdir -p "$MIDDLEWARE_DIR"

    echo -n "Masukkan ID owner utama (angka): "
    read -r OWNER_ID
    if ! [[ "$OWNER_ID" =~ ^[0-9]+$ ]]; then
        echo "Owner ID harus angka." >&2
        exit 1
    fi

    echo "[2/8] Backing up Kernel and routes..."
    backup_file "$KERNEL"
    for f in "$ROUTES_DIR"/*.php; do
        backup_file "$f"
    done

    echo "[3/8] Creating WhitelistAdmin middleware..."
    cat > "$MIDDLEWARE_ADMIN" <<EOF
<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

class WhitelistAdmin
{
    public function handle(Request \$request, Closure \$next)
    {
        \$allowedAdmins = [$OWNER_ID];

        if (!\$request->user() || !in_array(\$request->user()->id, \$allowedAdmins)) {
            abort(403, 'ngapain wok');
        }

        return \$next(\$request);
    }
}
EOF

    echo "[4/8] Creating ClientLock middleware..."
    cat > "$MIDDLEWARE_CLIENT" <<'EOF'
<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

class ClientLock
{
    public function handle(Request $request, Closure $next)
    {
        $allowedAdmins = [__OWNERS__];
        $user = $request->user();

        if (!$user) {
            abort(403, 'ngapain wok');
        }

        // Root/admins (if using root_admin flag) bypass
        if (isset($user->root_admin) && $user->root_admin) {
            return $next($request);
        }

        // If route has a server parameter, enforce owner check
        $server = $request->route('server');
        if ($server) {
            $ownerId = $server->owner_id ?? null;
            if ($ownerId === null || $ownerId != $user->id) {
                abort(403, 'ngapain wok');
            }
        }

        return $next($request);
    }
}
EOF

    # Insert owners into created file
    sed -i "s/__OWNERS__/$OWNER_ID/" "$MIDDLEWARE_CLIENT"

    echo "[5/8] Registering middleware aliases in Kernel..."
    if ! grep -q "clientlock" "$KERNEL"; then
        sed -i "/protected \$middlewareAliases = \[/a\        'clientlock' => App\\\Http\\\Middleware\\\ClientLock::class," "$KERNEL"
    fi
    if ! grep -q "whitelistadmin" "$KERNEL"; then
        sed -i "/protected \$middlewareAliases = \[/a\        'whitelistadmin' => App\\\Http\\\Middleware\\\WhitelistAdmin::class," "$KERNEL"
    fi

    echo "[6/8] Patching routes safely (api-client: attach clientlock to servers routes)..."
    # Apply clientlock to any route files that declare prefix => '/servers' or '/servers/{server}'
    FOUND=0
    for rf in "$ROUTES_DIR"/*.php; do
        if grep -q "['\"]prefix['\"]\s*=>\s*['\"]/servers" "$rf"; then
            # Only add if not already containing clientlock in middleware array for that group
            if grep -q "prefix' => '/servers" "$rf" && ! grep -q "clientlock" "$rf"; then
                # Try safe replace for both prefix patterns
                if grep -q "['\"]prefix['\"]\s*=>\s*['\"]/servers/\{server\}" "$rf"; then
                    sed -i "s/\(['\"]prefix['\"]\s*=>\s*['\"]\/servers\/{server}['\"]\s*,\s*\)/\1'middleware' => ['clientlock'], /" "$rf" || true
                fi
                if grep -q "['\"]prefix['\"]\s*=>\s*['\"]\/servers['\"]" "$rf"; then
                    sed -i "s/\(['\"]prefix['\"]\s*=>\s*['\"]\/servers['\"]\s*,\s*\)/\1'middleware' => ['clientlock'], /" "$rf" || true
                fi
            fi
            FOUND=1
        fi
    done

    if [ "$FOUND" -eq 0 ]; then
        echo "Warning: no '/servers' prefix found in routes. ClientLock not attached to any route automatically."
    fi

    echo "[7/8] Protecting admin route groups in admin.php (safe)..."
    ADMIN_ROUTE_FILE="$ROUTES_DIR/admin.php"
    if [ -f "$ADMIN_ROUTE_FILE" ]; then
        # Add whitelistadmin to common admin prefixes if present
        for prefix in nodes locations databases mounts nests; do
            if grep -q "['\"]prefix['\"]\s*=>\s*['\"]/$prefix['\"]" "$ADMIN_ROUTE_FILE" && ! grep -q "whitelistadmin" "$ADMIN_ROUTE_FILE"; then
                sed -i "s/\(['\"]prefix['\"]\s*=>\s*'\/$prefix'\s*,\s*\)/\1'middleware' => ['whitelistadmin'], /" "$ADMIN_ROUTE_FILE" || true
            fi
        done
    fi

    echo "[8/8] Clearing caches and restarting queue worker..."
    cd "$PTERO"
    php artisan route:clear || true
    php artisan cache:clear || true
    php artisan config:clear || true
    php artisan view:clear || true
    systemctl restart pteroq || true

    echo "Install complete. Owner ID set to: $OWNER_ID"
    echo "To add more owners use the script menu (choose Add Owner)."
}

add_owner() {
    if [ ! -f "$MIDDLEWARE_ADMIN" ]; then
        echo "WhitelistAdmin middleware not found. Run install first." >&2
        return 1
    fi
    echo -n "Masukkan ID owner baru: "
    read -r NEW
    if ! [[ "$NEW" =~ ^[0-9]+$ ]]; then
        echo "Owner ID harus angka." >&2
        return 1
    fi
    CUR=$(get_owners_from_file)
    if [ -z "$CUR" ]; then
        NEWLIST="$NEW"
    else
        # prevent duplicates
        if echo ",$CUR," | grep -q ",$NEW,"; then
            echo "Owner $NEW sudah ada."
            return 0
        fi
        NEWLIST="$CUR,$NEW"
    fi
    save_owners_to_files "$NEWLIST"
    echo "Owner $NEW ditambahkan."
    cd "$PTERO"
    php artisan route:clear || true
}

delete_owner() {
    if [ ! -f "$MIDDLEWARE_ADMIN" ]; then
        echo "WhitelistAdmin middleware not found. Run install first." >&2
        return 1
    fi
    echo -n "Masukkan ID owner yang ingin dihapus: "
    read -r DEL
    if ! [[ "$DEL" =~ ^[0-9]+$ ]]; then
        echo "Owner ID harus angka." >&2
        return 1
    fi
    CUR=$(get_owners_from_file)
    if [ -z "$CUR" ]; then
        echo "Tidak ada owner tersimpan."
        return 1
    fi
    # remove exact match entries
    NEW=$(echo "$CUR" | awk -v RS=, -v ORS=, '$0 != "'$DEL'"' | sed 's/,$//;s/^,//')
    if [ -z "$NEW" ]; then
        # empty -> make it blank
        NEW=""
    fi
    save_owners_to_files "$NEW"
    echo "Owner $DEL dihapus."
    cd "$PTERO"
    php artisan route:clear || true
}

uninstall() {
    echo "UNINSTALL: akan menghapus middleware custom, patch route, dan entries di Kernel."
    read -p "Yakin ingin uninstall Antirusuh? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "Batal uninstall."
        return 0
    fi

    echo "[1/6] Removing middleware files..."
    rm -f "$MIDDLEWARE_ADMIN" || true
    rm -f "$MIDDLEWARE_CLIENT" || true

    echo "[2/6] Removing middleware aliases from Kernel..."
    if [ -f "$KERNEL" ]; then
        sed -i "/'clientlock' =>/d" "$KERNEL" || true
        sed -i "/'whitelistadmin' =>/d" "$KERNEL" || true
    fi

    echo "[3/6] Removing clientlock from routes..."
    # revert any clientlock middleware in routes safely
    for rf in "$ROUTES_DIR"/*.php; do
        if [ -f "$rf" ]; then
            # remove 'clientlock', occurrences inside middleware arrays
            sed -i "s/'clientlock',\s*//g" "$rf" || true
            sed -i "s/,\s*'clientlock'//g" "$rf" || true
            sed -i "s/'middleware'\s*=>\s*\[\s*\]/'middleware' => []/g" "$rf" || true
        fi
    done

    echo "[4/6] Removing whitelistadmin from admin routes..."
    ADMIN_ROUTE_FILE="$ROUTES_DIR/admin.php"
    if [ -f "$ADMIN_ROUTE_FILE" ]; then
        sed -i "s/'middleware' => \['whitelistadmin'\],\s*//g" "$ADMIN_ROUTE_FILE" || true
        sed -i "s/'middleware' => \['whitelistadmin'\]//g" "$ADMIN_ROUTE_FILE" || true
    fi

    echo "[5/6] Removing inline protections from controllers..."
    # remove inserted 'ngapain wok' checks from controllers
    if [ -f "$USER_CONTROLLER" ]; then
        sed -i "/ngapain wok/d" "$USER_CONTROLLER" || true
    fi
    if [ -d "$SERVER_CONTROLLERS_DIR" ]; then
        for f in "$SERVER_CONTROLLERS_DIR"/*.php; do
            sed -i "/ngapain wok/d" "$f" || true
        done
    fi

    echo "[6/6] Clearing caches and restarting..."
    cd "$PTERO"
    php artisan route:clear || true
    php artisan cache:clear || true
    php artisan config:clear || true
    php artisan view:clear || true
    systemctl restart pteroq || true

    echo "Uninstall complete. Middleware and route patches removed."
}

show_menu() {
    while true; do
        cat <<'MENU'

Antirusuh installer — menu
1) Install Antirusuh (create middleware, attach clientlock)
2) Add Owner
3) Delete Owner
4) Uninstall Antirusuh
5) Exit

MENU
        printf "Pilih: "
        read -r CH
        case "$CH" in
            1) install ;;
            2) add_owner ;;
            3) delete_owner ;;
            4) uninstall ;;
            5) exit 0 ;;
            *) echo "Pilihan tidak valid." ;;
        esac
    done
}

# If script called with arguments, allow direct commands
case "${1-}" in
    install) install; exit 0 ;;
    add_owner) add_owner; exit 0 ;;
    delete_owner) delete_owner; exit 0 ;;
    uninstall) uninstall; exit 0 ;;
    "" ) show_menu ;;
    * ) show_menu ;;
esac
