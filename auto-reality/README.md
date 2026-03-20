# auto-reality

一个参考 `auto-tuic` 风格的简易脚本，用于安装和管理 sing-box 的 VLESS + Reality 入站。

## 用法

```bash
cd ~/projects/auto-tuic/auto-reality
chmod +x auto-reality.sh
sudo ./auto-reality.sh
```

## 菜单功能

- 0 安装 sing-box 和 Reality(VLESS)
- 1 卸载 sing-box 和 Reality
- 2 启动 sing-box
- 3 停止 sing-box
- 4 重启 sing-box
- 5 查看 sing-box 状态
- 6 查看 sing-box 日志
- 7 编辑 sing-box 配置文件
- 8 查看客户端配置参数
- 9 生成 Shadowrocket 导入 URI
- 10 查看当前服务端配置摘要
- 11 生成二维码(终端+PNG)

## 说明

- 配置文件：`/etc/sing-box/config.json`
- 客户端参数保存文件：`/etc/sing-box/reality-client.txt`
- 二维码 PNG 输出：`/etc/sing-box/reality-client.png`
- 默认监听端口：`10443`
- 默认伪装域名：`www.microsoft.com`
- 安装依赖时会额外安装 `qrencode`，避免依赖 Python。
