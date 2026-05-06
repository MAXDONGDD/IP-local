# ip-sentinel-local-safe

基于 [hotyue/IP-Sentinel](https://github.com/hotyue/IP-Sentinel) 思路整理的本机安全收敛版，用来处理 VPS IP 被 Google / YouTube 错误判区的问题，尤其是 YouTube 显示 CN、本应为 US 的情况。

## 部署位置原则

部署在最终出网 IP 所在 VPS 上。

谁的 IP 被 YouTube 判成 CN，就部署在谁上。不要部署在 Mac 上。如果 3x-ui 有链式出站，要部署在最终出口节点。如果 YouTube 走 WARP，部署在原 VPS 对 YouTube 判区帮助有限。

## 安全版范围

保留：

- 本机 Google / YouTube 区域纠偏
- 本机日志
- 本机定时任务
- 卸载脚本
- 可选 `mod_trust` 信用净化

移除/禁用：

- 公共机器人模式
- Master-Agent 远程控制
- Telegram 控制面板
- Webhook 监听端口 9527
- 远程触发接口
- OTA 静默更新
- 遥测计数
- 自动开放防火墙端口
- 不必要的 root 常驻能力

## 使用方式

先按需编辑配置：

```bash
cp config.example config.conf
vi config.conf
```

在最终出口 VPS 上执行：

```bash
sudo bash install_local.sh
```

安装后默认通过 systemd timer 每 30 分钟触发一次；如果目标系统没有 systemd，会降级写入 root crontab。脚本不监听任何公网端口，不接收远程指令，不自动执行上游新代码。

## 配置重点

- `REGION_CODE=US`：目标 Google / YouTube 国家或地区代码。
- `LANG_PARAMS=hl=en&gl=US&ceid=US:en`：Google 请求的区域语言参数。
- `BASE_LAT` / `BASE_LON`：目标区域内的坐标锚点。
- `ENABLE_GOOGLE=true`：启用 Google / YouTube 区域纠偏模块。
- `ENABLE_TRUST=false`：默认关闭信用净化模块，需要时手动开启。
- `BIND_IP=`：可选，绑定指定本机出口 IP。
- `IP_PREF=4`：默认 IPv4，可改为 `6`。
- `RUN_INTERVAL_MINUTES=30`：定时执行间隔，建议 20-60。

## 运行与检查

```bash
sudo /opt/ip_sentinel/core/runner.sh
sudo bash /opt/ip_sentinel/status_local.sh
ss -lntp | grep ip_sentinel
systemctl list-timers | grep ip-sentinel
sudo crontab -l | grep ip_sentinel
tail -f /opt/ip_sentinel/logs/sentinel.log
```

正常情况下，`ss -lntp | grep ip_sentinel` 不应输出任何监听端口。

生成近 7 天运行报告：

```bash
sudo bash /opt/ip_sentinel/status_local.sh
```

## 上游更新策略

监控 `hotyue/IP-Sentinel` 上游更新，但不自动合并。

人工审查差异，只移植安全、有用的数据或逻辑，并继续排除 Master、Webhook、OTA、Telegram 控制面板、遥测和公网监听能力。

可用辅助命令查看上游最新提交：

```bash
bash scripts/check_upstream.sh
```

## 风险说明

这个工具不是即时修复工具，而是 IP 养护 / 判区纠偏工具。可能需要数天到数周，不能保证 Google / YouTube 一定更新判区。

自动访问 Google / YouTube / 本土站点可能有服务条款风险。建议先部署在可重装测试 VPS 上，并把执行间隔保持在保守范围。

## 卸载

```bash
sudo bash /opt/ip_sentinel/uninstall_local.sh
```
