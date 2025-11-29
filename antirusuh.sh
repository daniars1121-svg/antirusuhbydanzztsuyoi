#!/bin/bash

panel="/var/www/pterodactyl"
routes="$panel/routes"
kernel="$panel/app/Http/Kernel.php"
mw="$panel/app/Http/Middleware"
clientlock="$mw/ClientLock.php"

backup() {
    [ ! -f "$routes/admin.php.bak" ] && cp "$routes/admin.php" "$routes/admin.php.bak"
    [ ! -f "$routes/api-client.php.bak" ] && cp "$routes/api-client.php" "$routes/api-client.php.bak"
    [ ! -f "$kernel.bak" ] && cp "$kernel" "$kernel.bak"
}

restore() {
    [ -f "$routes/admin.php.bak" ] && cp "$routes/admin.php.bak" "$routes/admin.php"
    [ -f "$routes/api-client.php.bak" ] && cp "$routes/api-client.php.bak" "$routes/api-client.php"
    [ -f "$kernel.bak" ] && cp "$kernel.bak" "$kernel"
    rm -f "$clientlock"
    php $panel/artisan route:clear
    php $panel/artisan config:clear
}

install_all() {
backup

echo "<?php if (!auth()->user()?->root_admin) abort(403,'ngapain njir'); ?>" | cat - "$routes/admin.php" > "$routes/admin.php.tmp"
mv "$routes/admin.php.tmp" "$routes/admin.php"

sed -i "/'prefix' => '\/servers\/{server}'/a \ \ \ \ 'middleware' => ['clientlock']," "$routes/api-client.php"

sed -i "/protected \$middlewareAliases = \[/a \ \ \ \ 'clientlock' => App\\\\Http\\\\Middleware\\\\ClientLock::class," "$kernel"

cat <<EOF > $clientlock
<?php
namespace App\Http\Middleware;
use Closure;
class ClientLock{
public function handle(\$r, Closure \$n){
\$s=\$r->route('server');
if(\$s && \$r->user()->id!==\$s->owner_id) abort(403,'ngapain njir');
return \$n(\$r);
}}
EOF

php $panel/artisan route:clear
php $panel/artisan config:clear
}

menu() {
echo "1) Install"
echo "2) Uninstall"
echo "3) Exit"
read -p "" o
case $o in
1) install_all ;;
2) restore ;;
3) exit ;;
esac
}

menu
