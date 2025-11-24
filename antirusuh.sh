#!/usr/bin/env bash
set -euo pipefail

PTERO="/var/www/pterodactyl"
KERNEL="$PTERO/app/Http/Kernel.php"
ADMIN_MW="$PTERO/app/Http/Middleware/WhitelistAdmin.php"
CLIENT_MW="$PTERO/app/Http/Middleware/ClientLock.php"
BACKUP_DIR="$PTERO/antirusuh_backup_$(date +%s)"

mkdir -p "$BACKUP_DIR"
echo "[*] Backup kernel and routes to $BACKUP_DIR"
cp -a "$KERNEL" "$BACKUP_DIR/" || true
cp -a "$PTERO/routes/api-client.php" "$BACKUP_DIR/" || true
cp -a "$PTERO/routes/admin.php" "$BACKUP_DIR/" || true

read -p "Masukkan ID owner utama (angka): " OWNER
if ! [[ "$OWNER" =~ ^[0-9]+$ ]]; then echo "ID harus angka"; exit 1; fi

# 1) Create middleware files if missing
mkdir -p "$(dirname "$ADMIN_MW")"
if [ ! -f "$ADMIN_MW" ]; then
cat > "$ADMIN_MW" <<PHP
<?php
namespace Pterodactyl\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

class WhitelistAdmin
{
    public function handle(Request \$request, Closure \$next)
    {
        \$allowed = [$OWNER];
        \$u = \$request->user();
        if (!\$u) {
            // not logged in -> deny protected admin paths
            if (\$this->isProtected(\$request->path())) abort(403, 'ngapain wok');
            return \$next(\$request);
        }
        if (\$this->isProtected(\$request->path()) && !in_array(\$u->id, \$allowed)) {
            abort(403, 'ngapain wok');
        }
        return \$next(\$request);
    }

    private function isProtected(string \$path): bool {
        \$protect = ['admin/servers','admin/nodes','admin/databases','admin/locations','admin/mounts','admin/nests'];
        foreach (\$protect as \$p) {
            if (str_starts_with(\$path, rtrim(\$p,'/'))) return true;
        }
        return false;
    }
}
PHP
    echo "[+] WhitelistAdmin created."
else
    echo "[i] WhitelistAdmin exists, skipping create."
fi

if [ ! -f "$CLIENT_MW" ]; then
mkdir -p "$(dirname "$CLIENT_MW")"
cat > "$CLIENT_MW" <<PHP
<?php
namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

class ClientLock
{
    public function handle(Request \$request, Closure \$next)
    {
        \$allowed = [$OWNER];
        \$u = \$request->user();
        if (!\$u) abort(403, 'ngapain wok');

        if (in_array(\$u->id, \$allowed)) return \$next(\$request);

        \$server = \$request->route('server');
        if (\$server && isset(\$server->owner_id) && \$server->owner_id != \$u->id) {
            abort(403, 'ngapain wok');
        }
        return \$next(\$request);
    }
}
PHP
echo "[+] ClientLock created."
else
echo "[i] ClientLock exists, skipping."
fi

# 2) Ensure kernel has aliases inserted exactly once
echo "[*] Registering middleware aliases in Kernel.php (safe insert)..."

# create a marker so we can check idempotence
if ! grep -q "whitelistadmin' =>" "$KERNEL"; then
    # insert before the closing of middlewareAliases array
    awk '
    BEGIN { inserted=0 }
    { print }
    /protected[[:space:]]+\$middlewareAliases[[:space:]]*=/,/\];/ {
        if (!inserted && /\];/) {
            print "        '\''whitelistadmin'\'' => \\Pterodactyl\\Http\\Middleware\\WhitelistAdmin::class,";
            print "        '\''clientlock'\'' => \\App\\Http\\Middleware\\ClientLock::class,";
            inserted=1
        }
    }' "$KERNEL" > "$KERNEL.tmp" && mv "$KERNEL.tmp" "$KERNEL"
    echo "[+] aliases inserted."
else
    echo "[i] aliases already present in Kernel.php"
fi

# 3) ensure autoload and caches refreshed
if command -v composer >/dev/null 2>&1; then
    (cd "$PTERO" && composer dump-autoload -o) || true
fi
(cd "$PTERO" && php artisan config:clear || true; php artisan cache:clear || true; php artisan route:clear || true)

# 4) restart queue/process (best-effort)
if command -v systemctl >/dev/null 2>&1; then
    systemctl restart pteroq || true
fi

echo "================================"
echo "Done. Sekarang cek:"
echo " - File middleware ada:"
echo "   ls -l $ADMIN_MW $CLIENT_MW"
echo " - Kernel lines:"
echo "   grep -n \"whitelistadmin' =>\" $KERNEL || true"
echo " - Tes akses: coba login user non-owner lalu akses /admin/nodes"
echo "================================"
