#!/usr/bin/env bash
set -euo pipefail

PTERO="/var/www/pterodactyl"
KERNEL="$PTERO/app/Http/Kernel.php"
MIDDLEWARE_DIR="$PTERO/app/Http/Middleware"
MW_ADMIN="$PTERO/app/Http/Middleware/WhitelistAdmin.php"
MW_CLIENT="$PTERO/app/Http/Middleware/ClientLock.php"
ROUTES_DIR="$PTERO/routes"
ADMIN_ROUTES="$ROUTES_DIR/admin.php"
API_CLIENT="$ROUTES_DIR/api-client.php"
USERCTL="$PTERO/app/Http/Controllers/Admin/UserController.php"
SERVERCTL_DIR="$PTERO/app/Http/Controllers/Admin/Servers"
BACKUP_DIR="$PTERO/antirusuh_backups_$(date +%s)"

mkdir -p "$BACKUP_DIR"
mkdir -p "$MIDDLEWARE_DIR"

backup() {
    local f="$1"
    if [ -f "$f" ]; then
        cp -a "$f" "$BACKUP_DIR/$(basename "$f").bak" || true
    fi
}

backup_all() {
    backup "$KERNEL"
    backup "$ADMIN_ROUTES"
    backup "$API_CLIENT"
    backup "$USERCTL"
    if [ -d "$SERVERCTL_DIR" ]; then
        for f in "$SERVERCTL_DIR"/*.php; do
            backup "$f"
        done
    fi
}

# read owners from WhitelistAdmin (comma separated)
get_owners() {
    if [ -f "$MW_ADMIN" ]; then
        grep "\$allowedAdmins" "$MW_ADMIN" 2>/dev/null | sed -E "s/.*\[(.*)\].*/\1/" | tr -d ' ' || true
    else
        echo ""
    fi
}

# save owner list into both middleware files (if present)
save_owners() {
    local owners="$1"
    if [ -f "$MW_ADMIN" ]; then
        sed -i "s/\\\$allowedAdmins = \\[.*\\];/\\\$allowedAdmins = [$owners];/" "$MW_ADMIN"
    fi
    if [ -f "$MW_CLIENT" ]; then
        sed -i "s/\\\$allowedAdmins = \\[.*\\];/\\\$allowedAdmins = [$owners];/" "$MW_CLIENT"
    fi
}

install_antirusuh() {
    echo "== Install AntiRusuh =="
    read -p "Masukkan ID Owner utama (angka): " OWNER_ID
    if ! [[ "$OWNER_ID" =~ ^[0-9]+$ ]]; then
        echo "Owner ID harus angka."
        return 1
    fi

    echo "Backup files ke: $BACKUP_DIR"
    backup_all

    echo "Membuat WhitelistAdmin (namespace Pterodactyl\Http\Middleware)..."
    cat > "$MW_ADMIN" <<EOF
<?php

namespace Pterodactyl\Http\Middleware;

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

    echo "Membuat ClientLock (namespace App\Http\Middleware)..."
    cat > "$MW_CLIENT" <<'EOF'
<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

class ClientLock
{
    public function handle(Request $request, Closure $next)
    {
        // daftar owner akan di-replace saat install
        $allowedAdmins = [__OWNERS__];

        $user = $request->user();
        if (!$user) {
            // tidak terautentikasi -> blok (API client harus terautentikasi)
            abort(403, 'ngapain wok');
        }

        // jika user termasuk owner -> jangan batasi
        if (in_array($user->id, $allowedAdmins)) {
            return $next($request);
        }

        // hanya beraksi pada API client servers (atau bila route punya parameter 'server')
        // cek route parameter 'server'
        $server = $request->route('server');
        if ($server) {
            $ownerId = $server->owner_id ?? null;
            if ($ownerId === null || $ownerId != $user->id) {
                abort(403, 'ngapain wok');
            }
            return $next($request);
        }

        // fallback: jika URI mengandung /api/client/servers -> blok
        $uri = $request->getRequestUri();
        if (strpos($uri, '/api/client/servers') === 0 || strpos($uri, '/api/client/servers') !== false) {
            abort(403, 'ngapain wok');
        }

        return $next($request);
    }
}
EOF

    # insert owner into client file
    sed -i "s/__OWNERS__/$OWNER_ID/" "$MW_CLIENT"

    # register aliases in Kernel if not present
    if ! grep -q "whitelistadmin" "$KERNEL"; then
        echo "Menambahkan alias whitelistadmin ke Kernel..."
        sed -i "/protected \$middlewareAliases = \[/a\        'whitelistadmin' => \\\\Pterodactyl\\\\Http\\\\Middleware\\\\WhitelistAdmin::class," "$KERNEL"
    fi
    if ! grep -q "clientlock" "$KERNEL"; then
        echo "Menambahkan alias clientlock ke Kernel..."
        sed -i "/protected \$middlewareAliases = \[/a\        'clientlock' => \\\\App\\\\Http\\\\Middleware\\\\ClientLock::class," "$KERNEL"
    fi

    # add ClientLock class to middleware group 'api' if not already present
    if grep -q "protected \\$middlewareGroups" "$KERNEL"; then
        if ! grep -q "App\\\\Http\\\\Middleware\\\\ClientLock::class" "$KERNEL"; then
            # insert after the 'api' => [ line, put under it
            awk -v added=0 '
            BEGIN{inapi=0}
            /protected \$middlewareGroups/ {print; next}
            {
              if ($0 ~ /\x27api\x27\s*=>\s*\[/ && !added) {
                  print $0
                  # print next lines until find the closing ]
                  getline
                  print $0
                  # insert our middleware after this line
                  print "            App\\\\\\Http\\\\\\Middleware\\\\ClientLock::class,"
                  added=1
                  next
              }
              print
            }' "$KERNEL" > "$KERNEL.tmp" && mv "$KERNEL.tmp" "$KERNEL"
        fi
    fi

    # Attach whitelistadmin to admin route groups (safe: only if admin.php exists)
    if [ -f "$ADMIN_ROUTES" ]; then
        for prefix in nodes locations databases mounts nests; do
            # only add if prefix exists and whitelistadmin not already in that group
            if grep -q "['\"]prefix['\"]\s*=>\s*['\"]/$prefix['\"]" "$ADMIN_ROUTES" && ! grep -q "whitelistadmin" "$ADMIN_ROUTES"; then
                echo "Menambahkan whitelistadmin di admin.php untuk prefix /$prefix"
                sed -i "s/\(['\"]prefix['\"]\s*=>\s*'\/$prefix'\s*,\s*\)/\1'middleware' => ['whitelistadmin'], /" "$ADMIN_ROUTES" || true
            fi
        done
    fi

    # Insert inline protections into controllers (guarded, avoid duplicates)
    if [ -f "$USERCTL" ]; then
        if ! grep -q "ANTI_RUSUH_CHECK" "$USERCTL"; then
            sed -i "/public function delete/!b;n;/}/i\        // ANTI_RUSUH_CHECK\n        \$allowedAdmins = [$OWNER_ID];\n        if (!in_array(auth()->user()->id, \$allowedAdmins)) abort(403,'ngapain wok');" "$USERCTL" || true
        fi
    fi

    if [ -d "$SERVERCTL_DIR" ]; then
        for f in "$SERVERCTL_DIR"/*.php; do
            if [ -f "$f" ] && ! grep -q "ANTI_RUSUH_CHECK" "$f"; then
                sed -i "/public function delete/!b;n;/}/i\        // ANTI_RUSUH_CHECK\n        \$allowedAdmins = [$OWNER_ID];\n        if (!in_array(auth()->user()->id, \$allowedAdmins)) abort(403,'ngapain wok');" "$f" || true
                sed -i "/public function destroy/!b;n;/}/i\        // ANTI_RUSUH_CHECK\n        \$allowedAdmins = [$OWNER_ID];\n        if (!in_array(auth()->user()->id, \$allowedAdmins)) abort(403,'ngapain wok');" "$f" || true
                sed -i "/public function view/!b;n;/}/i\        // ANTI_RUSUH_CHECK\n        \$allowedAdmins = [$OWNER_ID];\n        if (!in_array(auth()->user()->id, \$allowedAdmins)) abort(403,'ngapain wok');" "$f" || true
                sed -i "/public function details/!b;n;/}/i\        // ANTI_RUSUH_CHECK\n        \$allowedAdmins = [$OWNER_ID];\n        if (!in_array(auth()->user()->id, \$allowedAdmins)) abort(403,'ngapain wok');" "$f" || true
            fi
        done
    fi

    # clear caches
    cd "$PTERO"
    php artisan route:clear || true
    php artisan config:clear || true
    php artisan cache:clear || true
    php artisan view:clear || true
    systemctl restart pteroq || true

    echo "Install selesai. Owner: $OWNER_ID"
    echo "Backups ada di: $BACKUP_DIR"
}

add_owner() {
    if [ ! -f "$MW_ADMIN" ]; then
        echo "Middleware belum terpasang. Jalankan install dulu."
        return 1
    fi
    read -p "Masukkan ID Owner baru: " NEW
    if ! [[ "$NEW" =~ ^[0-9]+$ ]]; then echo "ID harus angka"; return 1; fi

    CUR=$(get_owners)
    if [ -z "$CUR" ]; then NEWLIST="$NEW"; else
        case ",$CUR," in
            *,"$NEW",*) echo "Owner sudah ada"; return 0 ;;
            *) NEWLIST="$CUR,$NEW" ;;
        esac
    fi

    save_owners "$NEWLIST"
    # update client file owners if present
    if [ -f "$MW_CLIENT" ]; then
        sed -i "s/\$allowedAdmins = \[.*\];/\$allowedAdmins = [$NEWLIST];/" "$MW_CLIENT" || true
    fi
    php artisan route:clear || true
    echo "Owner $NEW ditambahkan."
}

delete_owner() {
    if [ ! -f "$MW_ADMIN" ]; then
        echo "Middleware belum terpasang."
        return 1
    fi
    read -p "Masukkan ID Owner yang ingin dihapus: " DEL
    if ! [[ "$DEL" =~ ^[0-9]+$ ]]; then echo "ID harus angka"; return 1; fi

    CUR=$(get_owners)
    if [ -z "$CUR" ]; then echo "Tidak ada owner tersimpan"; return 1; fi

    NEW=$(echo ",$CUR," | sed "s/,$DEL,/,/g" | sed 's/^,//;s/,$//')
    save_owners "$NEW"
    if [ -f "$MW_CLIENT" ]; then
        sed -i "s/\$allowedAdmins = \[.*\];/\$allowedAdmins = [$NEW];/" "$MW_CLIENT" || true
    fi
    php artisan route:clear || true
    echo "Owner $DEL dihapus."
}

uninstall_antirusuh() {
    read -p "Yakin uninstall AntiRusuh? (y/N): " CONF
    if [ "$CONF" != "y" ] && [ "$CONF" != "Y" ]; then
        echo "Dibatalkan."
        return 0
    fi

    echo "Backup sebelum hapus ada di: $BACKUP_DIR (jika ada)"
    rm -f "$MW_ADMIN" || true
    rm -f "$MW_CLIENT" || true

    # remove aliases from Kernel
    if [ -f "$KERNEL" ]; then
        sed -i "/whitelistadmin/d" "$KERNEL" || true
        sed -i "/clientlock/d" "$KERNEL" || true
        # remove clientlock class from middlewareGroups 'api' if present
        sed -i "s/App\\\\\\Http\\\\\\Middleware\\\\ClientLock::class,//g" "$KERNEL" || true
    fi

    # remove clientlock usages in routes (best-effort)
    for rf in "$ROUTES_DIR"/*.php; do
        if [ -f "$rf" ]; then
            sed -i "s/'clientlock',\s*//g" "$rf" || true
            sed -i "s/'middleware' => \['clientlock'\],\s*//g" "$rf" || true
            sed -i "s/'middleware' => \['clientlock',\s*//g" "$rf" || true
            sed -i "s/'middleware' => \['clientlock'\]//g" "$rf" || true
        fi
    done

    # remove inline protections
    if [ -f "$USERCTL" ]; then
        sed -i "/ANTI_RUSUH_CHECK/,+2d" "$USERCTL" || true
        sed -i "/ngapain wok/d" "$USERCTL" || true
    fi
    if [ -d "$SERVERCTL_DIR" ]; then
        for f in "$SERVERCTL_DIR"/*.php; do
            sed -i "/ANTI_RUSUH_CHECK/,+2d" "$f" || true
            sed -i "/ngapain wok/d" "$f" || true
        done
    fi

    php artisan route:clear || true
    php artisan cache:clear || true
    php artisan config:clear || true
    php artisan view:clear || true
    systemctl restart pteroq || true

    echo "Uninstall selesai."
    echo "Jika perlu, restore backups dari $BACKUP_DIR manually."
}

menu() {
    while true; do
        cat <<'MENU'

Antirusuh — Menu
1) Install AntiRusuh danzz
2) Add Owner
3) Delete Owner
4) Uninstall AntiRusuh
5) Exit

MENU
        read -p "Pilih: " CH
        case "$CH" in
            1) install_antirusuh ;;
            2) add_owner ;;
            3) delete_owner ;;
            4) uninstall_antirusuh ;;
            5) exit 0 ;;
            *) echo "Pilihan tidak valid." ;;
        esac
    done
}

# run menu if script executed directly
menu
