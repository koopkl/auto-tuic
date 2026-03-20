#!/bin/bash

CONFIG_FILE=/etc/sing-box/config.json
TUIC_TEMPLATE=tuic-config.json
REALITY_CLIENT_FILE=/etc/sing-box/reality-client.txt
REALITY_QR_PNG=/etc/sing-box/reality-client.png

function install_common_deps() {
  echo "安装环境依赖"
  apt update && apt install -y jq gawk uuid-runtime vim curl openssl qrencode
  echo "依赖安装完成"
}

function install_sing_box() {
  echo "开始安装sing-box核心"
  bash <(curl -fsSL https://sing-box.app/deb-install.sh)
  systemctl enable sing-box
  echo "sing-box安装完成"
}

function install_and_run_tuic () {
    install_sing_box
    install_common_deps

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

    if [ -f "$CONFIG_FILE" ]; then
      cp "$CONFIG_FILE" "${CONFIG_FILE}.bak-$(date +%Y%m%d-%H%M%S)"
      echo "已备份旧配置"
    fi

    mv tuic-config-updated.json /etc/sing-box/config.json
    rm -rf tuic-config.json

    echo "停止sing-box"
    systemctl stop sing-box
    echo "运行sing-box"
    systemctl start sing-box
    init
}

function gen_reality_keypair() {
  key_output=$(sing-box generate reality-keypair)
  REALITY_PRIVATE_KEY=$(printf "%s\n" "$key_output" | awk -F': ' '/PrivateKey/{print $2}')
  REALITY_PUBLIC_KEY=$(printf "%s\n" "$key_output" | awk -F': ' '/PublicKey/{print $2}')

  if [ -z "$REALITY_PRIVATE_KEY" ] || [ -z "$REALITY_PUBLIC_KEY" ]; then
    echo "Reality密钥生成失败"
    exit 1
  fi
}

function install_and_run_reality() {
  install_sing_box
  install_common_deps

  read -p "请输入客户端连接地址(域名或IP): " server_host
  if [ -z "$server_host" ]; then
    echo "server_host 不能为空"
    exit 1
  fi

  read -p "请输入Reality监听端口(默认10443): " reality_port
  reality_port=${reality_port:-10443}

  read -p "请输入Reality伪装域名/SNI(默认www.microsoft.com): " reality_sni
  reality_sni=${reality_sni:-www.microsoft.com}

  reality_uuid=$(uuidgen | tr '[:upper:]' '[:lower:]')
  reality_short_id=$(openssl rand -hex 8)

  gen_reality_keypair

  if [ -f "$CONFIG_FILE" ]; then
    cp "$CONFIG_FILE" "${CONFIG_FILE}.bak-$(date +%Y%m%d-%H%M%S)"
    echo "已备份旧配置"
  fi

  cat > "$CONFIG_FILE" <<EOF
{
  "log": {
    "level": "info"
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-reality-in",
      "listen": "::",
      "listen_port": ${reality_port},
      "users": [
        {
          "name": "default",
          "uuid": "${reality_uuid}"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${reality_sni}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${reality_sni}",
            "server_port": 443
          },
          "private_key": "${REALITY_PRIVATE_KEY}",
          "short_id": ["${reality_short_id}"]
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "auto_detect_interface": true
  }
}
EOF

  mkdir -p /etc/sing-box
  cat > "$REALITY_CLIENT_FILE" <<EOF
SERVER=${server_host}
PORT=${reality_port}
UUID=${reality_uuid}
PUBLIC_KEY=${REALITY_PUBLIC_KEY}
SHORT_ID=${reality_short_id}
SNI=${reality_sni}
SHADOWROCKET_URI=vless://${reality_uuid}@${server_host}:${reality_port}?encryption=none&security=reality&sni=${reality_sni}&fp=chrome&pbk=${REALITY_PUBLIC_KEY}&sid=${reality_short_id}&type=tcp#reality-${server_host}
EOF

  echo "检查配置..."
  sing-box check -c "$CONFIG_FILE"

  echo "重启sing-box"
  systemctl restart sing-box

  echo "Reality安装完成，客户端参数如下："
  show_reality_client_info
}

function uninstall() {
    echo "开始卸载sing-box"
    rm -rf /usr/bin/sing-box && rm -rf /etc/sing-box && rm -rf /etc/systemd/system/sing-box.service
    systemctl daemon-reload || true
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
  journalctl -u sing-box --output cat -e -n 200
}

function status_sing_box() {
  systemctl status sing-box --no-pager
}

function edit_config() {
  vim /etc/sing-box/config.json
}

function gen_shadowrocket_config() {
  port=$(jq ".inbounds[0].listen_port" ${CONFIG_FILE})
  uuid=$(jq ".inbounds[0].users[0].uuid" ${CONFIG_FILE})
  password=$(jq ".inbounds[0].users[0].password" ${CONFIG_FILE})
  host=$(jq ".inbounds[0].tls.acme.domain" ${CONFIG_FILE})
  echo "{
    \"host\" : ${host},
    \"alpn\" : \"h3\",
    \"uuid\": ${uuid},
    \"type\" : \"TUIC\",
    \"udp\" : 2,
    \"port\" : \"${port}\",
    \"obfs\" : \"none\",
    \"proto\" : \"bbr\",
    \"password\": ${password},
    \"user\": ${uuid}
  }"
}

function gen_tuic_client_config() {
  port=$(jq -r ".inbounds[0].listen_port" ${CONFIG_FILE})
  uuid=$(jq ".inbounds[0].users[0].uuid" ${CONFIG_FILE})
  host=$(jq -r ".inbounds[0].tls.acme.domain" ${CONFIG_FILE})
  ip=$(ip addr | awk '/^[0-9]+: / {}; /inet.*global/ {print gensub(/(.*)\/(.*)/, "\\1", "g", $2)}' | head -n 1)
  echo "{
    \"relay\": {
      \"server\": \"${host}:${port}\",
      \"uuid\": ${uuid},
      \"password\": ${uuid},
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

function show_reality_client_info() {
  if [ ! -f "$REALITY_CLIENT_FILE" ]; then
    echo "未找到Reality客户端参数文件: $REALITY_CLIENT_FILE"
    return 1
  fi
  cat "$REALITY_CLIENT_FILE"
}

function gen_reality_uri() {
  if [ ! -f "$REALITY_CLIENT_FILE" ]; then
    echo "未找到Reality客户端参数文件: $REALITY_CLIENT_FILE"
    return 1
  fi
  grep '^SHADOWROCKET_URI=' "$REALITY_CLIENT_FILE" | cut -d= -f2-
}

function gen_reality_qrcode() {
  if ! command -v qrencode >/dev/null 2>&1; then
    echo "未安装 qrencode，请先执行安装流程"
    return 1
  fi
  uri=$(gen_reality_uri)
  if [ -z "$uri" ]; then
    echo "未能生成URI"
    return 1
  fi
  echo "终端二维码如下(可直接扫码):"
  qrencode -t ANSIUTF8 "$uri"
  qrencode -o "$REALITY_QR_PNG" -s 8 -m 2 "$uri"
  echo "二维码PNG已生成: $REALITY_QR_PNG"
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
  7. 生成小火箭(TUIC)配置文件
  8. 生成tuic-client配置文件
————————————————
  9. 安装sing-box和Reality(VLESS)
 10. 查看Reality客户端参数
 11. 生成Reality导入URI
 12. 生成Reality二维码(终端+PNG)
"
read -p "请输入选择[0-12]: " choice
if grep '^[[:digit:]]*$' <<< "${choice}";then
  if ((choice >= 0 && choice <= 12)); then
    case $choice in
      0) install_and_run_tuic ;;
      1) uninstall ;;
      2) start_sing_box ;;
      3) stop_sing_box ;;
      4) restart_sing_box ;;
      5) status_sing_box ;;
      6) edit_config ;;
      7) gen_shadowrocket_config ;;
      8) gen_tuic_client_config ;;
      9) install_and_run_reality ;;
      10) show_reality_client_info ;;
      11) gen_reality_uri ;;
      12) gen_reality_qrcode ;;
      *) echo "Invalid input. Please enter a number between 0 and 12." ;;
    esac
  else
    echo "错误，请输入正确的数字"
  fi
else
  echo "错误，请输入正确的数字"
fi
}

init
