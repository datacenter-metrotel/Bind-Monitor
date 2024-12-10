Mecanismo de chequeo de dispibilidad de Bind en clusteres de Resolvers

Instalación:

cd /usr/local/bin
wget --inet4-only https://raw.githubusercontent.com/datacenter-metrotel/Bind-Monitor/refs/heads/main/monitor_bind.sh
chmod +x monitor_bind.sh
crontab -e
*/1 * * * * /usr/local/bin/monitor_bind.sh
