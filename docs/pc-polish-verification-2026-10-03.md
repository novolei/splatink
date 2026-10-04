# PC 打磨检查记录

本记录持续更新至 2026-10-04。Windows/macOS 优先；Android 后续，iOS 暂缓。这里的“通过”只对应列出的检查范围，不能推断全部内容已经达到 100% 一致。

## 已有证据

| 检查 | 结果与范围 | 日志或报告 |
| --- | --- | --- |
| 原受击弹簧、累积方向、头部 FK/look/STAB、停步承接、骨架与射击恢复 | 6,354 项通过；最大标量弹簧误差约 9.54e-7 | `shots/pc-hit-inertia-corrected.log` |
| UI 页面实际 GPU 渲染 | 26 页输出，脚本/解析/着色器错误扫描干净；截图仍需视觉对照 | `shots/pc-ui-polish-matrix-final.log` |
| HDR 泛光原 GPU 对照 | 164,252 通道通过；高通、五级模糊和半尺寸合成一致，最终半浮点叠加有舍入差 | `shots/pc-bloom-gpu-contract-current.log` |
| 真实本地 ENet 两端 | 移动、涂墨、受击、爬墙 attach/detach、超级跳跃状态、结算和 12 秒回房通过；同一进程使用两套独立 SceneMultiplayer | `shots/pc-lan-superjump.log` |
| 实际 Game 断线清场 | 房主断开后客户端回 Online、清理旧场景/角色、恢复鼠标且不发正常 XP；重复旧包不恢复战斗 HUD | `shots/pc-net-abort-game-fixed.log` |
| Windows ↔ macOS 真实 LAN | Mac Host 20 项、Windows Guest 18 项均通过；真实 ENet 双机器、8 槽/2 人/6 Bot、双向 HP/移动/涂墨消息、结算/12 秒回房及第二局房主断开 | `shots/pc-lan-macos-host.json`、`shots/pc-lan-windows-guest.json` |
| 四图源角色碰撞 | 109,221 项通过；Float64 二进制几何用于生产角色 OBB/脚底/台阶/屋顶/墙面解析 | `shots/pc-actor-physics-binary.log` |
| 实际 Actor 连续运动 | 694 帧、14 类原 Actor.update 输入共 9,743 项通过；生产已使用该后端 | `shots/pc-actor-controller-integrated.log` |
| 四图寻路结果与缓存边界 | 3,004 项通过；Packed heap 默认开启，保持源搜索顺序；32,768 堆操作及四图路径共 49,184 项通过 | `shots/pc-nav-packed-default.log`、`shots/pc-nav-heap.log` |
| 运动匹配与惯性混合 | 105 项通过；时钟释放修复后实际 shinL 最大单帧 19.58°，保持原 20° 门限 | `shots/pc-motion-inertia-corrected.log` |
| 原瞄准/摇杆/扩散 | 原 Player.js、Physics.js 计算的 180 组瞄准、800 组胶囊、900 帧输入及立即鼠标输入共 14,206 项通过 | `shots/pc-player-raw-look.log` |
| 原投射物和蓄力命中 | 原 Projectiles._step 42 类及 fireCharger 8 类、419 项通过；包含原 actor/Boss/墙面顺序、尺寸、原始伤害 ID 与甩墨距离衰减 | `shots/pc-projectile-contacts.log` |
| 实际 PC 输入和实时地图 | 30 项通过：鼠标事件在下一物理帧之前改变视角、移动、射击涂墨、潜墨补充、跳跃、暂停、Tab 五枚投影标记及正确 1–4 跳跃槽 | `shots/pc-input-immediate-event.log` |
| 原 puff/glow 精灵 | 874 帧、33,911 项通过；验证源轨迹、随机旋转、寿命、尺寸、透明度与提交到渲染器的实例数据 | `shots/pc-fx-sprites-current.log` |
| 七类生产准星和受击状态 | 状态与 GPU 检查 58 项通过、20 图输出；含圆角、盾阴影、幽化像素与静态阴影缓存 | `shots/pc-reticle-round-shield-gpu.log` |
| 可选骨骼帧间插值 | 32,799 项通过；权威 pose 误差为零，但实际成本仍较高，默认关闭 | `shots/pc-pose-optimized.log` |
| 原投射物逐帧时序 | 13 段、596 帧、7,175 项通过；延迟跨零当帧推进、严格寿命边界、轨迹/重力/拖曳/尾滴阈值 | `shots/pc-projectile_motion-throwables.log` |
| 原炸弹与云弹时序 | 8 段、334 帧、6,734 项通过；反弹/格栅/引信/完整步长云弹落点与源超时策略 | `shots/pc-throwables-throwables.log` |
| 原投射物 FX polling | 2,690 项通过；每类距离、年龄、可见性、共享预算与 slosher 配方 | `shots/pc-fx_projectile_hooks-drops.log` |
| 原墨滴 Float32 池 | 8 段、379 帧、21,267 项通过；提交轨迹/半径/拉伸/回收/海面落点。容量和碰撞预算仍是原生适配值 | `shots/pc-fx_drops-drops.log` |
| FX 颜色和照明 | 1,390 固定断言及当次 2,513 随机提交包断言通过；六套色板、源线性混色和环境光 | `shots/pc-fx_colors-throwables.log` |
| 原 GTAO / PD compute | 4 个原 GPU 案例、168,564 通道通过；alpha/background 误差零。尚未接入生产法线采集与场景 | `shots/pc-ao-gpu-contract.log` |
| 原生 ENet 分包边界 | 112 项通过；1200 字节预算、乱序/丢片/过期/重复/重连以及完整 Actor/Boss 元数据。此项是编解码检查 | `shots/pc-native-tick-contract.log` |
| Windows ↔ macOS 实际 Game | Mac Host 39 项、Windows Guest 38 项，两个真实 InkGame/8 Actor，双向移动/注入涂墨与伤害、结算、12 秒回房、第二局断线清场；日志无错误/警告 | `shots/pc-lan-actual-macos-host-fixed.json`、`shots/pc-lan-actual-windows-guest-fixed.json` |
| 原生下半身 Motion Matching | 2,809 项真实插件检查、105 项运动与78项握枪/瞄准检查通过；九骨骼过滤、真实 exact query、C0、上半身排除及根位移不变 | `shots/pc-native-mm-fixed-contract.log`、`shots/pc-native-mm-quality.log`、`shots/pc-native-mm-aiming.log` |
| 原生下半身实际 PC 输入 | 33 项通过；8个真实查询器、潜墨/跳跃后继续查询、立即鼠标、射击、暂停和实时地图 | `shots/pc-native-mm-real-input.log` |
| 联机墨雨归属 | 原 `_updateClouds` 8 段/77 帧、2,439 项通过；远端云只在受害者所属客户端伤害一次。真实双机墨雨击杀尚未单独测试 | `shots/pc-storm-los-contract.log` |
| 原范围伤害遮挡 | 原 Bomb/Blaster/Slosh/Slam 和 Physics.los 的28类、373项通过；原5cm末端缩短、格栅穿透和各自起点 | `shots/pc-area-los-contract.log` |
| News 窄修 GPU | news-1/news-2/main 三页渲染，无日志错误；外框、阴影、细 grain、胶带与焦点修正已视觉对照 | `shots/pc-news-polished-gpu.log` |
| 下半身摆腿呈现 | 450,062项通过，支撑脚最大误差1.07cm、上身全局误差0；完整八角色GPU对照运行干净，保持默认关闭 | `shots/pc-lower-presentation-contract.log`、`shots/pc-boss-lower-{off,lower}.json` |
| 墨滴批量提交试验 | 47,527项真实buffer检查通过，已有source FX契约OFF/ON均通过；完整场景没有支持默认启用的收益 | `shots/pc-drop-batch-contract.log`、`shots/pc-boss-drop-batch-{off,on}.json` |

## 性能采样修正

真实游戏失焦时暂停离线对战。早期 GPU 截图仅以进程运行 32 秒为依据，没有记录实际对战秒数，部分样本只运行了约 6 秒实战。这些样本不再作为性能验收依据。

现在用显式开发参数 `--benchmark-background --nonpersistent` 保持无人值守模拟，并禁止写入玩家设置/进度；普通玩家运行仍保持失焦暂停行为。报告增加 `capture_clock_seconds`、`playing_seconds`、`focus_paused` 和 `unattended_simulation`，帧统计只收集正在模拟的对战。

另一个采样问题已修正：早期 `fps_average` 是在每个渲染帧重复采样 `Performance.TIME_FPS` 后求算术平均，会偏向帧数较多的区间。旧报告中的 124.35、78.89、84.39、59.26、64.38 等数字保留为历史引擎监控均值，不能作为最终平均 FPS。新报告直接采用渲染帧数除以这些帧的 delta 总时长，并单列 `engine_fps_monitor_average`、`sampled_render_seconds` 和 `fps_method`。旧帧时间分位、模式启用数与无错误检查仍有其明确范围。

原墨滴和缓存阴影基线真实 GPU 检查为 Windows、RTX 5090、D3D12 Forward Mobile、1280×720、高画质、4096 图集、8 人 Boss 傍晚场景，144 FPS 上限、默认不启用 pose presentation。32 秒窗口包含 24.78 秒实战；1,781 个渲染帧覆盖 24.77185 秒，实际平均 **71.90 FPS**，p95 **33.33ms**。同时记录的旧引擎监控均值为 103.49，体现两种统计口径的差异。此结果仍有帧时间尖峰，不能称为性能整体验收通过。见 `shots/pc-boss-drops-profile.json/.log`。

最新工作区同条件原生下半身 off/on 两组均为24.78秒实战、seed37、144上限且日志无错误：真实平均73.07/88.41 FPS，帧长p95 34.99/30.95ms，on确认8个原生查询器。角色更新p95 7.74/6.15ms、每角色惯性化p95 .152/.022ms；on真实新查询CPU中位/p95 .017/.021ms。C++搜索与九骨骼惯性化同时变化，且战斗/FX轨迹会受渲染调度影响，整局FPS差不能全部归于搜索器。见 `shots/pc-boss-native-mm-{off,on}.json/.log`。仍不足以宣称完整帧预算或运动观感已达标。

逐角色/逐Bot计时标签保留前7200条，8角色60Hz会在约15秒填满；整队game_*与render标签覆盖上述完整实战窗口。因此它们的max/p95不能相加或当成同一慢帧；还需联合帧号记录来定位尖峰。实际新查询的独立契约只采378笔新增查询，中位/p95/max10/16/19µs，见 `shots/pc-native-mm-query-sampling.log`，此前1512帧重复记录不再作为查询次数。

同一导出包的 off/all/local 三组 144 上限检查分别确认为 0/8/1 个角色启用插值，均有至少 24.78 秒真实实战且无运行错误；其 p95 为 25.00/45.83/34.56ms，仍不足以把插值改为默认。全角色每角色捕获/恢复/呈现中位约 130/52/101µs，权威 Actor 更新中位 6.81ms，相比关闭的 5.11ms 增加。相同随机种子不能保证不同渲染调度下的战斗和 FX 轨迹完全一致，不把整局差值全归于插值。见 `shots/pc-boss-144-{off,all,local}.json/.log`。更早 `--max-fps 144` 被游戏设置覆写的样本仍不能称为限帧验证。

准星辅助视口单独计时后，缓存版本最近刷新 GPU p95 0.096ms、max 0.197ms，CPU p95 0.113ms；准星自身 CPU 中位/p95 0.050/0.077ms。静态几何使用 UPDATE_ONCE，约 2,206 个运行帧只请求 709 次滤镜批次。该数据包含准星辅助面，其他辅助视口仍未合并为完整 GPU 帧预算。见 `shots/pc-boss-reticle-cached-profile.json/.log`。

Windows/Mac 快照 `20261003161513` 的包内启动、对战与实际 GPU 检查通过。运行时改色 SVG 保留字节完全一致的 `.svg.txt` 伴随文件，解决导出包缺少原 SVG 文本的问题。首次隔离导入的字体 Unicode 错误在重建该快照字体缓存后消失；没有更改字体字节。Mac M2 Max 的 Boss 检查为 24.78 秒实战、2,480 帧、p95 11.11ms，旧引擎监控均值 100.64，下一包需采用新的 FPS 统计。Mac GPU timestamp 不可用，报告明确 `gpu_timing_available=false`。见 `shots/pc-macos-polish-build-record.json`。该包早于后续墨滴/炸弹/网络及下半身 MM 接入，不能当成当前全部工作区的最终成品。

## 正在修正的差异

最新双PC开发快照 `20261003180842` 的Windows/macOS独立导入、导出、包内启动/对战、实际GPU检查已通过；两平台均确认8个原生MM查询器。Mac同源universal扩展的2,809/105/78项查询/运动/瞄准检查通过，M2 Max包内Boss场景24.7833秒实战，实际平均106.56 FPS、p95 10.60ms。Mac GPU timestamp仍不可用。包与记录在 `builds/20261003180842-{windows,macos}/output/`；Windows可用 `Splatink-NativeMM.cmd`评审入口。该快照早于新摆腿呈现和墨滴批量提交试验，不代表这些新入口已包含在包内。

- Tab 展开地图已改用生产 diorama 流程和垂直实时 3D 投影、去除图片地图。原 diorama 没有标记避让；当前避让来自原 HUD 小地图算法，是可读性扩展，不能称为原 diorama 原样实现。
- 原网页 High/Ultra GTAO 的 compute 已通过原 GPU 对照，但生产法线采集、场景接入与完整成本尚待验证。精灵、墨滴和颜色空间已按上述范围通过；墨滴容量/碰撞预算、生产软上限拒绝覆盖、炸弹/投射物阴影与部分 FX polling 仍有差别，见 `pc-gameplay-fx-source-contracts.md`。
- 骨骼帧间插值要进一步降低完整 pose 写回和皮肤上传成本，才考虑默认开启。
- News 外框/阴影/细粒纹理、胶带和焦点状态已窄修并输出三页实图；badge字距、Cargo缩略图圆角白边/图标与细部AA仍有差别。
- 双机器实际 InkGame 的基础 LAN 生命周期已通过 39/38 检查。涂墨/伤害由真实管线确定性注入，Bot 为安静测试控制；未验证公网 relay、任意战斗或所有网络时序。第一轮 JSON 通过但存在旧相机错误的 `pc20261004a` 不算干净验收。
- 用户授权的原生 Motion Matching 下半身试验已通过 Windows/macOS 实际运行，入口 `--native-locomotion-mm` 默认关闭。完整源码、19/19冻结增量和新增API/编辑器释放修复均可复现；九骨骼惯性化保留现有速度感知实现。实际轨迹最大转角19.93°、髋部单帧位移4.50cm、脚接触误差1.07cm，保持既有门限。缺少专门起步/刹停/pivot动作，不能仅凭搜索替换宣称玩家运动已更优雅。Mixamo Locomotion Pack没有起步、刹停或跑动pivot；四段站立转身的独立重定向已通过portable/native 985341/985355检查，内段连续性最大17.45°，但切入过渡和当前控制器快速转向时序尚未适配，未接入生产。见 `motion-matching-plugin-assessment.md`、`mixamo-locomotion-pack-assessment.md` 和 `mixamo-turn-prototype.md`。

## 服务与产物边界

Mini Tanks 客户端、服务端与现有服务保持只读。已完成独立复用研究，见 `mini-tanks-server-reuse-audit.md`；Splatink 的 8 人涂墨协议不能直接接入坦克的 6 人协议和战绩存储。

PC 导出只在新的 Splatink 快照中执行，使用独立引擎缓存和平台模板。开发包需要完成导入、导出、包内启动/对战及真实 GPU 运行，才记为该轮检查通过；不代表签名、商店发布或游戏整体验收完成。
