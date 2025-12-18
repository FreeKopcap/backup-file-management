#!/bin/zsh
# Удалить файлы нулевого размера определенной маски из директории
# (рекурсивно, включая поддиректории)
#
# Важно:
# - Удаление подтверждается интерактивно (по требованию: «Ask Before Irreversible Operations»)
# - Имена файлов обрабатываются безопасно (нулевой разделитель)
# - По умолчанию: подтверждение для каждого файла
# - С опцией -y/--yes: удаление без подтверждений, но список файлов выводится
# - С опцией -n/--dry-run: только показ списка файлов без удаления

# Обработка опций
YES_MODE=false
DRY_RUN=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -y|--yes)
            YES_MODE=true
            shift
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            echo "Неизвестная опция: $1" >&2
            echo "Использование: $0 [-y|--yes] [-n|--dry-run]" >&2
            exit 1
            ;;
    esac
done

# Запрос маски у пользователя
printf "Введите маску файлов (например, log*): "
read -r MASK
if [ -z "$MASK" ]; then
    echo "Маска не может быть пустой!" >&2
    exit 1
fi

# Запрос директории у пользователя
printf "Введите путь к директории [по умолчанию текущая папка]: "
read -r TARGET_DIR
[ -z "$TARGET_DIR" ] && TARGET_DIR="$PWD"

if [ ! -d "$TARGET_DIR" ]; then
    echo "Директория не найдена: $TARGET_DIR" >&2
    exit 1
fi

cd "$TARGET_DIR" || exit 1

# Сбор кандидатов к удалению: файлы нулевого размера, соответствующие маске
tmp_list=$(mktemp)
find . -type f -size 0 -name "$MASK" -print0 > "$tmp_list"

# Подсчет найденных файлов
count=$(tr -cd '\0' < "$tmp_list" | wc -c | tr -d ' ')
if [ "$count" -eq 0 ]; then
    echo "Файлов нулевого размера с маской '$MASK' не найдено."
    rm -f "$tmp_list"
    exit 0
fi

echo "Найдено $count файл(ов) нулевого размера с маской '$MASK' в: $TARGET_DIR"
echo "Список файлов для удаления:"
find . -type f -size 0 -name "$MASK" | sed 's/^/  /'

# Режим сухого прогона: только показываем список, не удаляем
if [ "$DRY_RUN" = true ]; then
    echo ""
    echo "РЕЖИМ СУХОГО ПРОГОНА: файлы НЕ будут удалены"
    echo "Были бы удалены: $count файл(ов)"
    rm -f "$tmp_list"
    exit 0
fi

# Удаление
deleted_count=0
if [ "$YES_MODE" = true ]; then
    # Режим -y: удаляем все без подтверждений
    echo ""
    echo "Удаление файлов (без подтверждения)..."
    while IFS= read -r -d '' file; do
        if rm -- "$file" 2>/dev/null || rm "$file" 2>/dev/null; then
            deleted_count=$((deleted_count + 1))
            echo "Удален: $file"
        else
            echo "Ошибка при удалении: $file" >&2
        fi
    done < "$tmp_list"
else
    # Режим по умолчанию: подтверждение для каждого файла
    echo ""
    while IFS= read -r -d '' file; do
        printf "Удалить файл '%s'? [y/N]: " "$file"
        read -r answer
        case "$answer" in
            y|Y|yes|YES)
                if rm -- "$file" 2>/dev/null || rm "$file" 2>/dev/null; then
                    deleted_count=$((deleted_count + 1))
                    echo "Удален: $file"
                else
                    echo "Ошибка при удалении: $file" >&2
                fi
                ;;
            *)
                echo "Пропущен: $file"
                ;;
        esac
    done < "$tmp_list"
fi

rm -f "$tmp_list"
echo ""
echo "Удалено: $deleted_count из $count файл(ов)."

