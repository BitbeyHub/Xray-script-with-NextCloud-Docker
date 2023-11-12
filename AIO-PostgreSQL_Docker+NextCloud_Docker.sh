#!/bin/bash

timedatectl set-timezone Asia/Singapore
if [[ $# -eq 0 ]]; then
    echo -e "\033[5;41;34m此脚本必须带参数运行\033[0m"
    exit 1
fi

while [[ $# -ge 2 ]]; do
    case $1 in
        '--ssl-domain')  # Since Rsync cannot work properly under some CDNs, so this is merely the mutual domain of Xray & Nextcloud (NOT the Rsync).
            shift
            if [[ -z $1 ]] || [[ $1 == -* ]]; then
                echo -e "\033[5;41;34m此脚本至少需要一个解析到本服务器的域名\n请补充域名后重新运行脚本！形如hostname.your.domain\033[0m"
                exit 1
            else
                sslDomain="$1"
                echo -e "\033[5;41;34m您输入的域名是：${sslDomain}\033[0m"
                if [ "$(echo -n "$domain" | wc -c)" -gt 46 ]; then
                    echo -e "\033[5;41;34m域名过长！请调整域名后重新运行脚本！\033[0m"
                    exit 1
                fi
            fi
            shift
        ;;

        '--fake-domain')
            shift
            if [[ -z $1 ]] || [[ $1 == -* ]]; then
                echo -e "\033[5;41;34m如选择反向代理伪装网站，则需要填写一个http网址！\033[0m"
                exit 1
            else
                fakeUrl="$1"
                echo -e "\033[5;41;34m您输入的反向代理伪装网址是：${fakeUrl}\033[0m"
            fi
            shift
        ;;

        '--NextCloud-admin-usr')
            shift
            if [[ -z $1 ]] || [[ $1 == -* ]]; then
                echo -e "\033[5;41;34m需要正确配置NextCloud管理员！\033[0m"
                exit 1
            else
                ncAdmin="$1"
                echo -e "\033[5;41;34m您输入的NextCloud管理员名称是：${ncAdmin}\033[0m"
            fi
            shift
        ;;

        '--NextCloud-admin-pwd')
            shift
            if [[ -z $1 ]] || [[ $1 == -* ]]; then
                echo -e "\033[5;41;34m需要正确配置NextCloud管理员密码！\033[0m"
                exit 1
            else
                ncAdminPwd="$1"
                echo -e "\033[5;41;34m您输入的NextCloud管理员密码是：${ncAdminPwd}\033[0m"
            fi
            shift
        ;;

        '--NextCloud-DB-pwd')
            shift
            if [[ -z $1 ]] || [[ $1 == -* ]]; then
                echo -e "\033[5;41;34m需要正确配置NextCloud数据库密码！\033[0m"
                exit 1
            else
                ncDatabasePwd="$1"
                echo -e "\033[5;41;34m您输入的NextCloud数据库密码是：${ncDatabasePwd}\033[0m"
            fi
            shift
        ;;
        
        '--Rsync-Acc-Pwd')  # separated by the colon symbol
            shift
            if [[ -z $1 ]] || [[ $1 == -* ]]; then
                echo -e "\033[5;41;34m需要正确配置Rsync的同步账号:密码！\033[0m"
                exit 1
            else
                rsyncAccPwd="$1"
                echo -e "\033[5;41;34m您输入的Rsync同步账号密码是：${rsyncAccPwd}\033[0m"
            fi
            shift
        ;;

        '--Rsync-Secret-Port')  # separated by the @ symbol
            shift
            if [[ -z $1 ]] || [[ $1 == -* ]]; then
                echo -e "\033[5;41;34m需要正确配置Rsync的服务端账密储存文件、端口！\033[0m"
                exit 1
            else
                rsyncSecPort="$1"
                echo -e "\033[5;41;34m您输入的Rsync服务端账密储存文件、端口是：${rsyncSecPort}\033[0m"
            fi
            shift
        ;;
    esac
done

if ! [[ -v sslDomain ]]; then
    echo -e "\033[5;41;34m指向域名是必需的！\033[0m"
    exit 1
elif [[ ! (-v ncAdmin && -v ncAdminPwd && -v ncDatabasePwd && -v rsyncAccPwd && -v rsyncSecPort) && -z $fakeUrl ]]; then
    echo -e "\033[5;41;34m要么装网盘要么正常简单用，也不能缺选项\033[0m"
    exit 1
elif [[ (-v ncAdmin || -v ncAdminPwd || -v ncDatabasePwd || -v rsyncAccPwd || -v rsyncSecPort) && -v fakeUrl ]]; then
    echo -e "\033[5;41;34m是二选一啦！不能两个都要！达咩！\033[0m"
    exit 1
fi


# start of the script
rm -rf /home/ncD
apt update && apt --no-install-recommends -y install wget curl ca-certificates rsync

if [[ -v fakeUrl ]]; then
    curl -fsL rebrand.ly/CamouSneak | bash -s -- $sslDomain $fakeUrl
    echo -e "\033[5;41;34m带有外部反向代理伪装网址的纯Xray服务端已部署完成！\033[0m"
else
    curl -fsL rebrand.ly/CamouSneak | bash -s -- $sslDomain

    curl -fsSL https://get.docker.com | bash

    docker network create NextCloudLAN

    docker run -d \
        --restart=unless-stopped \
        --network=NextCloudLAN \
        -e POSTGRES_DB=nextcloud \
        -e POSTGRES_USER=nextclouder \
        -e POSTGRES_PASSWORD=$ncDatabasePwd \
        -e TZ=Asia/Singapore \
        -v /home/ncD/pgData:/var/lib/postgresql/data \
        --name NextCloudDB \
        postgres:16.0-alpine3.18

    docker run -d \
        --restart=unless-stopped \
        --network=NextCloudLAN \
        -e TZ=Asia/Singapore \
        --name NextCloudCACHE \
        redis:7.2.3-alpine3.18

    docker run -d \
        --restart=unless-stopped \
        --network=NextCloudLAN \
        -p 127.0.0.1:8080:80 \
        -v /home/ncD/ncData:/var/www/html \
        -e NEXTCLOUD_ADMIN_USER=$ncAdmin \
        -e NEXTCLOUD_ADMIN_PASSWORD=$ncAdminPwd \
        -e NEXTCLOUD_TRUSTED_DOMAINS=$sslDomain \
        -e OVERWRITEPROTOCOL=https \
        -e OVERWRITECLIURL=https://$sslDomain \
        -e POSTGRES_DB=nextcloud \
        -e POSTGRES_USER=nextclouder \
        -e POSTGRES_PASSWORD=$ncDatabasePwd \
        -e POSTGRES_HOST=NextCloudDB \
        -e REDIS_HOST=NextCloudCACHE \
        -e TZ=Asia/Singapore \
        --name NextCloudIns \
        nextcloud:27.1.3-apache


    # Thankfully borrowed from https://stackoverflow.com/a/37410430
    (crontab -l; echo "*/5  *  *  *  * docker exec -d -u www-data NextCloudIns php --define apc.enable_cli=1 -f /var/www/html/cron.php") | crontab -

    echo -e "\033[5;41;34m高可迁移的NextCloud云盘实例已部署完成！\033[0m"



    # Create the config file for Rsyncd
    # Separate the sub-variables accordingly
    rsyncAcc=`cut -d':' -f1 <<< "$rsyncAccPwd"`
    rsyncSecrets=`cut -d'@' -f1 <<< "$rsyncSecPort"`
    rsyncPort=`cut -d'@' -f2 <<< "$rsyncSecPort"`

    # Create the account-password secret file for Rsync
    echo "$rsyncAccPwd" > $rsyncSecrets
    chmod 600 $rsyncSecrets

cat > /etc/rsyncd.conf <<EOF
uid = root
gid = root
port = ${rsyncPort}

[Mirroring]
comment = Disaster Recovery of My Cloud
auth users = ${rsyncAcc}
secrets file = ${rsyncSecrets}
use chroot = true
path = /home/ncD
read only = true
list = false
log file = /var/log/rsync.log

EOF
    systemctl start rsync
    echo -e "\033[5;41;34m！开箱即用的rsync daemon已部署完成！\033[0m"

fi
