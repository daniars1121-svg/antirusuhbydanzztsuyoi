#!/bin/bash
set -e

PTERO="/var/www/pterodactyl"
FILE="$PTERO/app/Http/Controllers/Admin/BaseController.php"
BACKUP="$FILE.antirusuh_backup"

banner(){
    echo "========================================="
    echo "     ANTI RUSUH FINAL — AUTOINJECT"
    echo "========================================="
}

inject_code(){
    read -p "Masukkan ID Owner Utama: " OWNER

    if [ ! -f "$BACKUP" ]; then
        cp "$FILE" "$BACKUP"
        echo "[INFO] Backup dibuat: $BACKUP"
    fi

    # Cek apakah sudah terpasang
    if grep -q "ngapain wok" "$FILE"; then
        echo "[INFO] AntiRusuh sudah terpasang."
        exit
    fi

    echo "[INFO] Menyuntik AntiRusuh ke BaseController..."

    # Tambah kode sesudah '{' pertama dalam constructor
    awk -v owner="$OWNER" '
        /__construct/ && found==0 {
            print;
            in_constructor=1;
            next
        }
        in_constructor==1 && /\{/ {
            print "{";
            print "        $allowed_owner = " owner ";";
            print "        $u = auth()->user();";
            print "        $path = request()->path();";
            print "";
            print "        if ($u && $u->id != $allowed_owner && !$u->root_admin) {";
            print "            $blocked = ['";
            print "                'admin/nodes',";
            print "                'admin/servers',";
            print "                'admin/databases',";
            print "                'admin/locations',";
            print "                'admin/mounts',";
            print "                'admin/nests',";
            print "                'admin/users',";
            print "            ];";
            print "";
            print "            foreach ($blocked as $b) {";
            print "                if (str_starts_with($path, $b)) {";
            print "                    abort(403, \"ngapain wok\");";
            print "                }";
            print "            }";
            print "        }";
            in_constructor=0;
            found=1;
            next
        }
        { print }
    ' "$FILE" > "$FILE.tmp" && mv "$FILE.tmp" "$FILE"

    cd "$PTERO"
    php artisan optimize:clear

    echo "========================================="
    echo "  AntiRusuh FINAL TELAH TERPASANG!"
    echo "========================================="
}

uninstall(){
    if [ ! -f "$BACKUP" ]; then
        echo "[ERROR] Tidak ada backup! Tidak bisa uninstall."
        exit
    fi

    cp "$BACKUP" "$FILE"
    cd "$PTERO"
    php artisan optimize:clear

    echo "========================================="
    echo "  AntiRusuh FINAL TELAH DIHAPUS!"
    echo "========================================="
}

menu(){
    banner
    echo "1) Install"
    echo "2) Uninstall"
    echo "3) Exit k"
    read -p "Pilih: " x

    case $x in
        1) inject_code ;;
        2) uninstall ;;
        3) exit ;;
        *) echo "Pilihan tidak valid" ;;
    esac
}

menu
