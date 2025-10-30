#!/bin/zsh
# Задача (macOS/Linux): удалить из папки SOURCE файлы, для которых в папке BACKUP
# существует файл с тем же относительным путем, тем же размером и той же датой создания
# (если на платформе недоступна дата создания — используется время изменения). Предполагается
# зеркальная структура каталогов: файлы сопоставляются по относительному пути
# (./sub/dir/file -> BACKUP/sub/dir/file).
#
# Важно:
# - На macOS (BSD stat): размер %z, дата создания (birth) %B
# - На Linux (GNU stat): размер %s, дата создания %W (может быть -1); при -1 — fallback на mtime %Y
# - Удаление подтверждается интерактивно (по требованию: «Ask Before Irreversible Operations»)
# - Имена файлов обрабатываются безопасно (нулевой разделитель)

# Запрос путей у пользователя
printf "Введите путь к SOURCE [по умолчанию текущая папка]: "
read -r SOURCE
[ -z "$SOURCE" ] && SOURCE="$PWD"

printf "Введите путь к BACKUP [по умолчанию /backup]: "
read -r BACKUP
[ -z "$BACKUP" ] && BACKUP="/backup"

if [ ! -d "$SOURCE" ]; then
    echo "SOURCE не найден: $SOURCE" >&2
    exit 1
fi
if [ ! -d "$BACKUP" ]; then
    echo "BACKUP не найден: $BACKUP" >&2
    exit 1
fi

# Проверка: SOURCE и BACKUP не должны совпадать
SOURCE_ABS=$(cd "$SOURCE" && pwd)
BACKUP_ABS=$(cd "$BACKUP" && pwd)
if [ "$SOURCE_ABS" = "$BACKUP_ABS" ]; then
    echo "ОШИБКА: SOURCE и BACKUP указывают на одну и ту же папку!" >&2
    echo "SOURCE: $SOURCE_ABS" >&2
    echo "BACKUP: $BACKUP_ABS" >&2
    exit 1
fi

# Определение диалекта stat
STAT_FLAVOR=""
if stat -f %z "/" >/dev/null 2>&1; then
    STAT_FLAVOR="bsd"   # macOS/BSD
elif stat -c %s "/" >/dev/null 2>&1; then
    STAT_FLAVOR="gnu"   # Linux/GNU
else
    echo "Неизвестный формат stat" >&2
    exit 1
fi

cd "$SOURCE" || exit 1

# Сбор кандидатов к удалению
tmp_list=$(mktemp)
find . -type f -print0 | while IFS= read -r -d '' file; do
    src="$file"
    dst="$BACKUP/$file"

    if [ -e "$dst" ]; then
        if [ "$STAT_FLAVOR" = "bsd" ]; then
            src_size=$(stat -f %z "$src")
            dst_size=$(stat -f %z "$dst")
            src_birth=$(stat -f %B "$src")
            dst_birth=$(stat -f %B "$dst")
            # На macOS %B всегда определен; сравниваем birth напрямую
            if [ "$src_size" = "$dst_size" ] && [ "$src_birth" = "$dst_birth" ]; then
                printf '%s\0' "$src"
            fi
        else
            # GNU stat: birth (%W) может быть -1. В таком случае fallback на mtime (%Y)
            src_size=$(stat -c %s "$src")
            dst_size=$(stat -c %s "$dst")
            src_birth=$(stat -c %W "$src")
            dst_birth=$(stat -c %W "$dst")
            if [ "$src_birth" != "-1" ] && [ "$dst_birth" != "-1" ]; then
                times_equal=[ "$src_birth" = "$dst_birth" ]
            else
                src_mtime=$(stat -c %Y "$src")
                dst_mtime=$(stat -c %Y "$dst")
                times_equal=[ "$src_mtime" = "$dst_mtime" ]
            fi
            if [ "$src_size" = "$dst_size" ] && eval $times_equal; then
                printf '%s\0' "$src"
            fi
        fi
    fi
done > "$tmp_list"

# Подтверждение перед удалением
count=$(tr -cd '\0' < "$tmp_list" | wc -c | tr -d ' ')
if [ "$count" -eq 0 ]; then
    echo "Совпадающих файлов не найдено."
    rm -f "$tmp_list"
    exit 0
fi

echo "Будут удалены $count файл(ов) из: $SOURCE"
printf "Продолжить удаление? [y/N]: "
read -r answer
case "$answer" in
    y|Y|yes|YES)
        : ;;
    *)
        echo "Отменено пользователем."
        rm -f "$tmp_list"
        exit 0
        ;;
esac

# Удаление
if [ "$count" -gt 0 ]; then
    xargs -0 rm -- < "$tmp_list"
fi
rm -f "$tmp_list"
echo "Удалено: $count файл(ов)."


