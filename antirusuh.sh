#!/bin/bash
set -e

PTERO="/var/www/pterodactyl"
FILE="$PTERO/app/Http/Controllers/Admin/BaseController.php"
BACKUP="$FILE.antirusuh_backup"

banner() {
    echo "========================================="
    echo "     ANTI RUSUH FINAL — AUTOINJECT v2"
    echo "========================================="
}

install_antirusuh() {
    read -p "Masukkan ID Owner Utama: " OWNER

    if [ ! -f "$BACKUP" ]; then
        cp "$FILE" "$BACKUP"
        echo "[INFO] Backup dibuat: $BACKUP"
    fi

    if grep -q "ngapain wok" "$FILE"; then
        echo "[INFO] AntiRusuh sudah terpasang!"
        exit 0
    fi

    echo "[INFO] Menyuntik AntiRusuh..."

    awk -v owner="$OWNER" '
        /__construct/ && !found {
            print $0
            in_ctor=1
            next
        }
        in_ctor && /\{/ {
            print "{"
            print "        /* Anti Rusuh Injected */"
            print "        $allowed_owner = " owner ";"
            print "        $u = auth()->user();"
            print "        $path = request()->path();"
            print ""
            print "        if ($u && $u->id != $allowed_owner && empty($u->root_admin)) {"
            print "            $blocked = ["
            print "                \"admin/nodes\","
            print "                \"admin/servers\","
            print "                \"admin/databases\","
            print "                \"admin/locations\","
            print "                \"admin/mounts\","
            print "                \"admin/nests\","
            print "                \"admin/users\""
            print "            ];"
            print ""
            print "            foreach ($blocked as $b) {"
            print "                if (str_starts_with($path, $b)) {"
            print "                    abort(403, \"ngapain wok\");"
            print "                }"
            print "            }"
            print "        }"
            in_ctor=0
            found=1
            next
        }
        { print }
    ' "$FILE" > "$FILE.tmp"

    mv "$FILE.tmp" "$FILE"

    cd "$PTERO"
    php artisan optimize:clear

    echo "========================================="
    echo "  AntiRusuh FINAL berhasil dipasang!"
    echo "========================================="
}

uninstall_antirusuh() {
    if [ ! -f "$BACKUP" ]; then
        echo "[ERROR] Tidak ada backup untuk restore."
        exit 1
    fi

    cp "$BACKUP" "$FILE"
    php $PTERO/artisan optimize:clear

    echo "========================================="
    echo "  AntiRusuh FINAL berhasil dihapus!"
    echo "========================================="
}

menu() {
    banner
    echo "1) Install"
    echo "2) Uninstall"
    echo "3) Exit"
    read -p "Pilih: " x

    case "$x" in
        1) install_antirusuh ;;
        2) uninstall_antirusuh ;;
        3) exit 0 ;;
        *) echo "Pilihan salah!" ;;
    esac
}

menu
