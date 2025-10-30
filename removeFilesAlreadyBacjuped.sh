#!/bin/zsh
# Задача (macOS): удалить из папки SOURCE все файлы, для которых в папке BACKUP
# существует файл с тем же относительным путем, тем же размером и той же датой
# создания (birth time). Предполагается зеркальная структура каталогов: файлы
# ищутся по совпадению относительного пути (./sub/dir/file -> BACKUP/sub/dir/file).
#
# Важно:
# - macOS использует BSD stat; для размера и даты создания используем: %z (size), %B (birth time)
# - Сравнивается именно дата создания (birth time), а не время изменения (mtime)
# - Имена файлов обрабатываются безопасно (нулевой разделитель)

SOURCE="/source"
BACKUP="/backup"

cd "$SOURCE" || exit 1

find . -type f -print0 | while IFS= read -r -d '' file; do
    src="$file"
    dst="$BACKUP/$file"

    if [ -e "$dst" ]; then
        src_size=$(stat -f %z "$src")
        dst_size=$(stat -f %z "$dst")

        # %B — birth time (дата создания) в секундах на macOS/BSD
        src_birth=$(stat -f %B "$src")
        dst_birth=$(stat -f %B "$dst")

        if [ "$src_size" = "$dst_size" ] && [ "$src_birth" = "$dst_birth" ]; then
            rm -- "$src"
        fi
    fi
done

