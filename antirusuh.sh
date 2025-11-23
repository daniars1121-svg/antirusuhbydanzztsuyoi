#!/bin/bash
set -e
clear

PANEL="/var/www/pterodactyl"
KERNEL="$PANEL/app/Http/Kernel.php"
CONFIG="$PANEL/config/antirusuh.php"
MIDDLE="$PANEL/app/Http/Middleware/AntiRusuh.php"

# ensure panel folder exists
if [ ! -d "$PANEL" ]; then
  echo "Panel tidak ditemukan di $PANEL"
  exit 1
fi

# helper: run artisan inside panel dir
run_artisan() {
  (cd "$PANEL" && php artisan "$@")
}

menu() {
  clear
  echo "1) Install AntiRusuh by danz anjay"
  echo "2) Uninstall AntiRusuh"
  echo "3) Kelola Owner"
  echo "4) Update AntiRusuh (Auto GitHub)"
  echo "0) Keluar"
  read -p "Pilih: " M
  case $M in
    1) install ;;
    2) uninstall ;;
    3) owner_menu ;;
    4) update_antirusuh ;;
    0) exit 0 ;;
    *) menu ;;
  esac
}

install() {
  mkdir -p "$PANEL/config"
  mkdir -p "$PANEL/app/Http/Middleware"

  rm -f "$CONFIG" "$MIDDLE"

  cat > "$CONFIG" <<EOF
<?php
return [
  'owners' => [
    '$(logname)'
  ]
];
EOF

  cat > "$MIDDLE" <<'EOF'
<?php
namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;

class AntiRusuh
{
    public function handle(Request $request, Closure $next)
    {
        $u = Auth::user();
        if (!$u) return $next($request);

        $owners = config('antirusuh.owners', []);
        $isOwner = in_array($u->username ?? $u->email, $owners, true);

        $uri = $request->path();

        $deny = [
            "admin/locations",
            "admin/nodes",
            "admin/servers/*/build",
            "admin/servers/*/network",
            "nodes/*"
        ];

        foreach ($deny as $d) {
            $rg = '#^' . str_replace('\*','.*',preg_quote($d,'#')) . '$#';
            if (preg_match($rg,$uri)) {
                if (!$isOwner) return abort(403,"AntiRusuh aktif.");
            }
        }

        if (preg_match('#^server/([a-zA-Z0-9-]+)#',$uri,$m)) {
            $id = $m[1];
            try {
                $s=\App\Models\Server::where('uuid',$id)
                    ->orWhere('uuidShort',$id)->first();
                if ($s && $s->owner_id !== $u->id && !$isOwner)
                    return abort(403,"AntiRusuh: akses server orang diblokir.");
            } catch (\Throwable $e) {}
        }

        return $next($request);
    }
}
EOF

  # inject middleware: try middlewareAliases first, then 'panel' group
  if grep -q "protected \$middlewareAliases" "$KERNEL"; then
    if ! grep -q "antirusuh" "$KERNEL"; then
      sed -i "/protected \$middlewareAliases = \[/a\        'antirusuh' => \App\Http\Middleware\AntiRusuh::class," "$KERNEL"
      echo "Middleware alias 'antirusuh' ditambahkan ke Kernel."
    else
      echo "Middleware alias 'antirusuh' sudah ada di Kernel."
    fi
  fi

  # if there's a 'panel' middleware group, insert the class into it (avoid duplicates)
  if grep -q "'panel' => \[" "$KERNEL"; then
    if ! grep -q "App\\\\Http\\\\Middleware\\\\AntiRusuh::class" "$KERNEL"; then
      sed -i "/'panel' => \[/a\            \\App\\Http\\Middleware\\AntiRusuh::class," "$KERNEL"
      echo "AntiRusuh class ditambahkan ke group 'panel'."
    else
      echo "AntiRusuh class sudah ada di group 'panel'."
    fi
  fi

  # clear caches from inside panel dir to ensure kernel/config reload
  echo "Membersihkan cache Laravel..."
  run_artisan optimize:clear || true
  run_artisan config:cache || true

  echo "AntiRusuh berhasil dipasang!"
  sleep 1
  menu
}

uninstall() {
  rm -f "$CONFIG" "$MIDDLE"

  # remove alias and class mentions
  sed -i "/antirusuh/d" "$KERNEL"
  sed -i "/App\\\\Http\\\\Middleware\\\\AntiRusuh::class/d" "$KERNEL"

  # clear caches
  run_artisan optimize:clear || true

  echo "AntiRusuh dihapus!"
  sleep 1
  menu
}

owner_menu() {
  clear
  echo "1) Lihat Owner"
  echo "2) Tambah Owner dari User Panel"
  echo "3) Hapus Owner"
  echo "0) Kembali"
  read -p "Pilih: " O

  case $O in
    1) list_owner ;;
    2) add_owner ;;
    3) del_owner ;;
    0) menu ;;
    *) owner_menu ;;
  esac
}

list_owner() {
  clear
  run_artisan tinker --execute="print_r(config('antirusuh.owners'))" || echo "Gagal menampilkan owner (artisan)."
  read -p "Enter untuk lanjut..."
  owner_menu
}

add_owner() {
  clear
  # try db:query --json (clean output). If fails, fallback to tinker but filter non-json.
  USERS_JSON=""
  if (cd "$PANEL" && php artisan help db:query >/dev/null 2>&1); then
    USERS_JSON=$(cd "$PANEL" && php artisan db:query "SELECT id, username FROM users" --json 2>/dev/null || true)
  fi

  if [ -z "$USERS_JSON" ]; then
    # fallback: use tinker but attempt to output pure json
    USERS_JSON=$(cd "$PANEL" && php artisan tinker --execute="echo json_encode(\App\Models\User::select(['id','username'])->get());" 2>/dev/null || true)
    # strip non-json lines (attempt)
    USERS_JSON=$(echo "$USERS_JSON" | sed -n '/^\[/{p;:a;N;/\]$/!ba;p}')
  fi

  if [ -z "$USERS_JSON" ]; then
    echo "Gagal mengambil daftar user."
    sleep 1
    owner_menu
    return
  fi

  # ensure jq available, otherwise use simple awk parsing
  if ! command -v jq >/dev/null 2>&1; then
    echo "jq tidak ditemukan, akan dipasang (minta sudo jika perlu)..."
    if command -v apt >/dev/null 2>&1; then
      apt update && apt install -y jq || true
    fi
  fi

  echo "Daftar User Panel:"
  if command -v jq >/dev/null 2>&1; then
    echo "$USERS_JSON" | jq -c '.[]' | nl -w2 -s') '
  else
    # naive listing: show lines with username
    echo "$USERS_JSON"
  fi

  read -p "Pilih nomor user: " N
  if command -v jq >/dev/null 2>&1; then
    SELECTED=$(echo "$USERS_JSON" | jq -r ".[$((N-1))].username" 2>/dev/null || echo "")
  else
    SELECTED=$(echo "$USERS_JSON" | sed -n "$N p" | sed -E "s/.*\"username\"\s*:\s*\"([^\"]+)\".*/\1/")
  fi

  if [ -n "$SELECTED" ] && [ "$SELECTED" != "null" ]; then
    # ensure config exists
    if [ ! -f "$CONFIG" ]; then
      cat > "$CONFIG" <<EOF
<?php
return [
  'owners' => []
];
EOF
    fi
    sed -i "/'owners' => \[/a\\        '$SELECTED'," "$CONFIG"
    echo "Owner ditambahkan: $SELECTED"
  else
    echo "Pilihan tidak valid."
  fi

  sleep 1
  owner_menu
}

del_owner() {
  clear
  OWNERS=$(cd "$PANEL" && php artisan tinker --execute="echo json_encode(config('antirusuh.owners'))" 2>/dev/null || echo "[]")
  if command -v jq >/dev/null 2>&1; then
    echo "$OWNERS" | jq -c '.[]' | nl -w2 -s') '
  else
    echo "$OWNERS"
  fi

  read -p "Pilih nomor owner yang ingin dihapus: " R
  if command -v jq >/dev/null 2>&1; then
    TARGET=$(echo "$OWNERS" | jq -r ".[$((R-1))]" 2>/dev/null || echo "")
  else
    TARGET=$(echo "$OWNERS" | sed -n "$R p" | sed -E "s/^[0-9[:space:]]*//")
  fi

  if [ -n "$TARGET" ] && [ "$TARGET" != "null" ]; then
    sed -i "/'$TARGET'/d" "$CONFIG"
    echo "Owner dihapus: $TARGET"
  else
    echo "Pilihan tidak valid."
  fi

  sleep 1
  owner_menu
}

update_antirusuh() {
  clear
  echo "Mengambil update terbaru..."

  REPO="https://raw.githubusercontent.com/daniars1121-svg/antirusuhbydanzztsuyoi/main/antirusuh.sh"

  curl -fsSL "$REPO" -o /root/antirusuh_update.sh || { echo "Gagal mendownload update"; sleep 1; menu; }
  chmod +x /root/antirusuh_update.sh
  bash /root/antirusuh_update.sh
  exit 0
}

menu
