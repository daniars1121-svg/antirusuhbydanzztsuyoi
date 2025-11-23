#!/bin/bash
set -e
clear

PANEL="/var/www/pterodactyl"
KERNEL="$PANEL/app/Http/Kernel.php"
CONFIG="$PANEL/config/antirusuh.php"
MIDDLE="$PANEL/app/Http/Middleware/AntiRusuh.php"

menu() {
  clear
  echo "1) Install AntiRusuh tsuyoi"
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
    0) exit ;;
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

# INJECT KE GROUP 'panel' BUKAN KE ROUTES
if ! grep -q "AntiRusuh::class" "$KERNEL"; then
  sed -i "/'panel' => \[/a\            \App\Http\Middleware\AntiRusuh::class," "$KERNEL"
fi

cd "$PANEL"
php artisan optimize:clear

echo "AntiRusuh berhasil dipasang!"
sleep 1
menu
}

uninstall() {

rm -f "$CONFIG" "$MIDDLE"

sed -i "/AntiRusuh/d" "$KERNEL"

cd "$PANEL"
php artisan optimize:clear

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
  php artisan tinker --execute="print_r(config('antirusuh.owners'));"
  read -p "Enter untuk lanjut..."
  owner_menu
}

add_owner() {
  clear
  USERS=$(php artisan db:query "SELECT id, username FROM users" --json)

  INDEX=1
  echo "Daftar User Panel:"
  echo "$USERS" | jq -c '.[]' | while read -r row; do
    echo "$INDEX) $(echo $row | jq -r '.username')"
    INDEX=$((INDEX+1))
  done

  read -p "Pilih nomor user: " N
  SELECTED=$(echo "$USERS" | jq -r ".[$((N-1))].username")

  if [ "$SELECTED" != "null" ]; then
    sed -i "/'owners' => \[/a\\        '$SELECTED'," "$CONFIG"
    echo "Owner ditambahkan: $SELECTED"
  else
    echo "Pilihan tidak valid"
  fi

  sleep 1
  owner_menu
}

del_owner() {
  clear
  OWNERS=$(php artisan tinker --execute="echo json_encode(config('antirusuh.owners'));")

  INDEX=1
  echo "Owner saat ini:"
  echo "$OWNERS" | jq -c '.[]' | while read -r row; do
    echo "$INDEX) $row"
    INDEX=$((INDEX+1))
  done

  read -p "Pilih nomor owner yang ingin dihapus: " R
  TARGET=$(echo "$OWNERS" | jq -r ".[$((R-1))]")

  if [ "$TARGET" != "null" ]; then
    sed -i "/'$TARGET'/d" "$CONFIG"
    echo "Owner dihapus: $TARGET"
  else
    echo "Pilihan tidak valid"
  fi

  sleep 1
  owner_menu
}

update_antirusuh() {
  clear
  echo "Mengambil update terbaru..."

  REPO="https://raw.githubusercontent.com/daniars1121-svg/antirusuhbydanzztsuyoi/main/antirusuh.sh"

  curl -s "$REPO" -o /root/antirusuh_update.sh

  chmod +x /root/antirusuh_update.sh
  bash /root/antirusuh_update.sh
  exit
}

menu
