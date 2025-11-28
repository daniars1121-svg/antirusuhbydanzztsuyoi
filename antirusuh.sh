#!/usr/bin/env bash
set -euo pipefail

PTERO="/var/www/pterodactyl"
KERNEL="$PTERO/app/Http/Kernel.php"
API_CLIENT="$PTERO/routes/api-client.php"
ADMIN_MW="$PTERO/app/Http/Middleware/WhitelistAdmin.php"
CLIENT_MW="$PTERO/app/Http/Middleware/ClientLock.php"
BACKUP_DIR="$PTERO/antirusuh_backups"

banner(){
    cat <<'EOF'
==========================================
     ANTI RUSUH FINAL (Universal Safe)
==========================================
EOF
}

backup_file(){
    mkdir -p "$BACKUP_DIR"
    local f="$1"
    if [ -f "$f" ]; then
        local t="$BACKUP_DIR/$(basename "$f").bak.$(date +%s)"
        cp -a "$f" "$t"
        echo "Backup: $f -> $t"
    fi
}

install(){
    banner
    read -p "Masukkan ID Owner Utama (angka): " OWNER
    if ! [[ "$OWNER" =~ ^[0-9]+$ ]]; then
        echo "ID harus angka." >&2
        exit 1
    fi

    echo "[*] Membuat backup penting..."
    backup_file "$KERNEL"
    backup_file "$API_CLIENT"
    backup_file "$ADMIN_MW"
    backup_file "$CLIENT_MW"

    echo "[*] Membuat WhitelistAdmin middleware: $ADMIN_MW"
    mkdir -p "$(dirname "$ADMIN_MW")"
    cat > "$ADMIN_MW" <<EOF
<?php
namespace Pterodactyl\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

class WhitelistAdmin
{
    public function handle(Request \$request, Closure \$next)
    {
        // Owner list - injected by installer (string concatenation)
        \$allowed = [$OWNER];

        // Jika tidak login, lanjutkan (bukan tugas middleware ini)
        \$u = \$request->user();
        if (!\$u) {
            return \$next(\$request);
        }

        // Hanya cek path yang dimulai dengan admin/... untuk daftar blocked berikut.
        \$blockedPrefixes = [
            'admin/nodes',
            'admin/locations',
            'admin/mounts',
            'admin/nests',
            'admin/databases',
            'admin/servers'
        ];

        \$path = ltrim(\$request->path(), '/');

        foreach (\$blockedPrefixes as \$p) {
            // gunakan strpos untuk kompatibilitas PHP7/8
            if (strpos(\$path, \$p) === 0) {
                // jika bukan owner dan bukan root_admin -> abort
                if (!in_array(\$u->id, \$allowed) && empty(\$u->root_admin)) {
                    abort(403, 'ngapain wok');
                }
            }
        }

        return \$next(\$request);
    }
}
EOF

    echo "[*] Membuat ClientLock middleware: $CLIENT_MW"
    mkdir -p "$(dirname "$CLIENT_MW")"
    cat > "$CLIENT_MW" <<EOF
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

        if (!\$u) {
            // jika tidak login, blokir akses API client
            abort(403, 'ngapain wok');
        }

        // jika owner utama atau root admin -> izinkan
        if (in_array(\$u->id, \$allowed) || (!empty(\$u->root_admin) && \$u->root_admin)) {
            return \$next(\$request);
        }

        // jika route terkait server, pastikan owner server sama
        \$server = null;
        try {
            \$server = \$request->route()->parameter('server');
        } catch (\\Exception \$e) {
            // ignore
        }

        if (\$server && property_exists(\$server, 'owner_id') && \$server->owner_id != \$u->id) {
            abort(403, 'ngapain wok');
        }

        return \$next(\$request);
    }
}
EOF

    echo "[*] Menambahkan alias middleware ke Kernel (jika belum ada): $KERNEL"

    if ! grep -q "whitelistadmin" "$KERNEL"; then
        # tambahkan alias entries
        sed -i "/protected \$middlewareAliases = \[/a\        'whitelistadmin' => \\\\Pterodactyl\\\\Http\\\\Middleware\\\\WhitelistAdmin::class," "$KERNEL"
        echo "  -> whitelistadmin ditambahkan."
    else
        echo "  -> whitelistadmin sudah ada."
    fi

    if ! grep -q "clientlock" "$KERNEL"; then
        sed -i "/protected \$middlewareAliases = \[/a\        'clientlock' => \\\\App\\\\Http\\\\Middleware\\\\ClientLock::class," "$KERNEL"
        echo "  -> clientlock ditambahkan."
    else
        echo "  -> clientlock sudah ada."
    fi

    # Masukkan WhitelistAdmin ke web group — hanya jika belum ada.
    if ! grep -q "WhitelistAdmin::class" "$KERNEL"; then
        sed -i "/'web' => \[/a\            \\\\Pterodactyl\\\\Http\\\\Middleware\\\\WhitelistAdmin::class," "$KERNEL"
        echo "  -> WhitelistAdmin ditambahkan ke web group."
    else
        echo "  -> WhitelistAdmin sudah berada di web group."
    fi

    # Sisipkan clientlock ke api-client group /servers/{server} di routes/api-client.php
    if [ -f "$API_CLIENT" ]; then
        if ! grep -q "ClientLock::class" "$API_CLIENT"; then
            # masukkan ClientLock sebelum AuthenticateServerAccess::class, atau setelah ServerSubject::class
            perl -0777 -pe 's/(ServerSubject::class,\s*\n\s*)(AuthenticateServerAccess::class,)/$1\\\\App\\\\Http\\\\Middleware\\\\ClientLock::class,\n        $2/s' -i "$API_CLIENT" || true

            # jika pola di atas tidak mengganti (karena formatting), coba pola lain:
            if ! grep -q "ClientLock::class" "$API_CLIENT"; then
                perl -0777 -pe 's/(ServerSubject::class,\s*\n\s*)(ResourceBelongsToServer::class,)/$1\\\\App\\\\Http\\\\Middleware\\\\ClientLock::class,\n        $2/s' -i "$API_CLIENT" || true
            fi

            if grep -q "ClientLock::class" "$API_CLIENT"; then
                echo "  -> ClientLock disisipkan ke $API_CLIENT"
            else
                echo "  -> Gagal otomatis sisipkan ClientLock, file akan dibackup saja. Edarkan manual:"
                echo "     - Edit $API_CLIENT dan pada group prefix '/servers/{server}' tambahkan \\App\\Http\\Middleware\\ClientLock::class di array middleware."
            fi
        else
            echo "  -> ClientLock sudah ada di $API_CLIENT"
        fi
    else
        echo "  -> File $API_CLIENT tidak ditemukan, lewati modifikasi api-client."
    fi

    echo "[*] Membersihkan cache laravel (jika tersedia)..."
    if [ -d "$PTERO" ]; then
        cd "$PTERO" || true
        php artisan route:clear 2>/dev/null || true
        php artisan config:clear 2>/dev/null || true
        php artisan cache:clear 2>/dev/null || true
    fi

    # restart pteroq jika tersedia (jangan fail jika tidak ada)
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart pteroq 2>/dev/null || true
    fi

    echo "======================================"
    echo "ANTIRUSUH FINAL TERPASANG (SAFE MODE)"
    echo "Backup di: $BACKUP_DIR"
    echo "Jika masih ada route yang perlu disisipkan manual, periksa $API_CLIENT"
    echo "======================================"
}

uninstall(){
    banner
    echo "[*] Menghapus file middleware (tidak menghapus backup)..."
    rm -f "$ADMIN_MW" "$CLIENT_MW" || true

    if [ -f "$KERNEL" ]; then
        sed -i "/whitelistadmin/d" "$KERNEL" || true
        sed -i "/clientlock/d" "$KERNEL" || true
        # hapus entry class di web group
        sed -i "/Pterodactyl\\\\Http\\\\Middleware\\\\WhitelistAdmin::class/d" "$KERNEL" || true
    fi

    if [ -f "$API_CLIENT" ]; then
        # hapus clientlock dari api-client jika tersisip
        sed -i "s/, *'\\\\App\\\\Http\\\\Middleware\\\\ClientLock::class'//g" "$API_CLIENT" || true
        sed -i "s/\\\\App\\\\Http\\\\Middleware\\\\ClientLock::class, //g" "$API_CLIENT" || true
        sed -i "s/\\\\App\\\\Http\\\\Middleware\\\\ClientLock::class//g" "$API_CLIENT" || true
    fi

    if [ -d "$PTERO" ]; then
        cd "$PTERO" || true
        php artisan route:clear 2>/dev/null || true
        php artisan config:clear 2>/dev/null || true
        php artisan cache:clear 2>/dev/null || true
    fi

    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart pteroq 2>/dev/null || true
    fi

    echo "======================================"
    echo "ANTIRUSUH FINAL DIHAPUS (file backup masih ada di $BACKUP_DIR)"
    echo "Jika panel masih error, restore backup manual dari folder diatas."
    echo "======================================"
}

helpmsg(){
    cat <<'EOF'
Usage:
  installer: run and pilih '1' untuk install, '2' untuk uninstall
Notes:
  - Script ini membuat backup file yang diubah di $PTERO/antirusuh_backups
  - Jika ada error 500 setelah install, jalankan uninstall lalu kirimkan log laravel/storage/logs/laravel-*.log
EOF
}

# main menu if run interactively
if [ "${BASH_SOURCE[0]}" == "$0" ]; then
    echo
    echo "Anti-Rusuh FINAL installer"
    PS3="Pilih: "
    options=("Install" "Uninstall" "Exit")
    select opt in "${options[@]}"; do
        case $opt in
            "Install") install; break ;;
            "Uninstall") uninstall; break ;;
            "Exit") exit 0 ;;
            *) echo "Pilihan tidak valid." ;;
        esac
    done
fi
