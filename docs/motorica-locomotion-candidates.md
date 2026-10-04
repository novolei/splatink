# Motorica 原始起停与跑动转身小样

当前为独立实验，`accepted_for_production=false`。三段原始 71 骨 FBX 已生成目标 87 骨角色的两种下身 Animation；正式 42 循环 / 1638 pose 库、原生 C++ 查询、Actor 控制器、生产 Avatar、冻结 Mixamo 候选均未修改。离线结果已发现脚滑和一处原动作的快速脚部旋转，不能作为正式移动验收。

## 原始素材与来源

只读来源是 `F:/Downloads/godot-motion-matching-demo-master/godot-motion-matching-demo-master/animation/motorica/running/forward/`。仅复制下面三个文件到 Splatink 的 `.tools/motorica-locomotion/source/`，原文件 SHA、大小和修改时间在复制与采样前后检查一致。

| 原始文件 | 原时长 / 30Hz 帧数 | 完整 Root 路程 | SHA256 |
|---|---:|---:|---|
| Run_Turns_StartStop_L_variation_1.fbx | 28.566667s / 858 | 57.9320m | `9149f1c3d9c7e9528654b13ee30938dc870abf08ef34002cff43fcb8c7d09bab` |
| Run_Turns_L_variation_1.fbx | 15.833333s / 476 | 58.3802m | `9ef0639f0a3d8a188755341a8eeb366cb05b6f7ae330519b97285d1a7489019e` |
| Run_Turns_180.fbx | 11s / 331 | 35.2649m | `49da698058455a09dc645becdbc295396eb331011dcd4f926148402f9754086d` |

这是原始 FBX 数据，不是 Rooftop 的 Meshy 24 骨 `.res` 再提取，也没有从文档名称推断动作内容。三个文件的 71 骨名称、父子关系、局部及全局 rest 矩阵逐项一致，最大差为 0。原文件 7700 版 FBX、+Y up、+Z forward、+X side，长度单位转换为 0.01m；层级是 `Root → Hips`，Root 与 Hips 的旋转分别保留。变化曲线均有准确 30Hz 时间，FBX key flags 为 `0x104`（linear）；帧末时间来自 key extent / Stack.LocalStop，而非误导性的全局 1s TimeSpan。

原始三个片段包含真实平移和转向，不是可直接循环的动画。前两段 Root 净转向约 450°；第三段净转向接近 0°，累计左右转向约 720°。没有外部 Root 位置跳变、yaw wrap、动画缩放或骨架 pivots 的未处理特殊项。这里的“Motorica”来源于原目录和原构建器；本地未找到针对这些 FBX 的独立授权文档，不把库名称等同于来源或再分发授权证明。

Rooftop 现用 Meshy 24 骨资源已是另一套目标 rest。`game/player/motion_matching/motorica_rooftop_meshy_library.res` 工作区 SHA 为 `b9cf8226dc95a6a210f5eeaf59bc963264ebbacb74a486a38e2570f928efa358`；冻结 release PCK 中库 SHA 为 `01e38133c412adeb00eabc58ff046269abf99dff039fb47b72b94e4db6be8a4b`，两者不相等。当前实验直接读取 F 目录的原始 71 骨，避开该 Meshy 重定向层。`F:/.../build_motorica_library.gd:82` 原构建器复制导入的 Take 001，`D:/Godot resource/rooftop-bird-team/tools/build_rooftop_motion_matching_library.gd:90` 再复制基础库并重烘特征；这些步骤本身没有合成新的起停动作。

## 重定向方法和实验边界

导出器 [motorica_retarget.py](../tools/motorica_retarget.py) 只借用冻结的 `mixamo_retarget.py` FBX 解析与 GLB rest 读取函数，不改该代码、不调用其 main，也不启动 Godot。先把每帧骨骼变换转入原 `Root(t)` 局部坐标，再使用 `R_source(t) · inverse(R_source_rest) · R_target_rest` 的全局 rest-basis 差量重建目标局部旋转，保持目标各段独立 rest 位移和单位缩放。

原 source 大腿 / 小腿长约 0.433413 / 0.422179m；目标为 0.275278 / 0.262939m。左、右大腿长度比约 0.635140，小腿 0.622814，脚段 0.685914，故没有统一缩放腿部所有位移。Root 和骨盆位移的展示参考比为总腿长比 `0.6290582239167961`；原 Root XZ、yaw、速度数组仍完整保留，没有覆盖为该参考比例。

| 模式 | Animation 写入 | 上身策略 | Root 策略 |
|---|---|---|---|
| source_path_pelvis9 | hips 位移+旋转、8 个腿脚旋转（10 tracks） | 保存并恢复 hips 下 spine / hemF / hemB 三个上身边界的 global pose | 动画没有 owner/root track；预览单独展示作者路径 |
| fixed_authority_leg8 | 8 个腿脚旋转 | 传入 hips 与所有上身 raw pose 保持；不插入骨盆摆动 | 与上模式使用相同作者路径作为比较参考；不接管控制器 |

目标骨为 hips、thighL/R、shinL/R、footL/R、toeL/R，目标骨架总数仍 87。原 body.glb SHA 保持 `ca43f303d96cd17990f91fbbf48378132ee4dca39e3f38df4b61ce9d19dc7ce3`。武器、手臂、面部、头发和换装资源均继续使用原 Splatink。预览只同步被改变的腿脚和上身边界到服装模块，其余模块 raw pose 也在下次采样前恢复。

运行时使用手动 `AnimationPlayer`，用于准确 scrub 独立完整 one-shot；此处没有新增 gameplay FSM / AnimationTree 层，也没有将实验候选提交给 native MM。场景结构为 `实验路径根 → InkAvatar → 原身体 Skeleton3D`，手动播放器与该 Skeleton 同级，跟随原骨架路径；环境、相机和顶部说明只存在于实验场景。

每次 `apply` 后，QA 精确恢复全部 87 骨 position / quaternion / scale，再调用下一次源 `avatar.animate`。这防止 FootPlant、inertializer、头部、上身补偿读取上一次实验姿态。实验不能改变 owner transform、MM 查询和播放时钟、IK 接触时钟或 hit 时钟。

## 从原始数据确认的窗口

所有窗口是原片段上的测量标注，不是剪短资源或作者事件标记。完整文件仍导出；预览选窗口只是指定原始起止秒数，播放速度为 1，无 timewarp、自动循环或 Root 控制器替换。

| 原片段 / 标注 | 时间窗口 | 实测行为 |
|---|---:|---|
| StartStop_L / first_start | 0.5–2.4s | 原 Root 从 0 加速到 3.95m/s |
| StartStop_L / first_stop | 3.2–5.2s | 原 Root 从约 4 降到约 0.009m/s |
| StartStop_L / second_start | 6.7–8.6s | 再次起跑，且窗口包含约 44.9°转向 |
| Turns_L / running_left_90 | 6–8s | Root 转 89.783°；速度最小 2.828m/s，持续跑动 |
| Turns_L / running_left_180 | 12.3–14.5s | Root 转 179.795°；最低约 0.027m/s，属于制动再转身 |
| Turns180 / first_left_180 | 0.6–2.8s | Root 转 179.822°；最低约 0.027m/s |
| Turns180 / first_right_180 | 2.7–4.9s | Root 转 −179.543°；最低约 0.022m/s |

速度按准确 30Hz Root 位置 `numpy.gradient` 计算：内部使用中心差分、端点单边差分。转身的中心差分速度可能近零，不与此前前向差分约 0.13m/s 的静态审计值混用。三段原速度峰均约 4m/s；按目标腿长展示参考约 2.516m/s。实际 Splatink dry kid 的 `runSpeed` 是 **6m/s**（`data/config.json:180`）；当前 MM 导出器的 in-place `run` 虚拟轨迹标签则是 **5.5m/s**（`tools/export_motion_database.mjs:16`），二者不能混用。参考作者路径与这两个速度均不匹配。现控制器快速响应与作者 1.9–2.2s 起停/转身窗口的时间匹配尚未做，不能说这些动作已适配实际快速输入。

## 未修正基线：质量明确未过

接触候选来自原 ToeBase / ToeBase_End 的低高度（各侧 floor + 0.03m）及低 XZ 速度（≤0.25m/s），是推断标签，非作者 foot-contact markers。每个连续候选 span 的目标脚底代理点在起始帧设固定测量锚点，然后测量真实 FK 对该点的漂移；锚点未逐帧追脚，也没有把脚锁到目标后宣称零脚滑。尚无 contact IK、时间滤波或膝盖修正。

| 完整片段 | pelvis9 最大未修正 FK 代理脚滑 | fixed8 最大未修正脚滑 | pelvis9 预计 60Hz slerp 最大局部步进 |
|---|---:|---:|---:|
| StartStop_L | 0.142384m | 0.173725m | 0.276406rad |
| Turns_L | 0.190133m | 0.168344m | 0.437276rad |
| Turns180 | 0.119842m | 0.107979m | 0.345128rad |

上表是 Python 目标 rest 的离线 FK，不能冒充实际 Godot Avatar 骨架/渲染结果。三段两模式均没有通过 3cm 接触门限。Turns_L 原右脚本身在 387→388 帧（12.9333s）转约 50.11°/30Hz；重定向保留的 60Hz 半步约 0.4373rad，也没有通过严格 0.35rad 门限。另一原右脚 292→293 帧约 47.22°。这些原数据特点已独立核对，不能通过偷偷改变原时序或放宽门限消失。

Root 已完成 Windows fresh import 及 **shooter / native ON / 三段完整时长 / 两模式** 的实际 Godot 检查：1,500,632 项，结构失败 0、质量失败 8，exit 1。两份 import 及运行 log/stdout 没有 parser/runtime/shader ERROR 或 WARNING；工具明确打印的 `MOTORICA_QUALITY_FAIL` 是未过的测量，不能改称为全部通过。记录为 [motorica-contract-shooter-native.json](../shots/motorica-contract-shooter-native.json)、`shots/pc-motorica-native.log` / `.stdout`。

同一 Windows shooter 完整片段检查也完成了 **portable** 对照：1,500,630 项，结构失败 0、质量失败 8，exit 1；`shots/pc-motorica-portable.log` / `.stdout` 均无 parser/runtime/shader ERROR 或 WARNING。[motorica-contract-shooter-portable.json](../shots/motorica-contract-shooter-portable.json) 记录 5426 个推断接触观测，upper global 最大位置误差 `4.7847868245e−7m` / basis `3.8426509263e−7`，世界枪口误差 0，provider 为 `portable source pose matcher`、native query count 为 0。两个 provider 均保留同样的八项质量失败；两次运行各保留其测量结果，不把脚滑数值的小差别解释为 native 改善。

实际 5426 个推断接触观测，upper global 最大位置误差 `4.18561e−7m` / basis `3.84265e−7`，世界枪口误差 0；owner、MM/IK clocks 和每次 87 骨 raw restore 通过。实际 provider 为 `native MMAnimationLibrary exact contiguous search`，1664 次真实查询、现有 family bucket 234。该查询属于原生产循环库；Motorica 动作由独立实验播放器写入下身，未加入 native candidate DB。

| Godot shooter 完整片段 | pelvis9 实际 FK 脚滑 | fixed8 实际 FK 脚滑 | 实际最大 60Hz 局部步进（两模式） |
|---|---:|---:|---:|
| StartStop_L | 0.104219m | 0.290927m | 0.276410rad |
| Turns_L | 0.150423m | 0.188465m | 0.437272rad |
| Turns180 | 0.084015m | 0.185655m | 0.345129rad |

8 项质量失败为六个完整片段/模式的 3cm 接触失败，加 Turns_L 两模式在 12.933333s / footR 的 0.35rad 连续性失败。Python 离线表采用目标 rest hips；实际 Avatar 固定模式保留当时的源 hips 和 skin 模型节点，故两表不能混成同一条件的收益对比。尚未实施接触或 entry 修复。

Source-hold 到作者首帧 entry 仍未过渡：实际 pelvis9 为 0.229872 / 1.081463 / 0.910483rad，fixed8 为 0.538488 / 1.080812 / 0.894632rad（StartStop_L / Turns_L / Turns180）。这些只测量，不算完成 entry gate。当前只验证 shooter，一些结构已通过但质量明确未过；不能宣称实战、七武器、Mac 或脚接触验收通过。

首轮三窗口 GPU fixture **失败且未验收**：初始空 `entry.authority` 为 untyped Array，预览将其直接赋给 `Array[Dictionary]`，导致 seek 没有完成、相机未更新。脚本当时虽输出“五图/0fail”，实际日志有 SCRIPT ERROR、截图纯背景。原三份日志和不带 suffix 的截图目录保留为失败证据。后续只修预览的 typed assign 与实际可见性检查，未修改已测原生 baseline、重定向曲线或正式移动。

修后 GPU 工具必须观察两份 actual pose / metadata、可见 kid、head/hips/feet 在相机前且投影进入 viewport、非纯背景以及各 Avatar ROI 中真实橙/青像素，否则 exit 1。Root 已在 Windows / D3D12 Forward Mobile / RTX 5090 重跑 first_start、running_left_90、first_left_180：每组 5 图、57 项检查、0 失败，三组 log/stdout 干净。新目录均带 `-corrected`，首轮失败历史未覆盖。已视查 first_start / running_left_90 中点，原衣服、两份下身模式及枪械可见。

修后证据位于 `shots/motorica-Run_Turns_StartStop_L_variation_1-first_start-corrected/`、`shots/motorica-Run_Turns_L_variation_1-running_left_90-corrected/`、`shots/motorica-Run_Turns_180-first_left_180-corrected/`，各含五图及 `captures.json`。这仅证明独立采样 pose 被实际渲染，不能覆盖未过的脚滑/连续性质量。画面标签某一帧的 slide=0 也可能表示该帧没有推断接触候选，不等同于完整窗口零脚滑。当前无连续动画视频、真实输入 entry/exit 或 Mac 候选验收。

## 复现

离线导出只在当前 Windows 工作区使用，读取原素材并写隔离副本与实验目录：

```powershell
& 'C:/Users/aresr/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' './tools/motorica_retarget.py'
```

仅 Root 运行引擎，先 fresh import。默认一武器完整三段、两模式（6654 个 60Hz 样本），避免一次七武器超过 watchdog；换 family 可重复执行。基线质量不合格时 exit 1 是预期结果，仍要扫描日志中的真实 parser/runtime/shader 错误。

```powershell
./tools/run_godot.ps1 -GodotArgs @('--headless','--editor','--path','H:/GDP/inkwave/splatink','--import')
./tools/run_godot.ps1 -GodotArgs @('--headless','--path','H:/GDP/inkwave/splatink','--script','res://tools/motorica_verify.gd','--','--motorica-family=shooter')
./tools/run_godot.ps1 -GodotArgs @('--headless','--path','H:/GDP/inkwave/splatink','--script','res://tools/motorica_verify.gd','--','--motorica-family=shooter','--native-locomotion-mm')
```

报告为 `shots/motorica-contract-shooter-portable.json` / `-native.json`。native ON 必须观察真实 provider、新 query count 和现有 234 pose family bucket，否则检查失败。这证明原生源保持动作确实工作，**不证明 Motorica 已加入 native candidate DB**。

可独立查看完整原片段或原时间窗口：

```powershell
./tools/run_godot.ps1 -GodotArgs @('--path','H:/GDP/inkwave/splatink','res://scenes/experiments/motorica_locomotion_preview.tscn','--','--motorica-clip=Run_Turns_L_variation_1','--motorica-window=running_left_90')
./tools/run_godot.ps1 -GodotArgs @('--path','H:/GDP/inkwave/splatink','--script','res://tools/motorica_verify_visual.gd','--','--motorica-clip=Run_Turns_StartStop_L_variation_1','--motorica-window=first_stop','--native-locomotion-mm','--motorica-capture-label=corrected')
```

GPU 工具只抓五个原时间 pose，结果写 `shots/motorica-<clip>-<window>-<capture-label>/`；这是独立 pose 预览，不是真实输入或连续帧间插值录像。完整预览到片段末尾停住，Space 暂停，R 手动重新开始。

GDScript 调用为 `configure(avatar._skeleton)`、`capture_authority()`、`apply(id, time, mode, true)`、`restore_authority(packets)`。若另建 Godot .NET 客户端，可使用同一实现，保持数学和 mask 完全一致；以下只是桥接调用，当前项目没有执行 C# 构建：

```csharp
Script source = GD.Load<Script>("res://scripts/animation/experiments/motorica_locomotion_prototype.gd");
GodotObject prototype = source.Call("new").AsGodotObject();
bool configured = prototype.Call("configure", skeleton).AsBool();
Variant authority = prototype.Call("capture_authority");
prototype.Call("apply", "motorica_Run_Turns_L_variation_1", 6.5, "source_path_pelvis9", true);
// Inspect rendered experimental pose here. Restore before the next source tick.
prototype.Call("restore_authority", authority);
prototype.Call("dispose");
prototype.Dispose();
```

## 下一阶段的候选库条件

先修正或明确拒绝未过的接触与尖锐原片段，保留原作者路径用于轨迹特征和测量。若要扩库，应把通过的原时间窗口按各武器 source upper hold 烘成目标 lower pose 与可查询 trajectory，记录缩放速度和原秒数，再验证连续 source cycle→entry→authored clip→exit，以及原控制器实际加减速、180°快速反向、ground/air/squid/climb 和网络回放。当前没有实施该扩库，也没有承诺把 2 秒作者动作强压成快速控制器转身后仍无脚滑。
