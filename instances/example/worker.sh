#!/bin/sh
echo "Starting Nextcloud AI Worker"
while true; do
  su -p www-data -s /bin/sh -c "php /var/www/html/occ taskprocessing:worker -v -t 60"
  sleep 1
done
