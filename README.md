# Транспортный модуль ДИОНИС (next generation)

TMWNG - это "высокоскоростной" транспортный модуль системы ДИОНИС, предназначен
для передачи информации серверу и получения информации с сервера.

Состав компонентов:

    tmwng/tmwng.sh - bash-скрипт, для запуска
    tmwng/tmwng.pl - perl-скрипт, реализующий приём/передачу

Для запуска TMWNG с периодичностью в 1 минуту, в /etc/crontab прописать:

    * * * * * USER /opt/tmw/tmwng.sh --sendpath=/opt/tmw/send --recvpath=/opt/tmw/recv 2>/tmp/tmwng.log

В качестве параметров `--sendpath` и `--recvpath` указать доступные на
чтение/запись пользователю каталоги передачи и приёма, соответственно.

# AUTHORS

Ilya V. Matveychikov <matvejchikov@gmail.com>
