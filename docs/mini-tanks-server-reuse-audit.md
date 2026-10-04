# Mini Tanks 服务架构只读研究（2026-10-03）

本轮仅读取 `H:/GDP/mini-tanks` 的文档和服务源代码。没有修改该项目、启动其服务、连接生产大厅、读 `.env` 或账户数据，也没有读取或输出凭据。用户当前优先 PC 体验，手机后续，iOS 暂停。本报告是隔离实现依据，不代表 Splatink 已复用或部署现有线上服务。

## 已核对来源

| 源文件 | 主要接口或职责 |
| --- | --- |
| `H:/GDP/mini-tanks/AGENTS.md`、`docs/HANDOFF.md` | 服务、生产测试、凭据和多会话保护约束；最新交接状态 |
| `docs/online.md` §1–4、§8、§12、§13 | 大厅 RPC、对局路由、权威模型、protocol epoch、输入边界、开发环境隔离 |
| `server/main.cjs` | `createServer(options)`、`route(pathname)`；公开 HTTP/WS 与内部 WS 两个端口，升级请求路径与连接角色隔离 |
| `server/lib/ws.cjs` | `Hub`、`Conn`；原生 Node WebSocket 帧解析、消息/字节预算、心跳、错误边界 |
| `server/lib/lobby.cjs` | `createLobby(deps)`、`attach(conn)`、`handle(conn,m)`；鉴权后 RPC 分发、在线会话、推送 |
| `server/lib/auth.cjs`、`steam_auth.cjs`、`admission.cjs` | `createAccounts`、`resolve`、`byToken`；随机游客凭证的散列保存、平台身份、Steam 验证、邀请/版本准入 |
| `server/lib/rooms.cjs` | `serialize`、`createRoom`、`requireOwner`、`requireEpoch`；创建/加入/准备/换队/开局/退出/房主变更 |
| `server/lib/matchflow.cjs` | `startMatch`、`payload`、`onReport`、`finish`；生成 plan+单局票据、启动专服、完整终局落账 |
| `server/lib/matches.cjs` | `createMatches`：`canStart/start/connected/reported/stop/tick/killAll/list`；单局子进程、容量、日志、超时和回收 |
| `server/lib/relay_dedicated.cjs` | `createDedicated`：`register/attach/fromPlayer/fromServer/end/remove`；玩家只送权威进程、只让专服代发 |
| `server/lib/relay_guard.cjs` | `checkPlayerMessage`、`KINDS`、字节预算、尺寸/深度/类型检查；违规只关闭违规连接 |
| `server/lib/protocol.cjs`、`room_settings.cjs`、`config.cjs` | epoch 分代、地图/时长/座位白名单、配置选项及默认值 |
| `tools/server/README.md`、`mini-tanks.service`、nginx 模板、`deploy.sh` | 部署目录、独立内部端口、systemd 进程组、资源预算、排空、冒烟后原子切二进制链接 |
| `game/online/online_endpoint_guard.gd`、`modules/net/link_heartbeat.gd`（文档引用） | 本地开发禁止生产连接、半开连接探测/恢复的参考接口 |

## 传输、身份与开局

Mini Tanks 使用 WebSocket JSON：大厅 `/mt/lobby` 收 `{"t":method,"rid":integer,...}`；回 `res {rid,ok,d/err}`，广播 `push {ev,d}`。必须先 `auth`，再允许 `room.create/join/team/ready/settings/start/leave`。大厅存放服务器签发的 uid 与 token 散列，游客身份可绑定经过服务端验证的平台身份；它不是 Splatink 当前源 relay 的 5 字符房号协议。

大厅房间与单局对局分开。`startMatch` 为每局新建 match code、稳定 peer plan、各玩家票据、协议 epoch，登记路由后拉起一个 Godot 无头进程。玩家打开 `/mt/match?room=...&ticket=...&protocol_epoch=...`；专服经仅回环的内部端口连接。公开入口拒绝专服角色，内部入口拒绝玩家。玩家包只传给专服，专服确认主人、血量、复活、计分和 Bot 后再转发。票据用于重连固定座位；结束推完整 final_stats，房间回 idle，单局进程自然退出或超时回收。

源码目前是 **每队 3 人、坦克配装、Mini Tanks 地图/击杀目标/战绩结构**。Splatink 是 **每队 4 人、墨色/武器/换装、四个源地图、涂地计分、Boss 模式**；其 `k:go/st/paint/hit/bhit/evt` 与 Mini Tanks 的 relay whitelist 形状不同。直接把 Splatink 客户端指向 `/mt/lobby` 或 `/mt/match` 会被拒绝或错误解释。

## 可以复用的层级

1. **架构模式**可以直接借鉴：独立大厅/对局生命周期、稳定槽位、短期单局票据、玩家只送权威端、完整终局一次提交、半开连接探测、每连接预算、异常局不计正常战绩。
2. **通用实现**可在 Splatink 内复制并改名、注明来源后独立维护：WebSocket 帧解析及尺寸限制、随机 ID/散列、调度/日志/子进程回收、输入检查工具。用户已授权复用自身 Mini Tanks 参考实现；复制时保留来源、已有许可声明与 Splatink 适配记录。
3. **运维模板**可新建 Splatink 专属 service/nginx/deploy 配置，套用排空→独立冒烟→原子版本链接流程。模板中的产品路径、端口、账号、资源额度必须替换；现有 Mini Tanks 部署脚本不得直接执行。

## 必须隔离的边界

建议全新 `/splatink/lobby`、`/splatink/match`、新 loopback 端口、`splatink.service`、`/opt/splatink/{server,game,data}`、单独 service user、凭据与日志。不能共用 Mini Tanks 的 uid/token store、邀请资格、Steam App 身份、最低版本/epoch、房间命名空间、统计榜单、管理密钥、二进制链接或 update 目录。同一主机的可用容量留待只读指标与后续隔离实测评估，不能依据源码默认 MAX_MATCHES 推断线上余量。

严格保留 Mini Tanks 的客户端、服务端、现有服务和资源预算。本轮没有修改其任何文件，也没有发起生产请求。当前原生 LAN 两分支 20 秒 probe 通过，包含结果送达与双方回大厅；INKWAVE 原 wss relay 的公网互操作仍未实测。建议 PC 首轮保持当前可验证 LAN 与原 relay adapter，未来在 Splatink 独立服务中移植上述生命周期和鉴权层，避免为了服务接入阻塞当前画面/操作体验打磨。

## 后续具体接口

若建设隔离权威服务，保留客户端 `InkNetwork` 外观：`configure/host/join/leave/start/set_ready/set_team/update/return_to_lobby` 与 `match_started/match_go/match_finished/match_ended/lobby_changed/status_changed`。新增 `InkLobbyLink` 负责 RPC、鉴权、票据；`InkMatchLink` 负责专服连接；`InkServerRunner` 负责无头对局入口。Splatink 白名单必须针对其实际快照/paint/bhit/evt 数据重新设计，不能复制坦克 KINDS 作为可用协议。Boss、涂地与终局应由 Splatink 专服权威执行，再运行真实两个客户端→隔离大厅→专服→结果→回房间链路验证。
