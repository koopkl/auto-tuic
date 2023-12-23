#!/bin/bash

CONFIG_FILE=/etc/sing-box/config.json 

function install_and_run () {
    echo "安装环境依赖"
    echo "开始安装sing-box核心"
    bash <(curl -fsSL https://sing-box.app/deb-install.sh)
    echo "sing-box安装完成"
    echo "开始安装jq"
    apt update && apt install -y jq gawk uuid-runtime vim
    echo "jq安装成功"
    systemctl enable sing-box
    read -p "请输入您用来申请证书的域名: " domain
    read -p "请输入tuic监听端口: " port
    read -p "您用于申请acme的邮箱, 尽量填写真实邮件地址: " email
    uuid=$(uuidgen)

    
    echo "正在下载tuic配置文件"
    curl --fail -O https://raw.githubusercontent.com/koopkl/auto-tuic/main/tuic-config.json
    echo "正在生成tuic 配置文件...."
    jq \
      ".inbounds[0].listen_port=${port} | \
      .inbounds[0].tls.server_name=\"${domain}\" | \
      .inbounds[0].tls.acme.domain=\"${domain}\" | \
      .inbounds[0].tls.acme.email=\"${email}\" | \
      .inbounds[0].users[0].uuid=\"${uuid}\" | \
      .inbounds[0].users[0].password=\"${uuid}\"" tuic-config.json > tuic-config-updated.json
    echo "sing-box配置如下："
    cat tuic-config-updated.json
    mv tuic-config-updated.json /etc/sing-box/config.json
    rm -rf tuic-config.json
    echo "停止sing-box"
    systemctl stop sing-box
    echo "运行sing-box"
    systemctl start sing-box
}

function uninstall() {
    echo "开始卸载sing-box"
    rm -rf /usr/bin/sing-box && rm -rf /etc/sing-box && rm -rf /etc/systemd/system/sing-box.service
    echo "卸载完成"
  }



function start_sing_box() {
  systemctl start sing-box
}

function stop_sing_box() {
  systemctl stop sing-box
}

function restart_sing_box() {
  systemctl restart sing-box
}

function log_sing_box() {
  journalctl -u sing-box --output cat -e
}

function edit_config() {
  vim /etc/sing-box/config.json 
}
function gen_shadowrocket_config() {
  port=`jq ".inbounds[0].listen_port" ${CONFIG_FILE}`
  uuid=`jq ".inbounds[0].users[0].uuid" ${CONFIG_FILE}`
  password=`jq ".inbounds[0].users[0].password" ${CONFIG_FILE}`
  host=`jq ".inbounds[0].tls.acme.domain" ${CONFIG_FILE}`
  echo "{
    \"host\" : ${host},
    \"alpn\" : \"h3\",
    \"uuid\": "${uuid}",
    \"type\" : \"TUIC\",
    \"udp\" : 2,
    \"port\" : "${port}",
    \"obfs\" : \"none\",
    \"proto\" : \"bbr\",
    \"password\": "${password}",
    \"user\": "${uuid}",
  }"
  echo "gen_shadowrocket_config"
}

function gen_tuic_client_config() {
  port=`jq -r ".inbounds[0].listen_port" ${CONFIG_FILE}`
  uuid=`jq ".inbounds[0].users[0].uuid" ${CONFIG_FILE}`
  password=`jq ".inbounds[0].users[0].password" ${CONFIG_FILE}`
  host=`jq -r ".inbounds[0].tls.acme.domain" ${CONFIG_FILE}`
  ip=$(ip addr | awk '/^[0-9]+: / {}; /inet.*global/ {print gensub(/(.*)\/(.*)/, "\\1", "g", $2)}' | head -n 1)
  echo "{
    \"relay\": {
      \"server\": \"${host}:${port}\",
      \"uuid\": "${uuid}",
      \"password\": "${uuid}",
      \"ip\": \"${ip}\",
      \"congestion_control\": \"bbr\",
      \"alpn\": [\"h3\"]
    },
    \"local\": {
       \"server\": \"127.0.0.1:7798\"
    },
    \"log_level\": \"warn\"
}
"
}

function init() {
  echo "欢迎使用本脚本"
  echo "--- https://github.com/koopkl/auto-tuic ---
  0. 安装sing-box和tuic协议
  1. 卸载 sing-box和tuic协议
————————————————
  2. 启动 sing-box
  3. 停止 sing-box
  4. 重启 sing-box
  5. 查看 sing-box 状态
 ————————————————
  6. 编辑sing-box配置文件
  7. 生成小火箭配置文件
  8. 生成tuic-clien配置文件
"
read -p "请输入选择[0-8]: " choice
if grep '^[[:digit:]]*$' <<< "${choice}";then
  if (($choice >= 0 && $choice <= 8)); then
    case $choice in
      0) install_and_run
      ;;
      1) uninstall
      ;;
      2) start_sing_box
      ;;
      3) stop_sing_box
      ;;
      4) restart_sing_box;;
      5) log_sing_box;;
      6) edit_config;;
      7) gen_shadowrocket_config;;
      8) gen_tuic_client_config;;
      *) echo "Invalid input. Please enter a number between 0 and 8.";;
    esac
  else
    echo "错误，请输入正确的数字"
  fi
else
  echo "错误，请输入正确的数字"
fi
}

init
