# PC 房间与断线生命周期

来源是本地 `src/net/session.js`、`src/net/netmatch.js`、`src/main.js` 与 Splatink 的 `scripts/net`。本研究没有读取 Mini Tanks 的密钥、修改其文件、调用其生产服务或部署新服务。

## 突然断线

原 `session.js:130–138` 的 `_closed()` 在 starting/match 释放 NetMatch，再调用 `game.netMatchAborted()`；`main.js:684` 调用完整 `quitToMenu()` 并显示原因。此前 Splatink 的 `_server_left()` 仅断开网络和显示 toast，Game 仍可能继续处于 playing，网络失活后还会获得本地权威，形成玩家可见的虚假继续比赛。

`InkNetwork.match_aborted(reason:String)` 现统一处理 ENet server_disconnected 和 relay closed。先标记 active=false/phase=offline，再关闭 transport、清理 replication，最后发一次信号；消费者在信号回调调用 leave 或释放对局时不再重入旧连接。starting/match/results 的突断发信号；主动 leave、房间阶段失联、正常结果后12秒回房不发。Game 以 CONNECT_DEFERRED 消费信号，完整清场后打开 Online 并显示原因，以便重新连接。原网页回 Main；原生 Online 入口是本次 PC 体验决定。

断线处理不调用结果判定或 XP 奖励。`InkUI.nonpersistent` 在 `_ready` 前设置，仅禁止 `_load/_save`，用于 QA 不读写用户设置；Game 同时用 `--nonpersistent` 禁止进度读写。这一标志不改变页面过渡或 fixture 内容。

## 可复查的执行脚本

- `scripts/net/tests/connection_loss_probe.gd`：单引擎、两 SceneMultiplayer 分支、真实 localhost ENet。逐项关闭 starting/match/results 的 host，验证 guest 每项恰一次 abort；房间关闭和 guest 主动退出零 abort；回调内部再次 leave 验证重入边界。
- `scripts/net/tests/abort_game_fixture.gd`：真实 InkGame guest 与 ProbeGame host，通过 ENet 握手/ready/go/playing，再关闭 host。验证实际清场/Online/HUD/鼠标/旧演员释放，以及内存进度不变和重复 callback 零新增 abort。
- `scripts/net/tests/local_pair_probe.gd`：此前已验证 paint/hit/movement/results/12秒回房。新增正常回房与主动退出 abort=[0,0]，climb bit attach/detach 各端恰2次断言。

所有 Godot 执行由 root 通过 `tools/run_godot.ps1` 串行运行。`shots/net_connection_loss.json` 已通过5种实际 ENet 断开情形。第一轮实际 Game 虽 JSON 断言通过，日志存在旧 ViewportTexture 释放后的宽高查询 ERROR，且断线前 HUD 被旧房间 refresh 覆盖，不能视为干净；已清理 HUD 旧纹理引用并拒绝 starting/match 时迟到的 lobby 页面刷新，增加断线前 HUD 活动断言。

随后 `shots/pc-net-abort-game-fixed.log` 实际重跑无 ERROR，`net_abort_game.json` before.in_match/menu_hidden 都为 true，after 的 Online、鼠标可见、旧演员移除、stage替换、local_player清理、内存进度未改变等断言通过，abort恰一次。`shots/pc-lan-climb-abort.log` 20秒实际 ENet 也无 ERROR，双方 climb 事件恰2次，结果送达/双方回房、正常退出 abort=[0,0] 通过。随后 pc-lan-superjump.log 的20秒实际运行也无 ERROR，远端 Super Jump BUSY 的 charge/flight/land 位断言通过，结果送达/双方回房与 abort=[0,0] 继续通过。

Super Jump 代理使用源 `netmatch.js:38/356/695` 的16384/32768位，避免在线地图把正在飞行的队友错误视作可跳跃。source-physics grounded 位优先 Actor.is_grounded/set_remote_grounded，使远端地面/落地姿态跟随源碰撞后端。

## 原生 ENet 快照尺寸

首次实际 InkGame 双机测试的 JSON 断言通过（host36/guest35），但 guest 日志仍有房间返回时旧演员 transform 查询 ERROR，Mac host 还报告1944字节快照超过1392 MTU；因此该次不能算干净集成结果。Root 处理 Camera 跟随对象清理，`scripts/net/native_tick_codec.gd` 与 `native_tick_inbox.gd` 将过大的原生 `k:'t'` actor数组及 Boss/统计元数据分为不超过1200字节预算的 RPC。预算包含 RPC 参数序列化、十字符 peer ID 与64字节头部余量。完整21值 actor行不拆分，帧全部到达后才交原有 replication；丢片帧不改变人物或 Boss。

原生 tick 使用 unordered unreliable，再以源 timestamp 拒绝 small/fragmented 之间的过期完整帧，避免旧 HP/clock/stats 回退。重组限制为每帧128片/64KiB元数据、每 sender2帧/全局16帧和1秒超时，断线/正常回房清历史。可靠消息与原始 WebSocket relay 分支保持原行为。`scripts/net/tests/native_tick_contract.gd` 是独立预算与乱序/丢失/重复/超时测试；在 root 运行及双机实际重跑之前，只能说修复实现已具备验证入口，不能宣称联机错误已完成解决。

随后 root 的 `shots/pc-native-tick-contract.json/.stdout` 已干净通过112项、零失败，最大预算尺寸1200字节，报告明确 `actual_enet=false`。实际 Game fixture 新增两端原生发送、guest完整分片重组、host小包时间线与缓存上限证据。

`pc20261004b` 的实际 Windows ↔ macOS 两设备重跑已接受为干净集成：`shots/pc-lan-actual-macos-host-fixed.json` 为 host39项零失败，`shots/pc-lan-actual-windows-guest-fixed.json` 为 guest38项零失败；root 核对两端日志无引擎 ERROR/WARNING，Windows 本地日志为 `shots/pc-lan-actual-windows-guest-fixed.stdout`。报告明确 `actual_game=true/real_enet=true/single_process=false`。真实8个 source-physics Actor、Tidewater Stage、生产 HUD/跟随镜头、本地控制器移动、跨端 paint/伤害、8人结果、12秒回房与第二局 host关闭后的清场通过。双方GO=2/end=1，guest结果送达且abort=1，host主动关闭abort=0；用户设置/进度文件未改变，未中断对局的内存XP保持不变。测试通过生产 paint_splat/Actor.damage 注入确定性样本，Bot命令为 quiet，未覆盖所有实战攻击或AI表现。

该轮 guest 重组完成52帧、expired20、pending/rejected/buffered均0，双方没有预算错误。guest 的 sent_native_frame=130 是其自身发送计数，不能与其接收的host完整分片数52相除来当作丢包率；旧 expired 计数也没有区分容量淘汰与超时。后续只增加发送small/fragmented/parts计数、接收超时/容量/重复/过期细分及测试可选的每sender到达间隔统计；生产默认不收集间隔数组。下一双机 telemetry fixture 还未运行，压缩仅在测试内测量原字节的无损往返/大小/耗时，没有启用任何新压缩传输。以上实测只接受指定功能链路，尚不能证明远端运动接收节奏或联机体验已完美。

## 尚未解决的房间边界

2026-10-04 的真实 Windows ↔ macOS 双机 LAN 运行已通过：`shots/pc-lan-macos-host.json/.log` 为 host 20 项零失败，`shots/pc-lan-windows-guest.json/.log` 为 guest 18 项零失败，两个日志都无引擎错误。双方 GO=2、正常 end=1，guest 收到结果并在第二轮房主关闭后 abort=1，host 主动关闭 abort=0。这是 `scripts/net/tests/lan_process_contract.gd` 的两个独立进程和实际 ENet 链路；两端报告明确 `actual_game=false`，因为演员由 ProbeGame 提供。它验证跨设备协议和房间生命周期，不能代替真实 InkGame/InkActor/InkStage/HUD 的双机集成或 GPU 性能验证。

源 relay 在 `session.js:282` 开赛锁房，`server/src/index.js:76` 拒绝 Match in progress；原生 ENet `_peer_connected()` 尚未对比赛中加入发送明确拒绝，因此晚加入可能停在空房间。源 relay `session.js:150–160`、`netmatch.js:627–642` 会移交原房主的人物/Bot/Boss/时钟；原生当前仅更新 host_id 与退出玩家 slot，不能把 ENet 房主进程关闭解释为完整房主迁移。公网原 relay 的互操作与跨设备链路未验证，这些缺口不属于此次单项断线修复的完成证明。
