#!/bin/bash

# Скрипт для настройки SSH-подписей коммитов в Git на macOS
# Запрашивает: Git имя, Git email, название сервиса (default: github)
# Генерирует ключ, настраивает Git, добавляет в ssh-agent, создает ~/.ssh/config
# Автоматически обновляет allowed_signers.pub
# Хост: для github - github.com, gitlab - gitlab.com, иначе запрашивает кастомный хост
# Юзер: git по умолчанию
# Порт: запрашивает, по умолчанию пустой (стандартный 22)

echo "Добро пожаловать в скрипт настройки SSH-подписей для Git!"

# Запрос Git имени
read -p "Введите Git имя (user.name, например 'GitUser'): " git_name
if [ -z "$git_name" ]; then
    echo "Ошибка: Имя не может быть пустым."
    exit 1
fi

# Запрос Git email
read -p "Введите Git email (user.email, например 'user@mail.ru'): " git_email
if [ -z "$git_email" ]; then
    echo "Ошибка: Email не может быть пустым."
    exit 1
fi

# Запрос названия сервиса
read -p "Введите название сервиса (default: github): " service
service=${service:-github}

# Запрос суффикса для имени ключа
read -p "Введите суффикс для имени ключа (default: sign, например sign или auth): " key_suffix
key_suffix=${key_suffix:-sign}

# Определение хоста на основе сервиса
if [ "$service" = "github" ]; then
    host="github.com"
elif [ "$service" = "gitlab" ]; then
    host="gitlab.com"
else
    read -p "Введите кастомный хост (например git.softlex.pro): " host
    if [ -z "$host" ]; then
        echo "Ошибка: Хост не может быть пустым."
        exit 1
    fi
fi

# Запрос порта (по умолчанию пустой)
read -p "Введите порт (default: пустой для 22, например 2222): " port

# Генерация SSH-ключа
key_name="id_ed25519_${key_suffix}_$service"
key_path="$HOME/.ssh/$key_name"
ssh-keygen -t ed25519 -C "$git_email" -f "$key_path"
if [ $? -ne 0 ]; then
    echo "Ошибка при генерации ключа."
    exit 1
fi

# Показ публичного ключа для добавления в сервис
pub_key="$key_path.pub"
echo "Скопируйте следующий публичный ключ и добавьте в настройки сервиса ($service):"
cat "$pub_key"
echo ""
echo "Для GitHub: Settings → SSH and GPG Keys → New SSH Key"
echo "Для GitLab: Settings → SSH Keys"
echo "Нажмите Enter после добавления..."
read -r

# Настройка allowed_signers.pub
allowed_dir="$HOME/.ssh/git-allowed-signers"
allowed_file="$allowed_dir/allowed_signers.pub"
mkdir -p "$allowed_dir"

# Добавляем ключ в файл в формате "cert-authority ssh-ed25519 KEY email" (cert-authority + содержимое pub_key)
echo "cert-authority $(cat "$pub_key")" >> "$allowed_file"

echo "Ключ добавлен в $allowed_file"

# Добавление ключа в ssh-agent с Keychain
eval "$(ssh-agent -s)"
ssh-add --apple-use-keychain "$key_path"

# Проверка добавления
ssh-add -l

# Настройка Git конфигурации
git config --global user.name "$git_name"
git config --global user.email "$git_email"
git config --global gpg.format ssh
git config --global user.signingkey "$pub_key"
git config --global gpg.ssh.allowedSignersFile "$allowed_file"
git config --global commit.gpgsign true  # Автоматическая подпись

# Создание/обновление ~/.ssh/config
ssh_config="$HOME/.ssh/config"
touch "$ssh_config"

# Добавляем или обновляем секцию Host
if grep -q "Host $host" "$ssh_config"; then
    echo "Обновляем существующую секцию Host $host в $ssh_config"
    # Удаляем старую секцию (простой способ, можно улучшить)
    sed -i '' "/Host $host/,/^\$/d" "$ssh_config"
else
    echo "Добавляем новую секцию Host $host в $ssh_config"
fi

# Добавляем новую секцию
echo "" >> "$ssh_config"
echo "Host $host" >> "$ssh_config"
echo "  User git" >> "$ssh_config"
if [ -n "$port" ]; then
    echo "  Port $port" >> "$ssh_config"
fi
echo "  IdentityFile $key_path" >> "$ssh_config"
echo "  AddKeysToAgent yes"
echo "  UseKeychain yes"

# Проверка подключения
echo "Проверяем соединение: ssh -T git@$host"
if [ -n "$port" ]; then
    ssh -T git@$host -p "$port"
else
    ssh -T git@$host
fi

echo "Настройка завершена!"
echo "Теперь настройте remote в репозитории: git remote set-url origin git@$host:username/repo.git"
echo "Тестируйте коммит: git commit --allow-empty -m 'Test commit'"