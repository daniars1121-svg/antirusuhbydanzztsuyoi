#!/bin/bash

FILE="/var/www/pterodactyl/routes/admin.php"

if [ ! -f "$FILE" ]; then
    exit 0
fi

if ! grep -q "owner.menu" "$FILE"; then
    sed -i '1s/^/Route::middleware(["auth","owner.menu"])->group(function() { \n/' "$FILE"
    echo "});" >> "$FILE"
fi
