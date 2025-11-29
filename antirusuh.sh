#!/bin/bash
set -euo pipefail

PTERO="/var/www/pterodactyl"
BACKUP_DIR="$PTERO/antirusuh_backup_$(date +%s)"
OWNER_ENV_NAME="ANTIRUSUH_OWNER"

echo "======================================="
echo "  PROTECTION INSTALLER — SAFE MODE v1"
echo "======================================="

if [ "$(id -u)" != "0" ]; then
  echo "Jalankan sebagai root (sudo). Exit."
  exit 1
fi

mkdir -p "$BACKUP_DIR"

# helper
bak() {
  src="$1"
  dst="$BACKUP_DIR$(echo "$src" | sed 's#/#_#g')"
  if [ -e "$src" ]; then
    cp -a "$src" "$dst"
    echo "backup: $src -> $dst"
  fi
}

ask_owner() {
  read -p "Masukkan ID Owner Utama (angka): " OWNER
  if ! [[ "$OWNER" =~ ^[0-9]+$ ]]; then
    echo "ID harus angka. Exit."
    exit 1
  fi
}

install_files() {
  echo "Membuat file middleware dan provider..."

  # ensure directories
  mkdir -p "$PTERO/app/Http/Middleware"
  mkdir -p "$PTERO/app/Providers"

  # Middleware file (namespace Pterodactyl\Http\Middleware)
  MW="$PTERO/app/Http/Middleware/AntiRusuh.php"
  bak "$MW"
  cat > "$MW" <<'PHP'
<?php

namespace Pterodactyl\Http\Middleware;

use Closure;

class AntiRusuh
{
    public function handle($request, Closure $next)
    {
        $user = $request->user();

        // if not logged in -> do nothing (normal behavior)
        if (!$user) {
            return $next($request);
        }

        // owner id read from env (fallback 1)
        $owner = (int)(env('ANTIRUSUH_OWNER') ?: 1);

        // protect admin sections: only owner or root_admin can access
        $path = ltrim($request->path(), '/');

        $protectedAdminPrefixes = [
            'admin/nodes',
            'admin/servers',
            'admin/databases',
            'admin/locations',
            'admin/mounts',
            'admin/nests',
            'admin/users',
        ];

        foreach ($protectedAdminPrefixes as $prefix) {
            if (strpos($path, $prefix) === 0) {
                if ($user->id != $owner && empty($user->root_admin)) {
                    abort(403, 'Access denied.');
                }
            }
        }

        // Protect API client server access as fallback (extra safety)
        if ($request->route() && $request->route()->parameter('server')) {
            $server = $request->route()->parameter('server');
            if ($server && isset($server->owner_id)) {
                if ($server->owner_id != $user->id && empty($user->root_admin) && $user->id != $owner) {
                    abort(403, 'Access denied.');
                }
            }
        }

        return $next($request);
    }
}
PHP

  chmod 0644 "$MW"

  # Provider file (namespace Pterodactyl\Providers)
  PROVIDER="$PTERO/app/Providers/AntiRusuhServiceProvider.php"
  bak "$PROVIDER"
  cat > "$PROVIDER" <<'PHP'
<?php

namespace Pterodactyl\Providers;

use Illuminate\Support\ServiceProvider;
use Illuminate\Support\Facades\Route;

class AntiRusuhServiceProvider extends ServiceProvider
{
    public function register()
    {
        //
    }

    public function boot()
    {
        // push middleware into groups so we don't need to edit routes/admin.php
        try {
            $router = $this->app['router'];
            if (method_exists($router, 'pushMiddlewareToGroup')) {
                // attach middleware to web group and client-api group if present
                $router->pushMiddlewareToGroup('web', \Pterodactyl\Http\Middleware\AntiRusuh::class);
                $router->pushMiddlewareToGroup('client-api', \Pterodactyl\Http\Middleware\AntiRusuh::class);
            }
        } catch (\Throwable $e) {
            // ignore failures here, provider will still be registered
        }

        // Additional route-time check (protect server param routes)
        Route::matched(function ($event) {
            $request = $event->request;
            $user = $request->user();
            if (!$user) return;

            $owner = (int)(env('ANTIRUSUH_OWNER') ?: 1);

            if ($request->route() && $request->route()->parameter('server')) {
                $server = $request->route()->parameter('server');
                if ($server && isset($server->owner_id)) {
                    if ($server->owner_id != $user->id && empty($user->root_admin) && $user->id != $owner) {
                        abort(403, 'Access denied.');
                    }
                }
            }
        });
    }
}
PHP

  chmod 0644 "$PROVIDER"
}

register_provider_in_config() {
  APP_CONFIG="$PTERO/config/app.php"
  bak "$APP_CONFIG"

  provider_line="    Pterodactyl\\\Providers\\\AntiRusuhServiceProvider::class,"

  # Try several insertion points (common variants)
  if grep -q "Pterodactyl\\\\Providers\\\\AntiRusuhServiceProvider::class" "$APP_CONFIG"; then
    echo "Provider sudah terdaftar di config/app.php"
    return
  fi

  # 1) typical Laravel: 'providers' => [
  if grep -q "'providers' => \[" "$APP_CONFIG"; then
    sed -i "/'providers' => \[/a\\
$provider_line" "$APP_CONFIG" && return
  fi

  # 2) double quotes variant
  if grep -q '"providers" => \[' "$APP_CONFIG"; then
    sed -i '/"providers" => \[/a\
'"$provider_line"'' "$APP_CONFIG" && return
  fi

  # 3) fallback: append near return array
  sed -i "/return \[/{p; a\\
'providers' => [
$provider_line
]," -n "$APP_CONFIG" 2>/dev/null || true

  if ! grep -q "AntiRusuhServiceProvider" "$APP_CONFIG"; then
    echo "Gagal otomatis menambah provider ke config/app.php — file dibackup di $BACKUP_DIR. Kamu perlu menambahkan provider secara manual:"
    echo "  Pterodactyl\\Providers\\AntiRusuhServiceProvider::class,"
  else
    echo "Provider terdaftar di config/app.php"
  fi
}

set_owner_env() {
  # set env variable in .env (create if not exist)
  ENVFILE="$PTERO/.env"
  bak "$ENVFILE"
  if [ ! -f "$ENVFILE" ]; then
    cp "$PTERO/.env.example" "$ENVFILE" 2>/dev/null || touch "$ENVFILE"
  fi
  # set or replace
  if grep -q "^${OWNER_ENV_NAME}=" "$ENVFILE"; then
    sed -i "s/^${OWNER_ENV_NAME}=.*/${OWNER_ENV_NAME}=${OWNER}/" "$ENVFILE"
  else
    echo "${OWNER_ENV_NAME}=${OWNER}" >> "$ENVFILE"
  fi
  echo "Set ${OWNER_ENV_NAME}=${OWNER} in $ENVFILE"
}

refresh_cache() {
  cd "$PTERO" || true
  # Try safe clears — ignore if artisan missing or errors
  if [ -f "$PTERO/artisan" ]; then
    php artisan config:clear || true
    php artisan cache:clear || true
    php artisan route:clear || true
    php artisan view:clear || true
    php artisan optimize:clear || true
  fi
  # Try restart service if exists
  if systemctl list-unit-files | grep -q pteroq; then
    systemctl restart pteroq || true
  fi
}

install() {
  ask_owner
  install_files
  register_provider_in_config
  set_owner_env
  refresh_cache

  echo "======================================="
  echo " PROTECTION TERPASANG. Tes sekarang:"
  echo " - login sebagai user bukan owner -> buka Admin > Nodes (harus 403)"
  echo " - owner / root_admin tetap bisa"
  echo "Jika masih tidak bekerja, kirim output:"
  echo "  php artisan route:list | grep admin"
  echo "  cat -n $PTERO/app/Http/Kernel.php"
  echo "  cat -n $PTERO/app/Providers/RouteServiceProvider.php"
  echo "Backup dibuat di: $BACKUP_DIR"
  echo "======================================="
}

uninstall() {
  echo "Mulai uninstall..."
  # restore backups if present
  if [ -d "$BACKUP_DIR" ]; then
    echo "Menggunakan backup di $BACKUP_DIR (tidak dihapus otomatis)."
  fi

  # remove created files
  rm -f "$PTERO/app/Http/Middleware/AntiRusuh.php" || true
  rm -f "$PTERO/app/Providers/AntiRusuhServiceProvider.php" || true

  # remove provider line from config/app.php if present (best-effort)
  APP_CONFIG="$PTERO/config/app.php"
  if [ -f "$APP_CONFIG" ]; then
    sed -i "/AntiRusuhServiceProvider::class/d" "$APP_CONFIG" || true
  fi

  # remove env key
  ENVFILE="$PTERO/.env"
  if [ -f "$ENVFILE" ]; then
    sed -i "/^${OWNER_ENV_NAME}=/d" "$ENVFILE" || true
  fi

  refresh_cache

  echo "Uninstall selesai. Periksa panel. Backup ada di $BACKUP_DIR (jika dibuat saat install)."
}

usage() {
  echo "Usage: $0 install  OR  $0 uninstall"
  exit 1
}

case "${1:-}" in
  install)
    install
    ;;
  uninstall)
    uninstall
    ;;
  *)
    usage
    ;;
esac
