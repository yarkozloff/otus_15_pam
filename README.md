# PAM
## Цель
Рассмотреть механизмы авторизации и аутентификации;
Узнать какие бывают права у пользовталей;
Управлять правами с помощью sudo, umask. sgid, suid и более сложными инструментами как PAM и ACL, PolicyKit.
## Описание:

- Запретить всем пользователям, кроме группы admin логин в выходные (суббота и воскресенье), без учета праздников
- ** Дать конкретному пользователю права работать с докером и возможность рестартить докер сервис
> В методичке описывается решение как пользователь ”day” - имеет удаленный доступ каждый день с 8 до 20; “night” - с 20 до 8; “friday” - в любое время, если сегодня пятница. 
> Это противоречит постановке первой задачи в описании, поэтому ниже будет описано решение с запретом всем пользователям кроме группы admin осуществлять вход в выходные дни

## Запретить всем пользователям кроме группы admin осуществлять вход в выходные дни:
Машина для тестирования CentOS Linux 7 (Core)
### Подготовка пользователей
Командой useradd создадим пользователей user1, user3.
Назначим всем для удоства одинаковый пароль командой passwd.
Создадим группу admin командой groupadd
Командой usermod -aG добавим user1 и root в группу admin
```
[root@yarkozloff ~]# cat /etc/group | grep admin
admin:x:1006:user1,root
```
Проверим вход под ними (я использую BitwiseSSH как ssh клиент):
```
[user1@yarkozloff ~]$ whoami
user1
[user1@yarkozloff ~]$ pwd
/home/user1
```
 ### Модуль pam_time
 Модуль pam_time позволяет достаточно гибко настроить доступ пользователя с учетом времени. Настройки данного модуля хранятся в файле /etc/security/time.conf.
 Добавим туда запись следующего формата:
sshd;*;!admin;Wk0000-2400
- sshd; - сервис, к которому применяется правило
- *; имя терминала, к которому применяется правило, тут можно было указать tty
- !admin; - группа пользователей к которым не применяется правило, то есть все кроме admin
- Wk0000-2400; - Время, когда правило носит разрешающий характер (Рабочие дни всё время) 

Теперь настроим PAM, так как по-умолчанию данный модуль не
подключен.
Для этого приведем файл /etc/pam.d/sshd к виду:
```
account    required     pam_nologin.so
account    required     pam_time.so
```
Всё настроено как и планировалось, но при проверке обнружились проблемы, оказалось, в 3 параметре /etc/security/time.conf нельзя задать локальную группу, только имя пользователя или сетевой группы (оказывается я не один такой https://serverfault.com/questions/1037366/linux-pam-time-with-groups). Можно перечислить всех пользователей через или, но это конечно не вариант. Поэтому будем решать по-другому

### Модуль pam_exec
Еще один способ реализовать задачу это выполнить при подключении пользователя скрипт, в котором мы сами обработаем необходимую информацию.
Удалим из /etc/pam.d/sshd изменения из предыдущего этапа и
приведем его к следующему виду:
```
account    required     pam_nologin.so
account    required     pam_exec.so /usr/local/bin/test_login.sh
```
Мы добавили модуль pam_exec и, в качестве параметра, указали скрипт, который осуществит необходимые проверки. Создадим сам скрипт:
```
#!/bin/bash
username=$PAM_USER
if [ $(date +%a) = "Sat" ]  || [ $(date +%a) = "Sun" ]; then
  if getent group admin | grep -q "\b${username}\b"; then
        exit 0
      else
        exit 1
    fi
  else
    exit 0
fi
```
При запуске данного скрипта PAM-модулем будет передана переменная окружения PAM_USER, содержащая имя пользователя. Затем вычисляется день недели, если это суббота или воскресенье то проверяем вхождение пользователя в группу admin, при выполнении обоих условий возвращается 0, иначе 1.
Проверяем, ошибка при логине:
```
/usr/local/bin/test_login.sh failed: exit code 13
```
Вообщем в скрипте накосячил и прав не хватило для его выполнения, лог /var/log/secure: 
Jun 22 00:22:11 yarkozloff sshd[20928]: pam_exec(sshd:account): execve(/usr/local/bin/1_login.sh,...) failed: Permission denied
Jun 22 00:22:11 yarkozloff sshd[20924]: pam_exec(sshd:account): /usr/local/bin/1_login.sh failed: exit code 13

Т.к. уже не выходные, меняем в скрипте условие на день недели Wed

Проверяем под пользователем user1:

![image](https://user-images.githubusercontent.com/69105791/174907920-19ef2fe5-07a2-4fb7-913c-00a54305c48b.png)


Проверяем под пользователем user3:

![image](https://user-images.githubusercontent.com/69105791/174907743-6d302b3a-a849-4f4f-90c9-1144f197b73a.png)

Вносим параметр pam_exec в конфиг vim /etc/pam.d/system-auth.
Результат, если зайти под пользователем user1 и аутентифициремся под user3:
```
[user1@yarkozloff ~]$ su - user3
Password:
/usr/local/bin/test_login.sh failed: exit code 1
su: System error
```
Работает как надо, user3 не входит в группу admin

## Дать конкретному пользователю права работать с докером и возможность рестартить докер сервис

Заводим пользователя, проверяем что он обычный:
```
[docker_user@yarkozloff ~]$ pwd
/home/docker_user
[docker_user@yarkozloff ~]$ id
uid=1006(docker_user) gid=1008(docker_user) groups=1008(docker_user)
```
Для возможнности работать с докером пользователя достаточно добавить в группу docker:
```
usermod -aG docker docker_user
```
Перелогинимся под ним. Попробуем запустить контейнер hello-world от этого пользователя:
```
[docker_user@yarkozloff ~]$ docker run hello-world
Unable to find image 'hello-world:latest' locally
Trying to pull repository docker.io/library/hello-world ...
latest: Pulling from docker.io/library/hello-world
2db29710123e: Pull complete
Digest: sha256:13e367d31ae85359f42d637adf6da428f76d75dc9afeb3c21faea0d976f5c651
Status: Downloaded newer image for docker.io/hello-world:latest

Hello from Docker!
This message shows that your installation appears to be working correctly.
```
Пробуем рестартнуть сервис:
```
[docker_user@yarkozloff ~]$ systemctl restart docker
==== AUTHENTICATING FOR org.freedesktop.systemd1.manage-units ===
Authentication is required to manage system services or units.
Authenticating as: root
```
Создаем файл /etc/polkit-1/localauthority/50-local.d/org.freedesktop.systemd1.pkla с содержимым:
```
[Allow user docker_user to run systemctl commands]
Identity=unix-user:docker_user
Action=org.freedesktop.systemd1.manage-units
ResultInactive=no
ResultActive=no
ResultAny=yes
```
Проверяем:
```
[docker_user@yarkozloff ~]$ systemctl restart httpd
[docker_user@yarkozloff ~]$ systemctl restart docker
[docker_user@yarkozloff ~]$
```
Как видим, данное решение позволяет пользователю рестартить не только сервис docker.
