#!/usr/bin/env bash
set -uo pipefail
PASS=0; FAIL=0
check() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "  [OK]   $desc"
    ((PASS++))
  else
    echo "  [FAIL] $desc (ожидалось: '$expected', получено: '$actual')"
    ((FAIL++))
  fi
}
echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"
echo "[1] Служба SSH"
check "Вход от имени root запрещён" "no" "$(sudo sshd -T | awk '/^permitrootlogin/{print $2}')"
check "Парольная аутентификация отключена" "no" "$(sudo sshd -T | awk '/^passwordauthentication/{print $2}')"
# Порт должен быть любым, кроме 22: равенство с эталоном здесь не подходит.
port="$(sudo sshd -T | awk '/^port /{print $2}')"
if [[ -n "$port" && "$port" != "22" ]]; then
  echo "  [OK]   Порт SSH отличен от 22 ($port)"
  ((PASS++))
else
  echo "  [FAIL] Порт SSH отличен от 22 (ожидалось: значение, отличное от 22, получено: '$port')"
  ((FAIL++))
fi
check "Лимит попыток аутентификации равен 3" "3" "$(sudo sshd -T | awk '/^maxauthtries/{print $2}')"
echo "[2] Межсетевой экран"
check "Межсетевой экран активен" "active" "$(sudo ufw status | awk '/^Status:/{print $2}')"
# Строка вида «Default: deny (incoming), allow (outgoing), ...».
default_in="$(sudo ufw status verbose | awk -F'[, ]+' '/^Default:/{print $2}')"
check "Политика входящего трафика — deny" "deny" "$default_in"
echo "[3] Учётные записи"
awk -F: '$3>=1000 && $3<65534 {printf "  %s (uid=%s)\n",$1,$3}' /etc/passwd
echo "[4] Веб-сервер"
check "Служба nginx активна" "active" "$(systemctl is-active nginx)"
if sudo nginx -t >/dev/null 2>&1; then
  nginx_ok=0
else
  nginx_ok=1
fi
check "Конфигурация nginx корректна" "0" "$nginx_ok"
# 30 суток. Для проверки отказа порог можно поднять переменной CERT_MIN_SECONDS.
cert_seconds="${CERT_MIN_SECONDS:-2592000}"
if sudo openssl x509 -checkend "$cert_seconds" -noout -in /etc/ssl/certs/devops.crt >/dev/null 2>&1; then
  cert_ok=yes
else
  cert_ok=no
fi
check "Сертификат действует ещё минимум заданный срок" "yes" "$cert_ok"
key_mode="$(sudo stat -c '%a' /etc/ssl/private/devops.key)"
writable="$(find /var/www/devops-site -perm -o+w -print)"
if [[ "$key_mode" == "600" && -z "$writable" ]]; then
  echo "  [OK]   Ключ закрыт (600), файлов с записью для всех нет"
  ((PASS++))
else
  echo "  [FAIL] Ключ закрыт (600), файлов с записью для всех нет (ключ: '$key_mode', запись для всех: '${writable:-нет}')"
  ((FAIL++))
fi
echo "[5] Контейнеризация"
check "Служба docker активна" "active" "$(systemctl is-active docker)"
db_health="$(docker inspect -f '{{.State.Health.Status}}' app-db-1 2>/dev/null || echo missing)"
check "Контейнер базы в состоянии healthy" "healthy" "$db_health"
# 127.0.0.1 допустим. Любой другой адрес на портах 5000 и 5432 — нет.
bad_bind="$(ss -tlnH | awk '
  {
    local=$4
    port=local
    sub(/^.*:/, "", port)
    host=local
    sub(/:[^:]*$/, "", host)
    if ((port=="5000" || port=="5432") && host!="127.0.0.1") print local
  }')"
if [[ -z "$bad_bind" ]]; then
  echo "  [OK]   Порты 5000 и 5432 не опубликованы наружу"
  ((PASS++))
else
  echo "  [FAIL] Порты 5000 и 5432 не опубликованы наружу (получено: '$bad_bind')"
  ((FAIL++))
fi
check "Права файла .env равны 600" "600" "$(stat -c '%a' /home/devops/app/.env)"
echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
