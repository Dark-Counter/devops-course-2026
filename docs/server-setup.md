# Конфигурация виртуальной машины devops-vm

Документ — исходные данные для восстановления машины после отката на снимок `01-clean-install`. Пароли учётных записей здесь не хранятся: они задаются при установке и при `adduser` и нужны только для локального `sudo`.

## 1. Параметры машины

| Параметр | Значение |
| --- | --- |
| Имя | devops-vm |
| Средство виртуализации | VirtualBox 7.2.22 |
| Гостевая система | Ubuntu Server 24.04.5 LTS, редакция Server, вариант minimized не используется |
| Образ | arm64: хост — Apple Silicon, VirtualBox не эмулирует amd64 |
| Память | 2048 МБ |
| Процессор | 2 ядра |
| Диск | 25 ГБ, динамический VDI |
| Имя узла | devops-vm |
| Учётная запись установщика | student, в группе sudo |
| OpenSSH server | установлен при инсталляции |
| Язык установщика | English |

Система поставлена автоматической установкой Ubuntu через шаблон VirtualBox: пользователь `student`, короткое имя узла `devops-vm`, пакет `openssh-server`. Откат на снимок `01-clean-install` установку не повторяет. Указатель — USB tablet, контроллер xHCI: с мышью PS/2 консоль на Apple Silicon не принимает клавиатуру.

## 2. Сетевые интерфейсы

Оба адаптера создаются до первого запуска.

| Адаптер | Тип | Адрес | Назначение |
| --- | --- | --- | --- |
| 1 | NAT, интерфейс `enp0s8` | 10.0.2.15/24 | выход в интернет, репозитории пакетов; вход с хоста только пробросом портов |
| 2 | Host-only, сеть `devops-hostonly`, интерфейс `enp0s9` | 192.168.56.2/24 | прямой доступ с хоста, в том числе по имени devops.local |

Сеть `devops-hostonly`: маска 255.255.255.0, DHCP от 192.168.56.1 до 192.168.56.200. На macOS в VirtualBox 7 это сеть типа host-only network, не старый адаптер `vboxnet`:

```bash
VBoxManage hostonlynet add --name=devops-hostonly --netmask=255.255.255.0 --lower-ip=192.168.56.1 --upper-ip=192.168.56.200 --enable
VBoxManage modifyvm devops-vm --nic2 hostonlynet --host-only-net2 devops-hostonly
```

Хост в этом сегменте получает 192.168.56.1. Гость получил 192.168.56.2, не пример 192.168.56.101 из методички.

Проверка: `ip -brief address`.

## 3. Правило проброса портов

Адаптер 1, NAT, правило `ssh`, протокол TCP.

| Этап | Адрес и порт хоста | Порт гостя |
| --- | --- | --- |
| До смены порта SSH | 127.0.0.1:2222 | 22 |
| После директивы `Port 2222` | 127.0.0.1:2222 | 2222 |

Поле адреса гостя не заполняется. Правило меняется без выключения машины:

```bash
VBoxManage controlvm devops-vm natpf1 delete ssh
VBoxManage controlvm devops-vm natpf1 "ssh,tcp,127.0.0.1,2222,,2222"
```

`VBoxManage` на macOS: `/Applications/VirtualBox.app/Contents/MacOS/VBoxManage`.

Менять проброс нужно до проверки нового входа. Пока гость слушает 2222, а проброс всё ещё ведёт на 22, новое соединение с хоста получит `Connection refused`. Уже открытая сессия при этом жива.

## 4. Учётные записи

| Имя | Группы | Аутентификация SSH |
| --- | --- | --- |
| student | sudo | пароль, учётка установщика; после hardening в `AllowUsers` её нет, вход по SSH закрыт |
| devops | sudo | только ключ `~/.ssh/devops_vm` (ed25519, комментарий `devops-vm-key`) |

Создание:

```bash
sudo adduser devops
sudo usermod -aG sudo devops
groups devops
```

Ключ выпускается на хосте, не из ключевой пары для Git. Парольная фраза ключа пустая, иначе вход спрашивает её и не считается беспарольным. Открытый ключ кладётся в `/home/devops/.ssh/authorized_keys`. Права: каталог `700`, файл `600`.

Фрагмент `~/.ssh/config` на хосте (дописывается в конец файла, существующие записи не заменяются):

```
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes

Host devops.local
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
```

Вторая запись нужна потому, что после переноса SSH на порт 2222 команда `ssh devops.local` без порта шла бы на закрытый порт 22. `IdentitiesOnly yes` не даёт клиенту перебрать чужие ключи и упереться в `MaxAuthTries 3`.

На хосте в `/etc/hosts` (на macOS это файл хоста, не гостя):

```
192.168.56.2 devops.local
```

## 5. Служба SSH

Порт 2222. Основной `/etc/ssh/sshd_config` не редактируется. Действующий файл: `/etc/ssh/sshd_config.d/99-hardening.conf`. Рядом лежит копия `/etc/ssh/sshd_config.backup`.

```
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers devops
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
```

На Ubuntu 24.04 более ранний файл в том же каталоге (часто `50-cloud-init.conf`) может содержать `PasswordAuthentication yes`. Файлы читаются по алфавиту, и первое значение директивы побеждает, поэтому префикс `99-` его не перекрывает. Проверка и при необходимости комментарий строки:

```bash
grep -R "PasswordAuthentication" /etc/ssh/sshd_config.d/ /etc/ssh/sshd_config
sudo sshd -t && echo "Конфигурация корректна"
sudo sshd -T | grep -Ei '^(port|permitrootlogin|passwordauthentication|maxauthtries|allowusers) '
```

Достоверный источник — вывод `sshd -T`, не текст файлов.

Ubuntu 24.04 активирует SSH сокетом, и сокет удерживает порт 22 поверх директивы `Port`:

```bash
sudo systemctl disable --now ssh.socket
sudo systemctl enable --now ssh.service
sudo systemctl restart ssh
sudo ss -tlnp | grep sshd
```

Ожидается `0.0.0.0:2222`. Исходную сессию не закрывать, пока новое соединение `ssh devops` не установлено.

## 6. Правила межсетевого экрана

Политика: входящие запрещены, исходящие разрешены. Разрешающее правило для порта управления создаётся до `ufw enable`. Имя `ssh` не используется: `/etc/services` сопоставляет его порту 22.

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 2222/tcp comment 'SSH'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw enable
sudo ufw delete allow 2222/tcp
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw logging medium
sudo ufw status verbose
```

В выводе у порта 2222/tcp признак `LIMIT` (не больше шести новых соединений с одного адреса за 30 секунд). Порты 80 и 443 оставлены для практической работы № 6.

## 7. Снимки состояния

| Имя | Что уже сделано | Чего ещё нет |
| --- | --- | --- |
| 01-clean-install, 30.10.2026 16:04 | система обновлена, OpenSSH на порту 22, NAT 10.0.2.15, host-only 192.168.56.2, машина выключена | учётки devops, ключа, hardening, файрвола |
| 02-keys-configured, 30.10.2026 16:20 | учётка devops, вход по ключу, `~/.ssh/config` на хосте | смены порта, запрета пароля и root |
| 03-ssh-hardened, 30.10.2026 16:26 | `99-hardening.conf`, порт 2222, проброс на гостевой 2222 | файрвола и записи devops.local |

Снимки 02 и 03 снимаются с работающей машины: выключение оборвало бы контрольную сессию задания 2. После заданий 3 и 4 откатываться на снимок 03 нельзя — в нём ещё нет межсетевого экрана и полного имени узла. Текущее состояние машины и есть итог работы.

Полное имя узла после задания 4: `devops-vm.devops.local` (`hostname -f`). Строка в `/etc/hosts` гостя: `127.0.1.1 devops-vm.devops.local devops-vm`.

Повторная проверка: `bash scripts/audit.sh` из этого репозитория. Ненулевой код означает, что эффективная конфигурация разошлась с описанной здесь.
