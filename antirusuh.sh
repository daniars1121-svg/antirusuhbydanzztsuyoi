#!/usr/bin/env bash
# AntiRusuh FINAL installer (safe, with backups + rollback)
# Save as antirusuh-final.sh and run with bash.

PTERO="/var/www/pterodactyl"
KERNEL="$PTERO/app/Http/Kernel.php"
API_CLIENT="$PTERO/routes/api-client.php"
ADMIN_MW="$PTERO/app/Http/Middleware/WhitelistAdmin.php"
CLIENT_MW="$PTERO/app/Http/Middleware/ClientLock.php"
BACKUP_DIR_ROOT="$PTERO/antirusuh_backups"

mkdir -p "$BACKUP_DIR_ROOT"

banner(){
    cat <<'EOF'
===========================================
        ANTI RUSUH FINAL - INSTALLER
         Safe universal for Pterodactyl
===========================================
EOF
}

php_check() {
    if ! command -v php >/dev/null 2>&1; then
        echo "php CLI not found. Install php-cli to continue."
        return 1
    fi
    return 0
}

backup_files(){
    local tag ts dest
    ts=$(date +%s)
    tag="$1"
    dest="$BACKUP_DIR_ROOT/${tag}_$ts"
    mkdir -p "$dest"
    echo "→ Backup to $dest"
    cp -a "$KERNEL" "$dest/" 2>/dev/null || true
    cp -a "$API_CLIENT" "$dest/" 2>/dev/null || true
    cp -a "$ADMIN_MW" "$dest/" 2>/dev/null || true
    cp -a "$CLIENT_MW" "$dest/" 2>/dev/null || true
    echo "$dest"
}

rollback_if_bad(){
    local dest="$1"
    local reason="$2"
    echo "ERROR: $reason"
    echo "Rolling back from backup: $dest"
    cp -a "$dest/Kernel.php" "$KERNEL" 2>/dev/null || true
    cp -a "$dest/$(basename "$API_CLIENT")" "$API_CLIENT" 2>/dev/null || true
    cp -a "$dest/$(basename "$ADMIN_MW")" "$ADMIN_MW" 2>/dev/null || true
    cp -a "$dest/$(basename "$CLIENT_MW")" "$CLIENT_MW" 2>/dev/null || true
    echo "Rollback complete. Please check web/logs and re-run the installer after fixing issues."
    exit 1
}

install(){
    banner
    php_check || exit 1

    read -p "Masukkan ID Owner Utama (angka): " OWNER
    if ! [[ "$OWNER" =~ ^[0-9]+$ ]]; then
        echo "ID harus angka. Batal."
        exit 1
    fi

    BACKUP_DIR=$(backup_files "preinstall")
    echo "→ Membuat middleware files..."

    mkdir -p "$(dirname "$ADMIN_MW")"
    mkdir -p "$(dirname "$CLIENT_MW")"

    cat > "$ADMIN_MW" <<EOF
<?php
namespace Pterodactyl\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

class WhitelistAdmin
{
    /**
     * Protect some admin routes by whitelist of admin IDs.
     * Uses request path checking so we don't need to touch admin.php.
     */
    public function handle(Request \$request, Closure \$next)
    {
        // Allowed admin user IDs (installer fills this)
        \$allowed = [${OWNER}];

        // If no authenticated user, abort
        \$u = \$request->user();
        if (!\$u) {
            abort(403, 'ngapain wok');
        }

        // paths to protect (prefixes). Keep them without leading slash.
        \$protectedPrefixes = [
            'admin/nodes',
            'admin/locations',
            'admin/mounts',
            'admin/databases',
            'admin/nests',
            'admin/servers',
        ];

        \$path = ltrim(\$request->path(), '/');

        foreach (\$protectedPrefixes as \$p) {
            if (str_starts_with(\$path, \$p)) {
                if (!in_array(\$u->id, \$allowed)) {
                    abort(403, 'ngapain wok');
                }
            }
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

class ClientLock
{
    /**
     * Restrict client API servers/{server} actions to server owner (unless owner is in allowed list).
     */
    public function handle(Request \$request, Closure \$next)
    {
        \$allowed = [${OWNER}];
        \$u = \$request->user();
        if (!\$u) {
            abort(403, 'ngapain wok');
        }

        // allowed owner bypass
        if (in_array(\$u->id, \$allowed)) {
            return \$next(\$request);
        }

        // get server route binding (if present)
        \$server = \$request->route('server');
        if (\$server && property_exists(\$server, 'owner_id') && \$server->owner_id != \$u->id) {
            abort(403, 'ngapain wok');
        }

        return \$next(\$request);
    }
}
EOF

    echo "→ Register middleware aliases in Kernel.php (safe insertion)..."

    # Use perl to insert aliases inside the middlewareAliases array only if missing
    if ! grep -q "whitelistadmin" "$KERNEL"; then
        perl -0777 -pe '
            if (s/(protected\s+\$middlewareAliases\s*=\s*\[)(.*?)(\n\s*\];)/$1$2
        '\''whitelistadmin'\'' => \\\\Pterodactyl\\\\Http\\\\Middleware\\\\WhitelistAdmin::class,
        '\''clientlock'\'' => \\\\App\\\\Http\\\\Middleware\\\\ClientLock::class,
$3/s) {
                print STDERR "Inserted aliases\n";
            }
            ' -i "$KERNEL"
    else
        echo "→ Kernel already contains whitelistadmin/clientlock aliases (skipping insert)."
    fi

    # After editing kernel, check PHP syntax
    php -l "$KERNEL" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        rollback_if_bad "$BACKUP_DIR" "Kernel.php syntax error after modification."
    fi

    # Add WhitelistAdmin to web middleware group if not exists.
    if ! grep -q "WhitelistAdmin::class" "$KERNEL"; then
        # Insert entry into 'web' group after the opening of that array in a best-effort way.
        perl -0777 -pe '
            if (s/(\x27web\x27\s*=>\s*\[\s*)(.*?)(\n\s*\],)/$1$2
            \\\\Pterodactyl\\\\Http\\\\Middleware\\\\WhitelistAdmin::class,
$3/s) {
                print STDERR "Inserted WhitelistAdmin into web group\n";
            }
            ' -i "$KERNEL"
    fi

    php -l "$KERNEL" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        rollback_if_bad "$BACKUP_DIR" "Kernel.php syntax error after adding to web group."
    fi

    echo "→ Patching api-client routes to attach clientlock middleware (if applicable)..."
    if [ -f "$API_CLIENT" ]; then
        # If AuthenticateServerAccess::class is present in servers group, add clientlock after it (only once).
        if grep -q "AuthenticateServerAccess::class" "$API_CLIENT" && ! grep -q "clientlock" "$API_CLIENT"; then
            sed -i "s/AuthenticateServerAccess::class/AuthenticateServerAccess::class, 'clientlock'/g" "$API_CLIENT"
        fi
        php -l "$API_CLIENT" >/dev/null 2>&1 || rollback_if_bad "$BACKUP_DIR" "api-client.php syntax error after edit."
    else
        echo "→ Warning: $API_CLIENT not found — skipping."
    fi

    echo "→ Clearing Laravel caches (route/config/cache)..."
    cd "$PTERO" || true
    php artisan route:clear 2>/dev/null || true
    php artisan config:clear 2>/dev/null || true
    php artisan cache:clear 2>/dev/null || true

    # Restart queue/process if exists (best-effort)
    if systemctl list-units --type=service --all | grep -q pteroq; then
        systemctl restart pteroq 2>/dev/null || true
    fi

    echo "========================================="
    echo " ANTI RUSUH FINAL TERPASANG (OWNER: $OWNER)"
    echo " Backup di: $BACKUP_DIR"
    echo " - Middleware dibuat: $ADMIN_MW and $CLIENT_MW"
    echo " - Kernel dipatch aman (alias + web group)"
    echo " - API client diperiksa/di-patch jika ada"
    echo "========================================="
    echo "Tes akses dengan user non-owner untuk memastikan protection berfungsi."
    echo "Jika ada error 500, lihat storage/logs/laravel.log"
}

uninstall(){
    banner
    # find latest backup to restore
    latest=$(ls -d "$BACKUP_DIR_ROOT"/preinstall_* 2>/dev/null | tail -n1)
    if [ -z "$latest" ]; then
        echo "No backup found in $BACKUP_DIR_ROOT. Will try to remove files safe."
        rm -f "$ADMIN_MW" "$CLIENT_MW"
        # remove aliases and whitelist insertion (best-effort)
        sed -i "/whitelistadmin/d" "$KERNEL" 2>/dev/null || true
        sed -i "/clientlock/d" "$KERNEL" 2>/dev/null || true
        sed -i "/WhitelistAdmin::class/d" "$KERNEL" 2>/dev/null || true
        if [ -f "$API_CLIENT" ]; then
            sed -i "s/,\s*'clientlock'//g" "$API_CLIENT" 2>/dev/null || true
            sed -i "s/'clientlock',//g" "$API_CLIENT" 2>/dev/null || true
        fi
        php artisan route:clear 2>/dev/null || true
        echo "Uninstall best-effort finished."
        exit 0
    fi

    echo "Restoring from backup: $latest"
    cp -a "$latest/Kernel.php" "$KERNEL" 2>/dev/null || true
    cp -a "$latest/$(basename "$API_CLIENT")" "$API_CLIENT" 2>/dev/null || true
    cp -a "$latest/$(basename "$ADMIN_MW")" "$ADMIN_MW" 2>/dev/null || true
    cp -a "$latest/$(basename "$CLIENT_MW")" "$CLIENT_MW" 2>/dev/null || true
    rm -f "$ADMIN_MW" "$CLIENT_MW"
    php artisan route:clear 2>/dev/null || true
    echo "Uninstall complete. Restored Kernel & api-client to backup."
}

menu(){
    while true; do
        banner
        echo "1) Install Anti-Rusuh FINAL"
        echo "2) Uninstall (restore latest backup)"
        echo "3) Exit"
        read -p "Pilih: " opt
        case "$opt" in
            1) install; break ;;
            2) uninstall; break ;;
            3) exit 0 ;;
            *) echo "Pilih 1/2/3";;
        esac
    done
}

menu
