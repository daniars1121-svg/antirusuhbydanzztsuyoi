#!/usr/bin/env bash
set -euo pipefail

# ANTIRUSUH INSTALLER (PERBAIKAN SAFE)
# Simpan sebagai /usr/local/bin/antirusuh_fix.sh lalu chmod +x

PTERO="${PTERO:-/var/www/pterodactyl}"
TIMESTAMP="$(date +%s)"
BACKDIR="$PTERO/antirusuh_backup_$TIMESTAMP"

ADMIN_MW="$PTERO/app/Http/Middleware/WhitelistAdmin.php"
CLIENT_MW="$PTERO/app/Http/Middleware/ClientLock.php"
KERNEL="$PTERO/app/Http/Kernel.php"
ADMIN_ROUTES="$PTERO/routes/admin.php"
API_CLIENT="$PTERO/routes/api-client.php"
SERVERCTL="$PTERO/app/Http/Controllers/Admin/Servers"
USERCTL="$PTERO/app/Http/Controllers/Admin/UserController.php"

# Utility
backup_file() {
    local f="$1"
    mkdir -p "$BACKDIR"
    if [ -f "$f" ]; then
        cp -a "$f" "$BACKDIR/$(basename "$f").bak_$TIMESTAMP"
    fi
}

backup_all() {
    echo "[*] Membuat backup cadangan ke: $BACKDIR"
    mkdir -p "$BACKDIR"
    for f in "$KERNEL" "$ADMIN_ROUTES" "$API_CLIENT" "$USERCTL"; do
        [ -f "$f" ] && cp -a "$f" "$BACKDIR/$(basename "$f")"
    done
    [ -d "$SERVERCTL" ] && cp -a "$SERVERCTL" "$BACKDIR/"
}

# Insert line(s) before the closing "];" of an array (used for Kernel)
insert_before_closing_array() {
    local file="$1"; shift
    local insert_text="$*"
    awk -v ins="$insert_text" '
    BEGIN {printed=0}
    {
      print $0
      if (!printed && $0 ~ /^\s*\];\s*$/) {
        print ins
        printed=1
      }
    }
    ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}

# Check if a PHP file already contains a pattern
contains() {
    local file="$1"; shift
    local pat="$*"
    grep -q -- "$pat" "$file" 2>/dev/null
}

#######################
# Install / Fix Flow
#######################
main_install() {
    if [ ! -d "$PTERO" ]; then
        echo "ERROR: Folder Pterodactyl tidak ditemukan di $PTERO"
        exit 1
    fi

    echo "[*] Backup sebelum perubahan..."
    backup_all

    # 1) Create middleware files (safe, with namespace matching Pterodactyl structure)
    echo "[*] Membuat middleware..."

    # WhitelistAdmin (admin-area)
    if ! contains "$ADMIN_MW" "class WhitelistAdmin"; then
        backup_file "$ADMIN_MW"
        cat > "$ADMIN_MW" <<'PHP'
<?php
namespace Pterodactyl\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

class WhitelistAdmin
{
    public function handle(Request $request, Closure $next)
    {
        // daftar owner default diisi oleh installer
        // installer akan mengganti TOKEN_OWNER_PLACEHOLDER ke angka ID owner
        $allowed = [TOKEN_OWNER_PLACEHOLDER];

        $user = $request->user();
        if (!$user || !in_array($user->id, $allowed)) {
            abort(403, 'ngapain wok');
        }

        return $next($request);
    }
}
PHP
        echo "[+] WhitelistAdmin dibuat: $ADMIN_MW"
    else
        echo "[i] WhitelistAdmin sudah ada, skip pembuatan."
    fi

    # ClientLock (protect individual server)
    if ! contains "$CLIENT_MW" "class ClientLock"; then
        backup_file "$CLIENT_MW"
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
        // daftar owner default diisi oleh installer
        $allowed = [TOKEN_OWNER_PLACEHOLDER];

        $user = $request->user();
        if (!$user) {
            abort(403, 'ngapain wok');
        }

        // if owner -> allow
        if (in_array($user->id, $allowed)) {
            return $next($request);
        }

        // check route parameter server -> ensure owner
        $server = $request->route('server');
        if ($server && isset($server->owner_id) && $server->owner_id != $user->id) {
            abort(403, 'ngapain wok');
        }

        return $next($request);
    }
}
PHP
        echo "[+] ClientLock dibuat: $CLIENT_MW"
    else
        echo "[i] ClientLock sudah ada, skip pembuatan."
    fi

    # 2) Ask for owner ID (must be number)
    read -p "Masukkan ID Owner utama (angka): " OWNER_ID
    if ! [[ "$OWNER_ID" =~ ^[0-9]+$ ]]; then
        echo "ID owner harus angka. Batal."
        exit 1
    fi

    # replace placeholder token in files
    sed -i "s/TOKEN_OWNER_PLACEHOLDER/$OWNER_ID/g" "$ADMIN_MW" "$CLIENT_MW"

    # 3) Register middleware di Kernel (dengan aman: jangan duplikat)
    echo "[*] Mendaftarkan middleware di Kernel..."
    if ! contains "$KERNEL" "whitelistadmin' =>"; then
        # insert before closing array of middlewareAliases
        insert_before_closing_array "$KERNEL" "        'whitelistadmin' => \\Pterodactyl\\Http\\Middleware\\WhitelistAdmin::class,\n        'clientlock' => \\App\\Http\\Middleware\\ClientLock::class,"
        echo "[+] Middleware terdaftar di $KERNEL"
    else
        echo "[i] Middleware sudah terdaftar di Kernel, skip."
    fi

    # 4) Protect admin routes:
    # Wrap entire admin.php inside Route::middleware(['whitelistadmin'])->group(function () { ... });
    echo "[*] Membungkus routes/admin.php dengan whitelistadmin (safe wrapper)..."
    if ! contains "$ADMIN_ROUTES" "Route::middleware(['whitelistadmin'])->group"; then
        backup_file "$ADMIN_ROUTES"
        # find the position after the last use ...; line (we'll insert wrapper after use statements)
        awk '
        BEGIN{ inserted=0 }
        {
            print $0
            if(!inserted && /^\\s*Route::get\\(/) {
                print ""
                print "Route::middleware([\\'whitelistadmin\\'])->group(function () {"
                inserted=1
            }
        }
        END{
            if(inserted){
                # add closing bracket at end
            }
        }' "$ADMIN_ROUTES" > "$ADMIN_ROUTES.tmp"
        # append closing "});" at end
        printf "\n});\n" >> "$ADMIN_ROUTES.tmp"
        mv "$ADMIN_ROUTES.tmp" "$ADMIN_ROUTES"
        echo "[+] admin.php dibungkus. Backup di $BACKDIR/$(basename "$ADMIN_ROUTES")"
    else
        echo "[i] admin.php sudah dibungkus, skip."
    fi

    # 5) Ensure api-client servers group is protected with clientlock
    echo "[*] Memodifikasi $API_CLIENT untuk menambahkan middleware clientlock pada route /servers/{server} (jika perlu)..."
    if [ -f "$API_CLIENT" ]; then
        backup_file "$API_CLIENT"
        # attempt safe replace: add 'middleware' => ['clientlock'], inside array header if not present
        # Only operate if the exact prefix exists and middleware not present
        if grep -q "'prefix' => '/servers/{server}'" "$API_CLIENT" && ! grep -q "clientlock" "$API_CLIENT"; then
            # replace the array header line (single-line or multi-line)
            perl -0777 -pe "s/(\\'prefix\\'\\s*=>\\s*\\'\\/servers\\/\\{server\\}\\'\\s*,?)/\\\$1 'middleware' => ['clientlock'],/s" "$API_CLIENT" > "$API_CLIENT.tmp" && mv "$API_CLIENT.tmp" "$API_CLIENT"
            echo "[+] $API_CLIENT updated to include clientlock"
        else
            echo "[i] $API_CLIENT already contains clientlock or prefix not found - skip."
        fi
    else
        echo "[!] $API_CLIENT not found, skip."
    fi

    # 6) Protect delete functions in controllers (simple insertion after "public function delete")
    echo "[*] Menambahkan pengecekan di fungsi delete pada controller admin (user + servers)..."
    # function to inject check only if not present
    inject_delete_check() {
        local file="$1"
        [ -f "$file" ] || return
        if ! grep -q "ngapain wok" "$file"; then
            cp "$file" "$file.bak_autofix_$TIMESTAMP"
            # insert check after function delete signature's opening brace
            perl -0777 -pe '
                s/(public function delete[^{]*\{)/$1\n        $allowed = ['$OWNER_ID'];\n        if(!auth()->user() || !in_array(auth()->user()->id, $allowed)) abort(403, "ngapain wok");/s
            ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
            echo "[+] Injected delete-check into $file"
        else
            echo "[i] Skip inject for $file (delete-check already present)"
        fi
    }

    inject_delete_check "$USERCTL"
    if [ -d "$SERVERCTL" ]; then
        for f in "$SERVERCTL"/*.php; do
            inject_delete_check "$f"
        done
    fi

    # 7) Clear caches and restart queue process
    echo "[*] Membersihkan cache artisan dan merestart pteroq..."
    cd "$PTERO" || true
    php artisan route:clear || true
    php artisan cache:clear || true
    php artisan config:clear || true

    # restart pteroq service if available
    if systemctl list-units --type=service --all | grep -q pteroq; then
        systemctl restart pteroq || true
    fi

    echo "======================================"
    echo " Antirusuh dipasang / diperbaiki (backup: $BACKDIR)"
    echo " Coba login non-owner dan akses admin/nodes/servers untuk tes."
    echo "======================================"
}

# Simple uninstall (restore backups created by installer)
main_uninstall() {
    echo "[*] Restore dari backup di $BACKDIR jika ada..."
    if [ -d "$BACKDIR" ]; then
        cp -a "$BACKDIR/"* "$PTERO/" || true
        echo "[+] Restore selesai (cek file pada $PTERO)"
    else
        echo "[!] Tidak ada backup otomatis ditemukan di $BACKDIR"
    fi
    echo "[*] Hapus middleware dari Kernel (manual) jika perlu."
    echo "Selesai."
}

# Menu CLI
case "${1:-}" in
    uninstall)
        main_uninstall
        ;;
    *)
        main_install
        ;;
esac
