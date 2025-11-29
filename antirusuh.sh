#!/bin/bash
# Skrip instalasi AntiRusuh untuk Pterodactyl Panel
set -e

# Fungsi install middleware dan konfigurasi
install() {
    echo "Menginstall AntiRusuh middleware..."

    # 1. Tambahkan ANTIRUSUH_OWNER ke .env jika belum ada
    if ! grep -q "^ANTIRUSUH_OWNER=" .env; then
        echo "ANTIRUSUH_OWNER=1" >> .env
        echo "Menambahkan ANTIRUSUH_OWNER=1 ke .env"
    else
        echo "Variabel ANTIRUSUH_OWNER sudah ada di .env, lewati penambahan."
    fi

    # 2. Buat file Middleware AntiRusuh di app/Http/Middleware
    local mw_path="app/Http/Middleware/AntiRusuh.php"
    if [ -f "$mw_path" ]; then
        echo "Middleware AntiRusuh sudah ada, lewati pembuatan file."
    else
        cat > "$mw_path" << 'EOF'
<?php

namespace Pterodactyl\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpKernel\Exception\AccessDeniedHttpException;

class AntiRusuh
{
    /**
     * Handle an incoming request.
     *
     * Hanya memperbolehkan user dengan ID sesuai ANTIRUSUH_OWNER di .env untuk akses.
     *
     * @param  \Illuminate\Http\Request  $request
     * @param  \Closure  $next
     * @return mixed
     *
     * @throws \Symfony\Component\HttpKernel\Exception\AccessDeniedHttpException
     */
    public function handle(Request $request, Closure $next)
    {
        $ownerId = env('ANTIRUSUH_OWNER');
        $user = $request->user();
        if (!$user || (string)$user->id !== (string)$ownerId) {
            // Jika bukan user pemilik, tolak akses dengan 403
            throw new AccessDeniedHttpException('Akses terbatas untuk user tertentu.');
        }
        return $next($request);
    }
}
EOF
        echo "Middleware AntiRusuh dibuat di $mw_path"
    fi

    # 3. Daftarkan alias middleware di Kernel (app/Http/Kernel.php)
    local kernel="app/Http/Kernel.php"
    if grep -q "AntiRusuh::class" "$kernel"; then
        echo "Alias AntiRusuh sudah terdaftar di Kernel, lewati penambahan."
    else
        # Tambahkan pernyataan use di Kernel
        sed -i "/use Pterodactyl\\\\Http\\\\Middleware\\\\VerifyReCaptcha/a use Pterodactyl\\\\Http\\\\Middleware\\\\AntiRusuh;" "$kernel"
        # Tambahkan alias routeMiddleware
        sed -i "/'recaptcha' => VerifyReCaptcha::class,/a \            'antirusuh' => \\Pterodactyl\\Http\\Middleware\\AntiRusuh::class," "$kernel"
        echo "Alias 'antirusuh' ditambahkan ke Kernel."
    fi

    # 4. Modifikasi routes/admin.php untuk melindungi route admin
    local routes="routes/admin.php"
    # Cek apakah sudah memiliki group antirusuh
    if grep -q "middleware' => \['antirusuh'\]" "$routes"; then
        echo "Route admin sudah menggunakan middleware antirusuh, lewati modifikasi."
    else
        # Masukkan route group dengan middleware sebelum rute admin pertama
        sed -i "/^Route::get.*admin.index/ i Route::group(['middleware' => ['antirusuh']], function () {" "$routes"
        # Tutup kurung setelah rute admin terakhir
        sed -i "/->where('react'/a });" "$routes"
        echo "Route admin dibungkus dengan Route::group middleware antirusuh."
    fi

    echo "Instalasi AntiRusuh selesai."
}

# Fungsi uninstall: hapus perubahan dan file
uninstall() {
    echo "Menghapus AntiRusuh middleware..."

    # 1. Hapus variabel ANTIRUSUH_OWNER di .env
    if grep -q "^ANTIRUSUH_OWNER=" .env; then
        sed -i "/^ANTIRUSUH_OWNER=/d" .env
        echo "Variabel ANTIRUSUH_OWNER dihapus dari .env"
    else
        echo "Variabel ANTIRUSUH_OWNER tidak ditemukan di .env"
    fi

    # 2. Hapus file Middleware AntiRusuh
    local mw_path="app/Http/Middleware/AntiRusuh.php"
    if [ -f "$mw_path" ]; then
        rm "$mw_path"
        echo "File $mw_path dihapus."
    else
        echo "File $mw_path tidak ditemukan, lewati penghapusan."
    fi

    # 3. Hapus alias di Kernel
    local kernel="app/Http/Kernel.php"
    sed -i "/use Pterodactyl\\\\Http\\\\Middleware\\\\AntiRusuh;/d" "$kernel"
    sed -i "/'antirusuh' => \\\\Pterodactyl\\\\Http\\\\Middleware\\\\AntiRusuh::class,/d" "$kernel"
    echo "Alias 'antirusuh' di Kernel dihapus."

    # 4. Kembalikan routes/admin.php seperti semula
    local routes="routes/admin.php"
    sed -i "/Route::group\|\['middleware' \=> \['antirusuh'\]\]/d" "$routes"
    sed -i "/^});/d" "$routes"
    echo "Modifikasi routes/admin.php dikembalikan."

    echo "Uninstall AntiRusuh selesai."
}

# Eksekusi fungsi sesuai argumen
case "$1" in
    install)
        install
        ;;
    uninstall)
        uninstall
        ;;
    *)
        echo "Gunakan: $0 {install|uninstall}"
        exit 1
        ;;
esac
