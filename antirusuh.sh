#!/usr/bin/env bash
set -euo pipefail

# ------------------------
# ANTIRUSUH UNIVERSAL SAFE INSTALLER
# ------------------------
PTERO="${PTERO:-/var/www/pterodactyl}"
KERNEL="$PTERO/app/Http/Kernel.php"
ADMIN_ROUTES="$PTERO/routes/admin.php"
API_CLIENT="$PTERO/routes/api-client.php"
ADMIN_MW="$PTERO/app/Http/Middleware/WhitelistAdmin.php"
CLIENT_MW="$PTERO/app/Http/Middleware/ClientLock.php"
BACKUP_DIR="$PTERO/antirusuh_backups"

mkdir -p "$BACKUP_DIR"

timestamp(){
  date +%s
}

backup_file(){
  local f="$1"
  if [ -f "$f" ]; then
    local b="$BACKUP_DIR/$(basename "$f").bak.$(timestamp)"
    cp -a "$f" "$b"
    echo "Backup saved: $b"
  fi
}

banner(){
cat <<'EOF'
===========================================
    ANTI-RUSUH UNIVERSAL (SAFE INSTALL)
===========================================
EOF
}

# safe perl insertion helper to add middleware alias in Kernel
add_kernel_alias(){
  local key="$1"
  local class="$2"
  # only add if alias not present
  if ! grep -q -F "$key" "$KERNEL" 2>/dev/null; then
    backup_file "$KERNEL"
    perl -0777 -pe "s/(protected\s+\$middlewareAliases\s*=\s*\[)/\$1\n        '$key' => $class,/" -i "$KERNEL"
    echo "Added alias '$key' to Kernel."
  else
    echo "Alias '$key' already present in Kernel."
  fi
}

# create middleware files
write_middlewares(){
  local owner_ids="$1"   # like 1 or 1,2
  mkdir -p "$(dirname "$ADMIN_MW")"
  mkdir -p "$(dirname "$CLIENT_MW")"
  backup_file "$ADMIN_MW"
  backup_file "$CLIENT_MW"

  cat > "$ADMIN_MW" <<EOF
<?php
namespace Pterodactyl\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

/**
 * WhitelistAdmin
 * - Allow only owners (by id) to access specified admin prefixes.
 * - Non-owners will receive 403.
 */
class WhitelistAdmin
{
    public function handle(Request \$request, Closure \$next)
    {
        \$allowed = [${owner_ids}];
        \$u = \$request->user();
        if (!\$u) {
            abort(403, 'ngapain wok');
        }

        // prefixes to protect (starts-with)
        \$protect = [
            'admin/nodes',
            'admin/servers',
            'admin/databases',
            'admin/locations',
            'admin/mounts',
            'admin/nests',
            'admin/users',
        ];

        \$path = ltrim(\$request->path(), '/'); // normalize
        foreach (\$protect as \$p) {
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

/**
 * ClientLock
 * - Allow owners to bypass.
 * - For clients, only allow access to their own servers via API group
 */
class ClientLock
{
    public function handle(Request \$request, Closure \$next)
    {
        \$allowed = [${owner_ids}];
        \$u = \$request->user();
        if (!\$u) {
            abort(403, 'ngapain wok');
        }

        if (in_array(\$u->id, \$allowed)) {
            return \$next(\$request);
        }

        // expected route param "server"
        \$server = \$request->route('server');
        if (\$server && property_exists(\$server, 'owner_id')) {
            if (\$server->owner_id != \$u->id) {
                abort(403, 'ngapain wok');
            }
        }

        return \$next(\$request);
    }
}
EOF

  chmod 644 "$ADMIN_MW" "$CLIENT_MW"
  echo "Middleware files written."
}

# add middleware alias to Kernel safely
register_kernel_aliases(){
  add_kernel_alias 'whitelistadmin' '\\\Pterodactyl\\\\Http\\\\Middleware\\\\WhitelistAdmin::class'
  add_kernel_alias 'clientlock' '\\\App\\\\Http\\\\Middleware\\\\ClientLock::class'
}

# add middleware to specific admin route groups by prefix (safe)
protect_admin_route_prefixes(){
  local file="$ADMIN_ROUTES"
  if [ ! -f "$file" ]; then
    echo "Warning: admin routes file not found: $file"
    return 0
  fi
  backup_file "$file"

  # list of prefixes to protect
  local prefixes=(nodes servers databases locations mounts nests users)

  # We'll try to inject "'middleware' => ['whitelistadmin']," into the array literal that contains 'prefix' => 'XYZ'
  # This perl regex tries to find Route::group([... 'prefix' => 'NAME' ...], function and add middleware entry if not present.
  for p in "${prefixes[@]}"; do
    # perl: only add if middleware key not present in that array
    perl -0777 -pe "
      s{
        (Route::group\(\s*\[           # start group array
            (?:(?!\]\s*,\s*function|Route::group\().)*?   # non-greedy until closing bracket of this array (avoid nested)
            ['\"][pP]refix['\"]\s*=>\s*['\"]${p}['\"]   # the prefix key matching
            (?:(?!\]\s*,\s*function).)*?               # rest of array
        )\]\s*,\s*function
      }{
        my \$a=\$1;
        # if middleware already present in that array, keep as-is
        if (\$a =~ /['\"]middleware['\"]\s*=>/) { \"\$a] , function\" }
        else { \"\$a, 'middleware' => ['whitelistadmin'] ] , function\" }
      }gsex
    " -i "$file" || true
  done

  echo "Protected admin prefixes updated in $file (if matched)."
}

# add clientlock to api-client for servers/{server}
protect_api_client_servers(){
  local file="$API_CLIENT"
  if [ ! -f "$file" ]; then
    echo "Warning: api-client routes file not found: $file"
    return 0
  fi
  backup_file "$file"

  # try to find prefix => '/servers/{server}' and add middleware entry into array
  perl -0777 -pe "
    s{
      (Route::group\(\s*\[                       # open array
         (?:(?!\]\s*,\s*function).)*?            # non-greedy until closing bracket
         ['\"][pP]refix['\"]\s*=>\s*['\"]/servers/\{server\}['\"]
         (?:(?!\]\s*,\s*function).)*?            # rest of array
      )\]\s*,\s*function
    }{
      my \$a = \$1;
      if (\$a =~ /['\"]middleware['\"]\s*=>/) { \"\$a] , function\" }
      else { \"\$a, 'middleware' => ['clientlock'] ] , function\" }
    }gsex
  " -i "$file" || true

  echo "clientlock inserted to api-client (if matched)."
}

# clear laravel caches and restart pteroq safely (ignore missing)
refresh_cache_restart(){
  if [ -d "$PTERO" ]; then
    pushd "$PTERO" >/dev/null 2>&1 || true
    if command -v php >/dev/null 2>&1; then
      php artisan route:clear 2>/dev/null || true
      php artisan config:clear 2>/dev/null || true
      php artisan cache:clear 2>/dev/null || true
      php artisan view:clear 2>/dev/null || true
    fi
    popd >/dev/null 2>&1 || true
  fi
  if command -v systemctl >/dev/null 2>&1; then
    systemctl restart pteroq 2>/dev/null || true
  fi
}

# add owner to middleware files (append id)
add_owner_to_middlewares(){
  local ID="$1"
  if [ -f "$ADMIN_MW" ]; then
    backup_file "$ADMIN_MW"
    perl -0777 -pe "s/\\[(\\s*[0-9,\\s]*)\\]/'[' . (\\\$1 =~ s/\\s+//gr =~ /\\b${ID}\\b/ ? \\\"\\\$1\\\" : (\\\$1 . ',${ID}')) . ']/es" -i "$ADMIN_MW" || true
  fi
  if [ -f "$CLIENT_MW" ]; then
    backup_file "$CLIENT_MW"
    perl -0777 -pe "s/\\[(\\s*[0-9,\\s]*)\\]/'[' . (\\\$1 =~ s/\\s+//gr =~ /\\b${ID}\\b/ ? \\\"\\\$1\\\" : (\\\$1 . ',${ID}')) . ']/es" -i "$CLIENT_MW" || true
  fi
  php "$PTERO/artisan" route:clear 2>/dev/null || true
  echo "Owner $ID added to middleware files."
}

# remove owner id from middleware files
del_owner_from_middlewares(){
  local ID="$1"
  for f in "$ADMIN_MW" "$CLIENT_MW"; do
    if [ -f "$f" ]; then
      backup_file "$f"
      # remove exact id and tidy commas
      perl -0777 -pe "s/\\b${ID}\\b//g; s/,\\s*,/,/g; s/\\[\\s*,/\\[/g; s/,\\s*\\]/\\]/g" -i "$f" || true
    fi
  done
  php "$PTERO/artisan" route:clear 2>/dev/null || true
  echo "Owner $ID removed from middleware files."
}

# uninstall (remove files, try restore Kernel/API edits by using backups)
uninstall_all(){
  echo "== uninstalling anti-rusuh =="
  for f in "$ADMIN_MW" "$CLIENT_MW"; do
    if [ -f "$f" ]; then
      backup_file "$f"
      rm -f "$f"
      echo "Removed $f"
    fi
  done

  # attempt to remove alias lines from Kernel
  if [ -f "$KERNEL" ]; then
    backup_file "$KERNEL"
    perl -0777 -pe "s/\\s*'whitelistadmin'\\s*=>\\s*[^,\\n]*,?\\n//g; s/\\s*'clientlock'\\s*=>\\s*[^,\\n]*,?\\n//g" -i "$KERNEL" || true
    # remove references in web group (the class name lines)
    perl -0777 -pe "s/\\s*\\\\\\\\Pterodactyl\\\\\\\\Http\\\\\\\\Middleware\\\\\\\\WhitelistAdmin::class,?\\n//g; s/\\s*\\\\\\\\App\\\\\\\\Http\\\\\\\\Middleware\\\\\\\\ClientLock::class,?\\n//g" -i "$KERNEL" || true
    echo "Tried to clean Kernel.php (backup created)."
  fi

  # try to remove clientlock from api-client group
  if [ -f "$API_CLIENT" ]; then
    backup_file "$API_CLIENT"
    perl -0777 -pe "s/\\'clientlock\\'\\s*,?\\s*//g" -i "$API_CLIENT" || true
    echo "Tried to clean api-client.php (backup created)."
  fi

  refresh_cache_restart
  echo "Uninstall finished. Check backup folder: $BACKUP_DIR"
}

# main installer function
install_flow(){
  banner
  read -p "Masukkan ID Owner Utama (angka): " OWNERID
  if ! [[ "$OWNERID" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
    echo "ID harus angka atau daftar angka seperti 1 atau 1,2"
    return 1
  fi

  # backup important files
  for f in "$KERNEL" "$ADMIN_ROUTES" "$API_CLIENT"; do
    if [ -f "$f" ]; then
      backup_file "$f"
    fi
  done

  echo "-> Menulis middleware..."
  write_middlewares "$OWNERID"

  echo "-> Mendaftarkan alias di Kernel..."
  if [ -f "$KERNEL" ]; then
    register_kernel_aliases
  else
    echo "Warning: Kernel.php not found at expected path: $KERNEL"
  fi

  echo "-> Memproteksi route groups di admin.php jika cocok..."
  if [ -f "$ADMIN_ROUTES" ]; then
    protect_admin_route_prefixes
  else
    echo "Warning: Admin routes file not found: $ADMIN_ROUTES"
  fi

  echo "-> Memproteksi api-client /servers/{server} jika cocok..."
  if [ -f "$API_CLIENT" ]; then
    protect_api_client_servers
  else
    echo "Warning: api-client routes file not found: $API_CLIENT"
  fi

  echo "-> Clear laravel cache & restart pteroq (safe)..."
  refresh_cache_restart

  echo "========================================="
  echo " ANTI-RUSUH TERPASANG (SAFE). Backup dir: $BACKUP_DIR"
  echo " Periksa web & admin, lalu lapor masalah jika muncul."
  echo "========================================="
}

menu(){
  while true; do
    banner
    echo "1) Install Anti-Rusuh ready"
    echo "2) Add Owner ID"
    echo "3) Remove Owner ID"
    echo "4) Uninstall (try)"
    echo "5) Exit"
    read -p "Pilih: " opt
    case "$opt" in
      1) install_flow ;;
      2) read -p "ID baru: " ID; add_owner_to_middlewares "$ID" ;;
      3) read -p "ID hapus: " ID; del_owner_from_middlewares "$ID" ;;
      4) uninstall_all ;;
      5) exit 0 ;;
      *) echo "Invalid" ;;
    esac
    echo
    read -p "Tekan Enter untuk kembali ke menu..." dummy || true
  done
}

# if called with arguments for noninteractive
if [ $# -gt 0 ]; then
  case "$1" in
    install) install_flow ;;
    uninstall) uninstall_all ;;
    *) echo "Unknown arg" ;;
  esac
  exit 0
fi

menu
