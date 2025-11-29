#!/bin/bash
set -euo pipefail

PTERO="/var/www/pterodactyl"
BACKUP_DIR="$PTERO/antirusuh_backup_$(date +%s)"
PROVIDER="$PTERO/app/Providers/AntiRusuhServiceProvider.php"
MIDDLEWARE="$PTERO/app/Http/Middleware/AntiRusuh.php"
CONFIG_APP="$PTERO/config/app.php"
ENV_FILE="$PTERO/.env"

banner(){
cat <<'EOF'
===========================================
    ANTI RUSUH — INSTALLER FINAL (SAFE)
    Install / Uninstall tanpa rusak routes
===========================================
EOF
}

require_root(){
  if [ "$(id -u)" -ne 0 ]; then
    echo "Harus dijalankan sebagai root. gunakan: sudo bash $0"
    exit 1
  fi
}

backup_file(){
  local f="$1"
  mkdir -p "$BACKUP_DIR"
  if [ -f "$f" ]; then
    cp -a "$f" "$BACKUP_DIR/"
  fi
}

install(){
  banner
  require_root

  read -p "Masukkan ID Owner utama (angka). kosong = 1 : " OWNER
  if [ -z "$OWNER" ]; then OWNER=1; fi
  if ! [[ "$OWNER" =~ ^[0-9]+$ ]]; then
    echo "ID harus angka"; exit 1
  fi

  echo "[*] Membuat backup di: $BACKUP_DIR"
  mkdir -p "$BACKUP_DIR"
  backup_file "$CONFIG_APP"
  backup_file "$PROVIDER"
  backup_file "$MIDDLEWARE"
  backup_file "$ENV_FILE"

  echo "[*] Menulis file middleware: $MIDDLEWARE"
  mkdir -p "$(dirname "$MIDDLEWARE")"
  cat > "$MIDDLEWARE" <<PHP
<?php

namespace Pterodactyl\Http\Middleware;

use Closure;

class AntiRusuh
{
    public function handle(\$request, Closure \$next)
    {
        // Ambil owner dari env, fallback ke 1
        \$owner = intval(env('ANTI_RUSUH_OWNER', ${OWNER}));

        \$u = \$request->user();
        if (!\$u) {
            return \$next(\$request);
        }

        // proteksi halaman admin tertentu (hanya contoh: nodes, servers, databases, locations, mounts, nests)
        \$path = ltrim(\$request->path(), '/');

        \$protectedPrefixes = [
            'admin/nodes',
            'admin/servers',
            'admin/databases',
            'admin/locations',
            'admin/mounts',
            'admin/nests',
        ];

        foreach (\$protectedPrefixes as \$p) {
            if (strpos(\$path, \$p) === 0) {
                if (\$u->id !== \$owner && empty(\$u->root_admin)) {
                    abort(403, 'ngapain wok');
                }
            }
        }

        // proteksi akses server milik orang lain lewat routes yang membawa parameter server
        if (\$request->route() && \$request->route()->parameter('server')) {
            \$server = \$request->route()->parameter('server');
            if (isset(\$server->owner_id)) {
                if (\$server->owner_id !== \$u->id && empty(\$u->root_admin) && \$u->id !== \$owner) {
                    abort(403, 'ngapain wok');
                }
            }
        }

        return \$next(\$request);
    }
}
PHP

  echo "[*] Menulis ServiceProvider: $PROVIDER"
  mkdir -p "$(dirname "$PROVIDER")"
  cat > "$PROVIDER" <<'PHP'
<?php

namespace App\Providers;

use Illuminate\Support\ServiceProvider;

class AntiRusuhServiceProvider extends ServiceProvider
{
    public function register()
    {
        //
    }

    public function boot()
    {
        // daftar alias middleware dan prepend ke grup web
        if (app()->bound('router')) {
            app('router')->aliasMiddleware('antirusuh', \Pterodactyl\Http\Middleware\AntiRusuh::class);

            // prepend ke 'web' group jika grup ada
            try {
                app('router')->prependMiddlewareToGroup('web', 'antirusuh');
            } catch (\Throwable $e) {
                // jika gagal, jangan crash installer; kernel mungkin beda struktur
            }
        }
    }
}
PHP

  # Tambah provider ke config/app.php jika belum ada
  if grep -q "App\\\Providers\\\AntiRusuhServiceProvider" "$CONFIG_APP" 2>/dev/null; then
    echo "[*] ServiceProvider sudah terdaftar di $CONFIG_APP"
  else
    echo "[*] Mencoba mendaftarkan ServiceProvider di $CONFIG_APP (backup dibuat)"
    # safe insert: cari array 'providers' => [  ... ] dan sebelum penutup '],' masukkan line
    perl -0777 -pe 'if (/\bproviders\s*=>\s*\[.*?\]/s) { s/(providers\s*=>\s*\[)(.*?)(\n\s*\],)/$1$2\n        App\\\Providers\\\AntiRusuhServiceProvider::class, $3/s }' -i "$CONFIG_APP" || true
    # fallback append (if perl failed)
    if ! grep -q "App\\\Providers\\\AntiRusuhServiceProvider" "$CONFIG_APP"; then
      # append near top: after "return [" we try to add to providers
      sed -n '1,240p' "$CONFIG_APP" > /tmp/_cfg_head.$$ || true
      echo "" >> /tmp/_cfg_head.$$ 
      echo "/* AntiRusuhServiceProvider auto-added */" >> /tmp/_cfg_head.$$
      echo "App\\\Providers\\\AntiRusuhServiceProvider::class," >> /tmp/_cfg_head.$$
      cat /tmp/_cfg_head.$$ > "$CONFIG_APP" || true
      rm -f /tmp/_cfg_head.$$
    fi
  fi

  # set env var if not exists
  if [ -f "$ENV_FILE" ]; then
    if grep -q "^ANTI_RUSUH_OWNER=" "$ENV_FILE"; then
      sed -i "s/^ANTI_RUSUH_OWNER=.*/ANTI_RUSUH_OWNER=${OWNER}/" "$ENV_FILE"
    else
      echo "ANTI_RUSUH_OWNER=${OWNER}" >> "$ENV_FILE"
    fi
  else
    echo "ANTI_RUSUH_OWNER=${OWNER}" > "$ENV_FILE"
  fi

  echo "[*] Menjalankan: php artisan optimize:clear"
  (cd "$PTERO" && php artisan optimize:clear) || true

  echo "========================================"
  echo "  INSTALL SELESAI. Owner = $OWNER"
  echo "  - Jika ingin ubah owner: edit $ENV_FILE -> ANTI_RUSUH_OWNER"
  echo "  - Untuk uninstall jalankan lagi script dan pilih Uninstall"
  echo "========================================"
}

uninstall(){
  banner
  require_root

  echo "[*] Mencari backup: $BACKUP_DIR (tidak ada jika sebelumnya berbeda run)"
  # restore files jika ada di backup (agar safe)
  if [ -d "$BACKUP_DIR" ]; then
    cp -a "$BACKUP_DIR/"* "$PTERO/" || true
  fi

  echo "[*] Menghapus file service provider & middleware"
  rm -f "$PROVIDER" "$MIDDLEWARE"

  # Hapus provider dari config/app.php (hapus baris yang mengandung AntiRusuhServiceProvider)
  if [ -f "$CONFIG_APP" ]; then
    sed -i "/AntiRusuhServiceProvider/d" "$CONFIG_APP" || true
  fi

  # Hapus var env
  if [ -f "$ENV_FILE" ]; then
    sed -i "/^ANTI_RUSUH_OWNER=/d" "$ENV_FILE" || true
  fi

  echo "[*] Jalankan optimize:clear"
  (cd "$PTERO" && php artisan optimize:clear) || true

  echo "========================================"
  echo "  UNINSTALL SELESAI. (files removed)"
  echo "========================================"
}

menu(){
  banner
  PS3="Pilih aksi: "
  options=("Install" "Uninstall" "Exit")
  select opt in "${options[@]}"; do
    case $opt in
      "Install") install; break ;;
      "Uninstall") uninstall; break ;;
      "Exit") exit 0 ;;
      *) echo "Pilihan tidak valid." ;;
    esac
  done
}

menu
