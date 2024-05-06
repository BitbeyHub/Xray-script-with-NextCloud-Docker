#!/bin/bash

timedatectl set-timezone Asia/Singapore
if [[ $# -eq 0 ]]; then
    echo -e "\033[5;41;34m此脚本必须带参数运行\033[0m"
    exit 1
fi

while [[ $# -ge 2 ]]; do
    case $1 in
        '--ssl-domain')  # Since SSH cannot be forwarded on default port under some CDNs, so this is merely the mutual domain of Xray & Nextcloud (NOT for the Rsync over SSH).
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
        
        '--RsyncSSH-Usr-Pwd')  # separated by the colon symbol
            shift
            if [[ -z $1 ]] || [[ $1 == -* ]]; then
                echo -e "\033[5;41;34m需要正确配置用于Rsync over SSH的系统`账号:密码`！\033[0m"
                exit 1
            else
                rsyncSshUsrPwd="$1"
                echo -e "\033[5;41;34m您输入的用于Rsync over SSH的系统账号密码是：${rsyncSshUsrPwd}\033[0m"
            fi
            shift
        ;;
    esac
done

if ! [[ -v sslDomain ]]; then
    echo -e "\033[5;41;34m指向域名是必需的！\033[0m"
    exit 1
elif [[ ! (-v ncAdmin && -v ncAdminPwd && -v ncDatabasePwd && -v rsyncSshUsrPwd) && -z $fakeUrl ]]; then
    echo -e "\033[5;41;34m要么装网盘要么正常简单用，也不能缺选项\033[0m"
    exit 1
elif [[ (-v ncAdmin || -v ncAdminPwd || -v ncDatabasePwd || -v rsyncSshUsrPwd) && -v fakeUrl ]]; then
    echo -e "\033[5;41;34m是二选一啦！不能两个都要！达咩！\033[0m"
    exit 1
fi


# start of the script
rm -rf /home/ncD
apt update && apt --no-install-recommends -y install wget curl ca-certificates vnstat unzip  # openresolv wireguard wireguard-tools

# You need to modify the /etc/vnstat.conf according to https://doc.ssr.rs/vnstat
# Then run "systemctl restart vnstat"

mkdir -p /opt/ServerStatus && cd /opt/ServerStatus
wget -q https://github.com/zdz/Serverstatus-Rust/releases/latest/download/client-x86_64-unknown-linux-musl.zip
unzip -o client-x86_64-unknown-linux-musl.zip 'stat_client' && rm client-x86_64-unknown-linux-musl.zip
# Upload your PROPER stat_client systemd file to /etc/systemd/system/stat_client.service
# 
# Execute "systemctl daemon-reload && systemctl restart stat_client" afterwards
cd -

if [[ -v fakeUrl ]]; then
    curl -fsL rebrand.ly/CamouSneak | bash -s -- $sslDomain $fakeUrl
    echo -e "\033[5;41;34m带有外部反向代理伪装网址的纯Xray服务端已部署完成！\033[0m"
else
    apt install -y acl rsync
    curl -fsL rebrand.ly/CamouSneak | bash -s -- $sslDomain

    curl -fsSL https://get.docker.com | bash

    ncCpuLimit=`nproc --all | awk '{print $1*0.9}'`
    docker network create NextCloudLAN

    # https://hub.docker.com/_/postgres/tags
    docker run -d \
        --restart=unless-stopped \
        --network=NextCloudLAN \
        -e POSTGRES_DB=nextcloud \
        -e POSTGRES_USER=nextclouder \
        -e POSTGRES_PASSWORD=$ncDatabasePwd \
        -e TZ=Asia/Singapore \
        -v /home/ncD/pgData:/var/lib/postgresql/data \
        --name NextCloudDB \
        postgres:15.5-alpine3.19

    # https://hub.docker.com/_/redis/tags
    docker run -d \
        --restart=unless-stopped \
        --network=NextCloudLAN \
        -e TZ=Asia/Singapore \
        --name NextCloudCACHE \
        redis:7.2.3-alpine3.19

    # https://hub.docker.com/_/nextcloud/tags
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
        --cpus="$ncCpuLimit" \
        nextcloud:28.0.0-apache


    # Thankfully borrowed from https://stackoverflow.com/a/37410430
    (crontab -l; echo "*/5  *  *  *  * docker exec -d -u www-data NextCloudIns php --define apc.enable_cli=1 -f /var/www/html/cron.php") | crontab -

    echo -e "\033[5;41;34m高可迁移的NextCloud云盘实例已部署完成！\033[0m"



    # Enable the specific user account for rsync over SSH
    rsyncSshUsr=`cut -d: -f1 <<< $rsyncSshUsrPwd`
    rsyncSshUsrPwd=`cut -d: -f2 <<< $rsyncSshUsrPwd`

    usermod -p `echo $rsyncSshUsrPwd | openssl passwd -1 -stdin` -s /bin/bash $rsyncSshUsr
    rsyncSshGrp=`getent passwd $rsyncSshUsr | cut -d: -f5`
    rsyncSshUsrHome=`getent passwd $rsyncSshUsr | cut -d: -f6`
    chown -hR $rsyncSshUsr:$rsyncSshGrp $rsyncSshUsrHome  # in some circumstances an non-root user doesn't own their homedir which introduces considerable latency on SSH login every time

    # Assign proper ACL permissions to the specific user account for the NextCloud deployment directory
    setfacl -LR -m u:$rsyncSshUsr:rx /home/ncD
    setfacl -dLR -m u:$rsyncSshUsr:rx /home/ncD

    # Check periodically for directory permissions recursively to maintain consistency
    (crontab -l; echo "* 2 * * * setfacl -LR -m u:$rsyncSshUsr:rx /home/ncD") | crontab -

    echo -e "\033[5;41;34m！为rsync over SSH准备的系统用户已启用完成！\033[0m"
fi
