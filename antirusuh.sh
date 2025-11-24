#!/usr/bin/env bash
set -euo pipefail

PTERO="/var/www/pterodactyl"

ADMIN_MW="$PTERO/app/Http/Middleware/WhitelistAdmin.php"
CLIENT_MW="$PTERO/app/Http/Middleware/ClientLock.php"
KERNEL="$PTERO/app/Http/Kernel.php"
API_CLIENT="$PTERO/routes/api-client.php"
BACKUP_DIR="$PTERO/antirusuh_backup"

banner() {
    cat <<'EOF'
=======================================
   ANTI RUSUH UNIVERSAL - INSTALLER
=======================================
EOF
}

ensure_paths() {
    if [ ! -d "$PTERO" ]; then
        echo "ERROR: PTERO path $PTERO tidak ditemukan. Ubah variabel PTERO di skrip."
        exit 1
    fi
    mkdir -p "$BACKUP_DIR"
}

backup_file() {
    local f="$1"
    if [ -f "$f" ]; then
        cp -a "$f" "$BACKUP_DIR/$(basename "$f").bak.$(date +%s)"
    fi
}

write_whitelist_middleware() {
    local owner_ids="$1"
    cat > "$ADMIN_MW" <<EOF
<?php
namespace Pterodactyl\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

class WhitelistAdmin
{
    /**
     * \$ownerIds should be an array of integer IDs inserted by installer.
     */
    public function handle(Request \$request, Closure \$next)
    {
        \$ownerIds = [$owner_ids];
        // Only enforce for admin area (prefix 'admin')
        \$path = ltrim(\$request->path(), '/'); // e.g. "admin/nodes"
        if (strpos(\$path, 'admin') === 0) {
            \$u = \$request->user();
            if (!\$u || !in_array(\$u->id, \$ownerIds)) {
                abort(403, 'ngapain wok');
            }
        }

        return \$next(\$request);
    }
}
EOF
    chmod 644 "$ADMIN_MW"
}

write_clientlock_middleware() {
    local owner_ids="$1"
    cat > "$CLIENT_MW" <<EOF
<?php
namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

class ClientLock
{
    public function handle(Request \$request, Closure \$next)
    {
        \$ownerIds = [$owner_ids];
        \$u = \$request->user();
        if (!\$u) {
            abort(403, 'ngapain wok');
        }

        // owners bypass
        if (in_array(\$u->id, \$ownerIds)) {
            return \$next(\$request);
        }

        // If route provides a server, allow only owner or subusers handled by existing controllers
        \$srv = null;
        try {
            \$srv = \$request->route('server');
        } catch (\Exception \$e) {
            // ignore, route param not present
        }

        if (\$srv && isset(\$srv->owner_id) && \$srv->owner_id != \$u->id) {
            abort(403, 'ngapain wok');
        }

        return \$next(\$request);
    }
}
EOF
    chmod 644 "$CLIENT_MW"
}

add_kernel_aliases_and_web_group() {
    # Add middleware alias if not present
    if ! grep -q "whitelistadmin" "$KERNEL" 2>/dev/null; then
        backup_file "$KERNEL"
        # add alias line after "protected \$middlewareAliases = [" line
        sed -i "/protected \$middlewareAliases\s*=\s*\[/a\        'whitelistadmin' => \\\\Pterodactyl\\\\Http\\\\Middleware\\\\WhitelistAdmin::class," "$KERNEL"
        echo "Added 'whitelistadmin' alias to Kernel.php"
    else
        echo "Kernel already contains 'whitelistadmin' alias — skipping."
    fi

    if ! grep -q "clientlock" "$KERNEL" 2>/dev/null; then
        backup_file "$KERNEL"
        sed -i "/protected \$middlewareAliases\s*=\s*\[/a\        'clientlock' => \\\\App\\\\Http\\\\Middleware\\\\ClientLock::class," "$KERNEL"
        echo "Added 'clientlock' alias to Kernel.php"
    else
        echo "Kernel already contains 'clientlock' alias — skipping."
    fi

    # Add WhitelistAdmin into 'web' middleware group (only once).
    # We will insert fully-qualified class in web group array, not the alias, to be robust.
    if ! grep -q "Pterodactyl\\\\Http\\\\Middleware\\\\WhitelistAdmin::class" "$KERNEL" 2>/dev/null; then
        backup_file "$KERNEL"
        # insert after the opening of 'web' => [
        # Use awk to place after the 'web' => [ line block header
        awk 'BEGIN{p=1} /'\''web'\''\s*=>\s*\[/ && p==1 {print; getline; print; print "            \\\\Pterodactyl\\\\Http\\\\Middleware\\\\WhitelistAdmin::class,"; p=0; next} {print}' "$KERNEL" > "$KERNEL.tmp" && mv "$KERNEL.tmp" "$KERNEL"
        echo "Inserted WhitelistAdmin into 'web' middleware group"
    else
        echo "WhitelistAdmin already present in web group — skipping."
    fi
}

add_clientlock_to_api_client() {
    if [ ! -f "$API_CLIENT" ]; then
        echo "api-client route file not found at $API_CLIENT — skipping clientlock insertion."
        return
    fi

    # If already contains 'clientlock' skip
    if grep -q "clientlock" "$API_CLIENT"; then
        echo "api-client already references clientlock — skipping."
        return
    fi

    backup_file "$API_CLIENT"

    # We want to add 'clientlock' next to AuthenticateServerAccess::class in the server group.
    # We'll replace the first occurrence of "AuthenticateServerAccess::class," with "AuthenticateServerAccess::class, 'clientlock',"
    # but only if that token exists.
    if grep -q "AuthenticateServerAccess::class" "$API_CLIENT"; then
        sed -i "0,/AuthenticateServerAccess::class/ s//AuthenticateServerAccess::class, 'clientlock'/" "$API_CLIENT" || true
        echo "Added clientlock to api-client route group (if matched)."
    else
        echo "AuthenticateServerAccess::class not found in api-client — skipping."
    fi
}

clear_laravel_cache() {
    # run artisan clear commands if available
    if [ -d "$PTERO" ] && [ -f "$PTERO/artisan" ]; then
        cd "$PTERO"
        php artisan route:clear || true
        php artisan config:clear || true
        php artisan cache:clear || true
    fi
    # restart pteroq if systemctl available
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart pteroq 2>/dev/null || true
    fi
}

install_flow() {
    banner
    read -p "Masukkan ID Owner Utama (angka, bisa lebih dari 1 pisah koma): " OWNER
    # sanitize owner list: remove spaces
    OWNER=$(echo "$OWNER" | tr -d ' ')
    if [ -z "$OWNER" ]; then
        echo "Owner ID kosong. Abort."
        exit 1
    fi

    ensure_paths

    echo "Backup folder: $BACKUP_DIR"
    backup_file "$KERNEL"
    [ -f "$API_CLIENT" ] && backup_file "$API_CLIENT"

    echo "Membuat middleware files..."
    write_whitelist_middleware "$OWNER"
    write_clientlock_middleware "$OWNER"

    echo "Mendaftarkan di Kernel dan route..."
    add_kernel_aliases_and_web_group
    add_clientlock_to_api_client

    clear_laravel_cache

    echo "======================================="
    echo " ANTI RUSUH TERPASANG DENGAN AMAN!"
    echo " Owner(s): $OWNER"
    echo " Backups: $BACKUP_DIR"
    echo "======================================="
}

add_owner_flow() {
    read -p "Masukkan ID owner baru (angka): " NEW
    if ! [[ "$NEW" =~ ^[0-9]+$ ]]; then
        echo "ID harus angka."
        return
    fi
    if [ -f "$ADMIN_MW" ]; then
        # insert into the array line in WhitelistAdmin.php
        sed -i -E "s/\\[([0-9, ]*)\\]/[\\1,$NEW]/" "$ADMIN_MW" || true
        echo "Ditambahkan ke $ADMIN_MW"
    fi
    if [ -f "$CLIENT_MW" ]; then
        sed -i -E "s/\\[([0-9, ]*)\\]/[\\1,$NEW]/" "$CLIENT_MW" || true
        echo "Ditambahkan ke $CLIENT_MW"
    fi
    clear_laravel_cache
}

del_owner_flow() {
    read -p "Masukkan ID owner yang dihapus (angka): " DEL
    if ! [[ "$DEL" =~ ^[0-9]+$ ]]; then
        echo "ID harus angka."
        return
    fi
    if [ -f "$ADMIN_MW" ]; then
        sed -i "s/\\b$DEL\\b//g" "$ADMIN_MW" || true
        sed -i "s/,,/,/g" "$ADMIN_MW" || true
        echo "Dihapus dari $ADMIN_MW"
    fi
    if [ -f "$CLIENT_MW" ]; then
        sed -i "s/\\b$DEL\\b//g" "$CLIENT_MW" || true
        sed -i "s/,,/,/g" "$CLIENT_MW" || true
        echo "Dihapus dari $CLIENT_MW"
    fi
    clear_laravel_cache
}

uninstall_flow() {
    echo "Membuat backup sebelum hapus..."
    backup_file "$KERNEL"
    [ -f "$API_CLIENT" ] && backup_file "$API_CLIENT"

    echo "Menghapus middleware files..."
    rm -f "$ADMIN_MW" "$CLIENT_MW" || true

    echo "Menghapus alias dan class dari Kernel..."
    sed -i "/whitelistadmin/d" "$KERNEL" || true
    sed -i "/clientlock/d" "$KERNEL" || true
    sed -i "/Pterodactyl\\\\Http\\\\Middleware\\\\WhitelistAdmin::class/d" "$KERNEL" || true

    echo "Menghapus clientlock dari api-client..."
    if [ -f "$API_CLIENT" ]; then
        sed -i "s/AuthenticateServerAccess::class, 'clientlock'*/AuthenticateServerAccess::class/" "$API_CLIENT" || true
        sed -i "s/'clientlock',//g" "$API_CLIENT" || true
    fi

    clear_laravel_cache

    echo "Anti-Rusuh telah dihapus. Backup ada di $BACKUP_DIR"
}

menu() {
    while true; do
        banner
        echo "1) Install Anti-Rusuh"
        echo "2) Tambah Owner"
        echo "3) Hapus Owner"
        echo "4) Uninstall Anti-Rusuh"
        echo "5) Exit"
        read -p "Pilih: " CH
        case "${CH:-}" in
            1) install_flow ;;
            2) add_owner_flow ;;
            3) del_owner_flow ;;
            4) uninstall_flow ;;
            5) exit 0 ;;
            *) echo "Pilihan tidak valid." ;;
        esac
        echo ""
        read -p "Tekan ENTER untuk kembali ke menu..." -r
    done
}

menu
