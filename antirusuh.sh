#!/bin/bash
set -e

PTERO="/var/www/pterodactyl"
CTRL="$PTERO/app/Http/Controllers/Admin/BaseController.php"

banner(){
    echo "==============================="
    echo "    ANTI RUSUH FINAL 100% AKTIF"
    echo "==============================="
}

install(){
    banner
    read -p "Masukkan ID Owner Utama: " OWNER

    cp "$CTRL" "$CTRL.bak"

    # Tambahkan proteksi di constructor BaseController
    sed -i '/public function __construct()/a \
        \\t$u = auth()->user(); \
        \\tif($u && $u->id != '"$OWNER"' && !$u->root_admin){ \
        \\t\t$path = request()->path(); \
        \\t\t$block = ["admin/nodes","admin/servers","admin/databases","admin/locations","admin/mounts","admin/nests"]; \
        \\t\tforeach($block as $p){ \
        \\t\t\tif(strpos($path,$p)===0){ abort(403,"ngapain wok"); } \
        \\t\t} \
        \\t} \
    ' "$CTRL"

    cd $PTERO
    php artisan optimize:clear

    echo ""
    echo "==============================="
    echo "  ANTI RUSUH FINAL DIPASANG!"
    echo "==============================="
}

uninstall(){
    banner
    if [ -f "$CTRL.bak" ]; then
        mv "$CTRL.bak" "$CTRL"
        echo "[OK] BaseController dikembalikan"
    else
        echo "[!] Backup tidak ditemukan"
    fi

    cd $PTERO
    php artisan optimize:clear

    echo "==============================="
    echo "     ANTI RUSUH FINAL DIHAPUS"
    echo "==============================="
}

menu(){
    banner
    echo "1) Install"
    echo "2) Uninstall"
    echo "3) Exit"
    read -p "Pilih: " x

    case "$x" in
        1) install ;;
        2) uninstall ;;
        *) exit ;;
    esac
}

menu
