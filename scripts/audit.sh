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
echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
