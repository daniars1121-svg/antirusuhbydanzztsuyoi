#!/usr/bin/env bash
set -euo pipefail

PTERO="/var/www/pterodactyl"
ADMIN_ROUTES="$PTERO/routes/admin.php"
CLIENT_ROUTE="$PTERO/routes/api-client.php"
KERNEL="$PTERO/app/Http/Kernel.php"
ADMIN_MW="$PTERO/app/Http/Middleware/WhitelistAdmin.php"
CLIENT_MW="$PTERO/app/Http/Middleware/ClientLock.php"
BACKUP_DIR="$PTERO/antirusuh_backup_$(date +%s)"

mkdir -p "$BACKUP_DIR"

banner(){
  cat <<'EOF'
========================================
      ANTI RUSUH UNIVERSAL - SAFE
========================================
EOF
}

safe_backup(){
  echo "→ Backup files to: $BACKUP_DIR"
  for f in "$KERNEL" "$ADMIN_ROUTES" "$CLIENT_ROUTE" "$ADMIN_MW" "$CLIENT_MW"; do
    if [ -f "$f" ]; then
      cp -a "$f" "$BACKUP_DIR/" || true
    fi
  done
}

validate_php_syntax_file(){
  # quick check: balanced brackets and no obvious ", ,"
  local file=$1
  if grep -qE ",[[:space:]]*," "$file"; then
    echo "ERROR: file $file contains ', ,' pattern (syntax risk). Will not modify."
    return 1
  fi
  # count parentheses/braces roughly
  local open=$(grep -o "{" "$file" | wc -l)
  local close=$(grep -o "}" "$file" | wc -l)
  if [ "$open" -ne "$close" ]; then
    echo "ERROR: mismatched { } in $file (found $open vs $close). Will not modify."
    return 1
  fi
  return 0
}

install_antirusuh(){
  banner
  read -p "Masukkan ID Owner Utama (angka): " OWNER
  if ! [[ "$OWNER" =~ ^[0-9]+$ ]]; then
    echo "ID harus angka."
    exit 1
  fi

  safe_backup

  # validate critical files before touching
  for f in "$KERNEL" "$ADMIN_ROUTES" "$CLIENT_ROUTE"; do
    if [ -f "$f" ]; then
      validate_php_syntax_file "$f" || { echo "Perbaiki $f dulu atau restore dari backup."; exit 1; }
    fi
  done

  echo "→ Menulis middleware WhitelistAdmin (admin protection)"
  mkdir -p "$(dirname "$ADMIN_MW")"
  cat > "$ADMIN_MW" <<EOF
<?php
namespace Pterodactyl\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

class WhitelistAdmin {
    public function handle(Request \$request, Closure \$next) {
        // owner id list
        \$allowed = [$OWNER];
        \$u = \$request->user();
        if (!\$u) {
            // not logged in => default deny for protected admin routes
            if (\$this->isProtectedPath(\$request->path())) abort(403, 'ngapain wok');
            return \$next(\$request);
        }
        if (\$this->isProtectedPath(\$request->path()) && !in_array(\$u->id, \$allowed)) {
            abort(403, 'ngapain wok');
        }
        return \$next(\$request);
    }

    private function isProtectedPath(string \$path): bool {
        // match prefix paths that should be admin-only in panel (/admin/...)
        \$protect = [
            'admin/servers',
            'admin/nodes',
            'admin/databases',
            'admin/locations',
            'admin/mounts',
            'admin/nests'
        ];
        foreach (\$protect as \$p) {
            if (str_starts_with(\$path, rtrim(\$p, '/'))) return true;
        }
        return false;
    }
}
EOF

  echo "→ Menulis middleware ClientLock (block access ke panel server orang via API)"
  mkdir -p "$(dirname "$CLIENT_MW")"
  cat > "$CLIENT_MW" <<EOF
<?php
namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

class ClientLock {
    public function handle(Request \$request, Closure \$next) {
        \$allowed = [$OWNER];
        \$u = \$request->user();
        if (!\$u) {
            abort(403, 'ngapain wok');
        }
        // owner bypass
        if (in_array(\$u->id, \$allowed)) return \$next(\$request);

        // route param 'server' must belong to user
        \$server = \$request->route('server');
        if (\$server && method_exists(\$server, 'getAttribute')) {
            // Eloquent model: owner_id
            \$owner_id = \$server->owner_id ?? (\$server->getAttribute('owner_id') ?? null);
            if (\$owner_id !== null && \$owner_id != \$u->id) {
                abort(403, 'ngapain wok');
            }
        }
        return \$next(\$request);
    }
}
EOF

  # register middleware aliases safely
  echo "→ Menambahkan middlewareAliases ke Kernel.php (jika belum ada)"
  if ! grep -q "WhitelistAdmin" "$KERNEL"; then
    # insert lines just before protected \$middlewareAliases = [
    # we'll add them inside the array block (search for "protected \$middlewareAliases")
    awk -v insert1="'clientlock' => \\\\App\\\\Http\\\\Middleware\\\\ClientLock::class," \
        -v insert2="'whitelistadmin' => \\\\Pterodactyl\\\\Http\\\\Middleware\\\\WhitelistAdmin::class," \
        '{
          print;
          if(!done && $0 ~ /protected[[:space:]]+\$middlewareAliases[[:space:]]*=/) {
             # print until opening bracket [
             while(getline) {
               print;
               if($0 ~ /\[/) {
                 print "        " insert1;
                 print "        " insert2;
                 done=1;
                 break;
               }
             }
          }
        }' "$KERNEL" > "$KERNEL.tmp" && mv "$KERNEL.tmp" "$KERNEL"
  else
    echo "   - middlewareAliases sudah ada, skip insert."
  fi

  # IMPORTANT: do NOT add WhitelistAdmin to 'web' group (that blocks whole panel).
  # Instead wrap admin routes file with middleware group if not already wrapped.

  echo "→ Membungkus routes/admin.php dengan Route::middleware(['whitelistadmin'])->group(...) jika belum"
  if [ -f "$ADMIN_ROUTES" ]; then
    # check if already wrapped
    if grep -q "middleware(['\"]*whitelistadmin" "$ADMIN_ROUTES"; then
      echo "   - admin.php sudah mengandung whitelistadmin, skip wrapping."
    else
      # produce temporary wrapped file: add opening line after initial <?php and use closure end at EOF
      awk 'NR==1{print; next}
           NR==2&& !x{ print "Route::middleware([\"whitelistadmin\"])->group(function() {"; x=1 }
           {print}
           END{ if(x==1) print "});" }' "$ADMIN_ROUTES" > "$ADMIN_ROUTES.tmp" && mv "$ADMIN_ROUTES.tmp" "$ADMIN_ROUTES"
      echo "   - admin.php dibungkus dengan middleware whitelistadmin."
    fi
  fi

  # Add clientlock to api-client servers group safely
  echo "→ Menambahkan clientlock ke routes/api-client.php server group jika perlu"
  if [ -f "$CLIENT_ROUTE" ]; then
    # find the servers group prefix line and inject 'clientlock' into middleware array if not present
    if grep -q "servers/{server}" "$CLIENT_ROUTE" && ! grep -q "clientlock" "$CLIENT_ROUTE"; then
      # safest approach: replace the servers group opening array to include 'middleware' => ['clientlock'],
      # but only if pattern "prefix' => '/servers/{server}'" exists. We'll do a targeted sed.
      sed -i "0,/'prefix'[[:space:]]*=>[[:space:]]*'\/servers\/{server}'/{
        s/'prefix' => '\/servers\/{server}'/'prefix' => '\/servers\/{server}', 'middleware' => ['clientlock']/
      }" "$CLIENT_ROUTE" || true

      # fallback: if above didn't run (different coding style), try adding clientlock after ServerSubject::class
      if ! grep -q "clientlock" "$CLIENT_ROUTE"; then
        sed -i "s/ServerSubject::class,/ServerSubject::class, 'clientlock',/g" "$CLIENT_ROUTE" || true
      fi
      echo "   - clientlock ditambahkan (jika cocok pola)."
    else
      echo "   - tidak menemukan kelompok servers/{server} atau clientlock sudah ada."
    fi
  fi

  echo "→ Membersihkan cache laravel dan restart pteroq (jika tersedia)"
  if [ -d "$PTERO" ]; then
    cd "$PTERO"
    php artisan route:clear || true
    php artisan config:clear || true
    php artisan cache:clear || true
  fi
  if command -v systemctl >/dev/null 2>&1; then
    systemctl restart pteroq || true
  fi

  echo "========================================"
  echo "   ANTI RUSUH TERPASANG (SAFE MODE)"
  echo "   Owner utama: $OWNER"
  echo "   Backup: $BACKUP_DIR"
  echo "========================================"
}

add_owner(){
  read -p "Masukkan ID owner baru (angka): " NEW
  if ! [[ "$NEW" =~ ^[0-9]+$ ]]; then echo "ID harus angka"; return; fi
  # safe add: insert into numeric lists inside middleware files
  sed -i "s/\[\([0-9,[:space:]]*\)\]/[\1,$NEW]/" "$ADMIN_MW" || true
  sed -i "s/\[\([0-9,[:space:]]*\)\]/[\1,$NEW]/" "$CLIENT_MW" || true
  php "$PTERO/artisan" route:clear || true
  echo "Owner $NEW ditambahkan."
}

del_owner(){
  read -p "Masukkan ID owner yang dihapus (angka): " DEL
  if ! [[ "$DEL" =~ ^[0-9]+$ ]]; then echo "ID harus angka"; return; fi
  sed -i "s/\b$DEL\b//g" "$ADMIN_MW" || true
  sed -i "s/\b$DEL\b//g" "$CLIENT_MW" || true
  sed -i "s/,,/,/g" "$ADMIN_MW" || true
  sed -i "s/,,/,/g" "$CLIENT_MW" || true
  php "$PTERO/artisan" route:clear || true
  echo "Owner $DEL dihapus."
}

uninstall_antirusuh(){
  banner
  echo "→ Restore dari backup jika ada, dan hapus file yang dibuat oleh script"
  # remove middleware files
  rm -f "$ADMIN_MW" "$CLIENT_MW"
  # remove middlewareAliases lines
  sed -i "/ClientLock::class/d" "$KERNEL" || true
  sed -i "/WhitelistAdmin::class/d" "$KERNEL" || true
  # remove wrapper in admin.php if it matches the wrapper we inserted
  if [ -f "$ADMIN_ROUTES" ]; then
    # if last line is "});" and first inserted wrapper exists, attempt to remove first wrapper line and final line
    if head -n 5 "$ADMIN_ROUTES" | grep -q "Route::middleware" ; then
      # remove first occurrence of the wrapper opening line
      awk 'NR==1{print;next}
           { if(!removed && $0 ~ /Route::middleware.*whitelistadmin/){removed=1; next}
             else print }' "$ADMIN_ROUTES" > "$ADMIN_ROUTES.tmp" && mv "$ADMIN_ROUTES.tmp" "$ADMIN_ROUTES"
      # remove trailing "});" if it was appended by us and not part of file logic (best-effort)
      # only delete trailing }); if it is standalone on last line.
      tail -n1 "$ADMIN_ROUTES" | grep -q "});" && sed -i '$d' "$ADMIN_ROUTES" || true
    fi
  fi
  # remove clientlock mention in api-client
  sed -i "s/'clientlock',//g" "$CLIENT_ROUTE" || true
  sed -i "s/, 'clientlock'//g" "$CLIENT_ROUTE" || true

  if [ -d "$BACKUP_DIR" ]; then
    echo "Backup ada di: $BACKUP_DIR (manual restore tersedia)"
  fi

  php "$PTERO/artisan" route:clear || true
  systemctl restart pteroq || true
  echo "AntiRusuh dihapus."
}

menu(){
  while true; do
    banner
    echo "1) Install Anti-Rusuh (safe)"
    echo "2) Tambah Owner"
    echo "3) Hapus Owner"
    echo "4) Uninstall"
    echo "5) Exit"
    read -p "Pilih: " CH
    case "$CH" in
      1) install_antirusuh ;;
      2) add_owner ;;
      3) del_owner ;;
      4) uninstall_antirusuh ;;
      5) exit 0 ;;
      *) echo "Pilihan tidak valid." ;;
    esac
  done
}

menu
