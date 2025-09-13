#!/bin/bash

echo "Добро пожаловать в скрипт настройки SSH-ключей для Git (auth + signing)!"

# --- Git данные ---
read -p "Введите Git имя (user.name, например 'GitUser'): " git_name
[ -z "$git_name" ] && { echo "Ошибка: Имя не может быть пустым."; exit 1; }

read -p "Введите Git email (user.email, например 'user@mail.ru'): " git_email
[ -z "$git_email" ] && { echo "Ошибка: Email не может быть пустым."; exit 1; }

# --- Сервис/хост ---
read -p "Введите название сервиса (default: github): " service
service=${service:-github}

if [ "$service" = "github" ]; then
    host="github.com"
elif [ "$service" = "gitlab" ]; then
    host="gitlab.com"
else
    read -p "Введите кастомный хост (например git.softlex.pro): " host
    [ -z "$host" ] && { echo "Ошибка: Хост не может быть пустым."; exit 1; }
fi

# --- Порт ---
read -p "Введите порт (default: пустой для 22, например 2222): " port

# --- Пути к ключам ---
auth_key="$HOME/.ssh/id_ed25519_auth_$service"
sign_key="$HOME/.ssh/id_ed25519_sign_$service"

# --- Генерация ключей ---
ssh-keygen -t ed25519 -C "$git_email" -f "$auth_key"
ssh-keygen -t ed25519 -C "$git_email" -f "$sign_key"

[ $? -ne 0 ] && { echo "Ошибка при генерации ключей."; exit 1; }

# --- Вывод публичных ключей ---
echo "Добавьте эти публичные ключи в сервис ($service):"
echo "--- AUTH ключ (для подключения): ---"
cat "${auth_key}.pub"
echo "--- SIGNING ключ (для подписей): ---"
cat "${sign_key}.pub"
read -p "Нажмите Enter после добавления ключей..."

# --- allowed_signers.pub ---
allowed_dir="$HOME/.ssh/git-allowed-signers"
allowed_file="$allowed_dir/allowed_signers.pub"
mkdir -p "$allowed_dir"

# обновляем/заменяем запись для email
grep -v "$git_email" "$allowed_file" > "${allowed_file}.tmp" 2>/dev/null || true
mv "${allowed_file}.tmp" "$allowed_file"
echo "cert-authority $(cat "${sign_key}.pub")" >> "$allowed_file"

echo "Signing ключ добавлен в $allowed_file"

# --- ssh-agent ---
eval "$(ssh-agent -s)"
ssh-add --apple-use-keychain "$auth_key"
ssh-add --apple-use-keychain "$sign_key"
ssh-add -l

# --- Git config ---
read -p "Хотите записать настройки в git config --global? (y/n): " set_git
if [ "$set_git" = "y" ]; then
    git config --global user.name "$git_name"
    git config --global user.email "$git_email"
    git config --global gpg.format ssh
    git config --global user.signingkey "${sign_key}.pub"
    git config --global gpg.ssh.allowedSignersFile "$allowed_file"
    git config --global commit.gpgsign true
    echo "Git config обновлён."
else
    echo "Git config пропущен."
fi

# --- SSH config ---
ssh_config="$HOME/.ssh/config"
touch "$ssh_config"

if grep -q "Host $host" "$ssh_config"; then
    echo "⚠️ Найдена секция Host $host в $ssh_config"
    read -p "Перезаписать её? (y/n): " overwrite
    if [ "$overwrite" = "y" ]; then
        sed -i '' "/Host $host/,/^\$/d" "$ssh_config"
    else
        echo "Секция сохранена как есть."
        exit 0
    fi
fi

# Добавляем секцию только с signing ключом
{
    echo ""
    echo "Host $host"
    echo "  User git"
    [ -n "$port" ] && echo "  Port $port"
    echo "  IdentityFile $sign_key"
    echo "  AddKeysToAgent yes"
    echo "  UseKeychain yes"
} >> "$ssh_config"

echo "Настройка завершена!"
