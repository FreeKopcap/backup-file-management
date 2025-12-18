#!/bin/zsh
# Удалить файлы нулевого размера определенной маски из директории
# (рекурсивно, включая поддиректории)
#
# Важно:
# - Удаление подтверждается интерактивно (по требованию: «Ask Before Irreversible Operations»)
# - Имена файлов обрабатываются безопасно (нулевой разделитель)
# - По умолчанию: подтверждение для каждого файла/директории
# - С опцией -y/--yes: удаление без подтверждений, но список объектов выводится
# - С опцией -n/--dry-run: только показ списка объектов без удаления
# - С опцией -d/--directory: вместо файлов удаляются директории, в которых (и в поддиректориях) нет ни одного файла

print_help() {
    cat <<EOF
Использование: $SCRIPT_NAME [-y|--yes] [-n|--dry-run] [-d|--directory]

Без опций:
  - удаляются файлы нулевого размера (по маске или все), с подтверждением для каждого

Опции:
  -y, --yes        Удалять без подтверждений (список файлов/директорий все равно выводится)
  -n, --dry-run    Сухой прогон — только показать, что было бы удалено, без фактического удаления
  -d, --directory  Вместо файлов удалять директории, в которых (и поддиректориях) нет ни одного файла
  -h, --help       Показать эту справку и выйти

Примеры:
  $SCRIPT_NAME
  $SCRIPT_NAME -y
  $SCRIPT_NAME -n
  $SCRIPT_NAME -d
EOF
}

# Обработка опций
SCRIPT_NAME=${0##*/}
YES_MODE=false
DRY_RUN=false
DIR_MODE=false

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
        -d|--directory)
            DIR_MODE=true
            shift
            ;;
        -h|--help)
            print_help
            exit 0
            ;;
        *)
            echo "Неизвестная опция: $1" >&2
            echo "Использование: $0 [-y|--yes] [-n|--dry-run] [-d|--directory]" >&2
            exit 1
            ;;
    esac
done

# Запрос маски у пользователя
if [ "$DIR_MODE" = true ]; then
    printf "Введите маску директорий (например, log*), или Enter для всех директорий: "
else
    printf "Введите маску файлов (например, log*), или Enter для всех файлов: "
fi
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

# Сбор кандидатов к удалению
tmp_list=$(mktemp)

if [ "$DIR_MODE" = true ]; then
    # Режим удаления директорий: выбираем только директории, в которых нет файлов (на любом уровне вложенности)
    if [ -z "$MASK" ]; then
        MASK_DESC="всеми директориями без файлов"
        while IFS= read -r -d '' dir; do
            if ! find "$dir" -type f -print -quit | grep -q .; then
                printf '%s\0' "$dir"
            fi
        done < <(find . -type d -print0) > "$tmp_list"
    else
        MASK_DESC="маской '$MASK' (директории без файлов)"
        while IFS= read -r -d '' dir; do
            if ! find "$dir" -type f -print -quit | grep -q .; then
                printf '%s\0' "$dir"
            fi
        done < <(find . -type d -name "$MASK" -print0) > "$tmp_list"
    fi
else
    # Режим удаления файлов нулевого размера
    if [ -z "$MASK" ]; then
        # Если маска пустая, ищем все файлы нулевого размера
        find . -type f -size 0 -print0 > "$tmp_list"
        MASK_DESC="всеми файлами нулевого размера"
    else
        # Если маска указана, используем её для фильтрации
        find . -type f -size 0 -name "$MASK" -print0 > "$tmp_list"
        MASK_DESC="маской '$MASK' (файлы нулевого размера)"
    fi
fi

# Подсчет найденных объектов
count=$(tr -cd '\0' < "$tmp_list" | wc -c | tr -d ' ')
if [ "$count" -eq 0 ]; then
    if [ "$DIR_MODE" = true ]; then
        echo "Подходящих директорий не найдено."
    else
        if [ -z "$MASK" ]; then
            echo "Файлов нулевого размера не найдено."
        else
            echo "Файлов нулевого размера с маской '$MASK' не найдено."
        fi
    fi
    rm -f "$tmp_list"
    exit 0
fi

if [ "$DIR_MODE" = true ]; then
    echo "Найдено $count директорий без файлов с $MASK_DESC в: $TARGET_DIR_ABS"
    echo "Список директорий для удаления:"
else
    echo "Найдено $count файл(ов) нулевого размера с $MASK_DESC в: $TARGET_DIR_ABS"
    echo "Список файлов для удаления:"
fi
while IFS= read -r -d '' file; do
    # Преобразуем относительный путь в абсолютный
    full_path="${TARGET_DIR_ABS}/${file#./}"
    echo "  $full_path"
done < "$tmp_list"

# Режим сухого прогона: только показываем список, не удаляем
if [ "$DRY_RUN" = true ]; then
    echo ""
    if [ "$DIR_MODE" = true ]; then
        echo "РЕЖИМ СУХОГО ПРОГОНА: директории НЕ будут удалены"
        echo "Были бы удалены: $count директорий"
    else
        echo "РЕЖИМ СУХОГО ПРОГОНА: файлы НЕ будут удалены"
        echo "Были бы удалены: $count файл(ов)"
    fi
    rm -f "$tmp_list"
    exit 0
fi

# Удаление
deleted_count=0
if [ "$YES_MODE" = true ]; then
    # Режим -y: удаляем все без подтверждений
    echo ""
    if [ "$DIR_MODE" = true ]; then
        echo "Удаление директорий (без подтверждения)..."
    else
        echo "Удаление файлов (без подтверждения)..."
    fi
    while IFS= read -r -d '' file; do
        full_path="${TARGET_DIR_ABS}/${file#./}"
        if [ "$DIR_MODE" = true ]; then
            if rm -r -- "$file" 2>/dev/null || rm -r "$file" 2>/dev/null; then
                deleted_count=$((deleted_count + 1))
                echo "Удалена: $full_path"
            else
                echo "Ошибка при удалении директории: $full_path" >&2
            fi
        else
            if rm -- "$file" 2>/dev/null || rm "$file" 2>/dev/null; then
                deleted_count=$((deleted_count + 1))
                echo "Удален: $full_path"
            else
                echo "Ошибка при удалении: $full_path" >&2
            fi
        fi
    done < "$tmp_list"
else
    # Режим по умолчанию: подтверждение для каждого файла
    echo ""
    while IFS= read -r -d '' file <&3; do
        full_path="${TARGET_DIR_ABS}/${file#./}"
        if [ "$DIR_MODE" = true ]; then
            printf "Удалить директорию '%s'? [y/N]: " "$full_path"
        else
            printf "Удалить файл '%s'? [y/N]: " "$full_path"
        fi
        read -r answer < /dev/tty
        case "$answer" in
            y|Y|yes|YES)
                if [ "$DIR_MODE" = true ]; then
                    if rm -r -- "$file" 2>/dev/null || rm -r "$file" 2>/dev/null; then
                        deleted_count=$((deleted_count + 1))
                        echo "Удалена: $full_path"
                    else
                        echo "Ошибка при удалении директории: $full_path" >&2
                    fi
                else
                    if rm -- "$file" 2>/dev/null || rm "$file" 2>/dev/null; then
                        deleted_count=$((deleted_count + 1))
                        echo "Удален: $full_path"
                    else
                        echo "Ошибка при удалении: $full_path" >&2
                    fi
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
if [ "$DIR_MODE" = true ]; then
    echo "Удалено: $deleted_count из $count директорий."
else
    echo "Удалено: $deleted_count из $count файл(ов)."
fi

