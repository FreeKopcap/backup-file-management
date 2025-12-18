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
printf "Введите маску файлов (например, log*), или Enter для всех файлов: "
read -r MASK

# Запрос директории у пользователя
printf "Введите путь к директории [по умолчанию текущая папка]: "
read -r TARGET_DIR
[ -z "$TARGET_DIR" ] && TARGET_DIR="$PWD"

# Раскрытие тильды в пути (~ -> $HOME)
if [[ "$TARGET_DIR" == ~* ]]; then
    TARGET_DIR="${TARGET_DIR/#\~/$HOME}"
fi

if [ ! -d "$TARGET_DIR" ]; then
    echo "Директория не найдена: $TARGET_DIR" >&2
    exit 1
fi

cd "$TARGET_DIR" || exit 1
TARGET_DIR_ABS=$(pwd)

# Сбор кандидатов к удалению: файлы нулевого размера, соответствующие маске
tmp_list=$(mktemp)
if [ -z "$MASK" ]; then
    # Если маска пустая, ищем все файлы нулевого размера
    find . -type f -size 0 -print0 > "$tmp_list"
    MASK_DESC="все файлы"
else
    # Если маска указана, используем её для фильтрации
    find . -type f -size 0 -name "$MASK" -print0 > "$tmp_list"
    MASK_DESC="маской '$MASK'"
fi

# Подсчет найденных файлов
count=$(tr -cd '\0' < "$tmp_list" | wc -c | tr -d ' ')
if [ "$count" -eq 0 ]; then
    if [ -z "$MASK" ]; then
        echo "Файлов нулевого размера не найдено."
    else
        echo "Файлов нулевого размера с маской '$MASK' не найдено."
    fi
    rm -f "$tmp_list"
    exit 0
fi

echo "Найдено $count файл(ов) нулевого размера с $MASK_DESC в: $TARGET_DIR_ABS"
echo "Список файлов для удаления:"
while IFS= read -r -d '' file; do
    # Преобразуем относительный путь в абсолютный
    full_path="${TARGET_DIR_ABS}/${file#./}"
    echo "  $full_path"
done < "$tmp_list"

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
        full_path="${TARGET_DIR_ABS}/${file#./}"
        if rm -- "$file" 2>/dev/null || rm "$file" 2>/dev/null; then
            deleted_count=$((deleted_count + 1))
            echo "Удален: $full_path"
        else
            echo "Ошибка при удалении: $full_path" >&2
        fi
    done < "$tmp_list"
else
    # Режим по умолчанию: подтверждение для каждого файла
    echo ""
    while IFS= read -r -d '' file <&3; do
        full_path="${TARGET_DIR_ABS}/${file#./}"
        printf "Удалить файл '%s'? [y/N]: " "$full_path"
        read -r answer < /dev/tty
        case "$answer" in
            y|Y|yes|YES)
                if rm -- "$file" 2>/dev/null || rm "$file" 2>/dev/null; then
                    deleted_count=$((deleted_count + 1))
                    echo "Удален: $full_path"
                else
                    echo "Ошибка при удалении: $full_path" >&2
                fi
                ;;
            *)
                echo "Пропущен: $full_path"
                ;;
        esac
    done 3< "$tmp_list"
fi

rm -f "$tmp_list"
echo ""
echo "Удалено: $deleted_count из $count файл(ов)."

