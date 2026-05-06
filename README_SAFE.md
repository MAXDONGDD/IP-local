# IP-Sentinel Local Safe Task Note

项目目标：

```text
基于 hotyue/IP-Sentinel 做一个安全收敛版，用来处理 VPS IP 被 Google/YouTube 错误判区的问题，尤其是 YouTube 显示 CN、本应为 US 的情况。
```

部署位置原则：

```text
部署在最终出网 IP 所在 VPS 上。
谁的 IP 被 YouTube 判成 CN，就部署在谁上。
不要部署在 Mac 上。
如果 3x-ui 有链式出站，要部署在最终出口节点。
如果 YouTube 走 WARP，部署在原 VPS 对 YouTube 判区帮助有限。
```

安全版改造方向：

```text
只保留本机 Google / YouTube 区域纠偏
保留本机日志
保留本机定时任务
保留卸载脚本
可选保留 mod_trust 信用净化
```

需要移除/禁用：

```text
公共机器人模式
Master-Agent 远程控制
Telegram 控制面板
Webhook 监听端口 9527
远程触发接口
OTA 静默更新
遥测计数
自动开放防火墙端口
不必要的 root 常驻能力
```

建议项目形态：

```text
ip-sentinel-local-safe
```

建议使用方式：

```bash
sudo bash install_local.sh
```

运行方式：

```text
本机 cron/systemd 定时运行 runner
默认每 20-60 分钟执行一次，可配置
不监听任何公网端口
不接收远程指令
不自动执行上游新代码
```

需要保留的核心文件/逻辑：

```text
core/mod_google.sh
core/mod_trust.sh 可选
core/runner.sh
data/regions
data/keywords
data/user_agents.txt
```

需要重写/新增：

```text
install_local.sh
uninstall_local.sh
config.example
README_SAFE.md
```

安全检查目标：

```bash
ss -lntp | grep ip_sentinel
systemctl list-timers | grep ip-sentinel
crontab -l | grep ip_sentinel
tail -f /opt/ip_sentinel/logs/sentinel.log
```

上游更新策略：

```text
监控 hotyue/IP-Sentinel 上游更新
不自动合并
人工审查差异
只移植安全、有用的数据或逻辑
继续排除 Master/Webhook/OTA/遥测
```

风险说明：

```text
这个工具不是即时修复工具，而是 IP 养护/判区纠偏工具。
可能需要数天到数周。
不能保证 Google/YouTube 一定更新判区。
自动访问 Google/YouTube/本土站点可能有服务条款风险。
建议先部署在可重装测试 VPS 上。
```

