# Mixamo 四转向重定向小样

2026-10-04。独立实验，默认关闭，尚未替换 Native MM 数据库或游戏控制器。原 ZIP、参考项目、`body.glb`、Avatar、Native MM DLL 和生产动画均未修改。

## 目标与动作边界

保留四个 standing turn 的原始时间和实际朝向曲线，验证能否作为原 87 骨角色的低速转向补充。它们不是 authored Start、Stop 或跑动 Pivot。

| 原文件 | 原时长 s | 实测 Hips 净 yaw |
|---|---:|---:|
| left turn.fbx | 1.633333 | +176.144493° |
| right turn.fbx | 1.633333 | −175.070577° |
| left turn 90.fbx | 0.933333 | +90.000085° |
| right turn 90.fbx | 0.933333 | −102.641280° |

当前控制器 [ink_actor.gd](../scripts/game/ink_actor.gd#L708) 用临界阻尼朝向弹簧，kid 默认 `omega=20`、最大速度 `12.5 rad/s`、最大加速度 `170 rad/s²`；射击瞄准更快。这与 0.933/1.633 秒的作者转身并不等时。把动作硬加速到当前输入朝向可能改变脚触地和观感，本小样没有进行这种 time warp。不能因预览脚接触良好就宣称已适配真实瞬间输入反转。

## 可复现转换与独立对照

输入 ZIP SHA-256：`e838c2f95645d2202b88ae972adb9560aefae0bfcb13e2082a4e37b4b70aac86`，1,023,751 bytes。四个源文件只提取到 Splatink `.tools/mixamo-turn-prototype/source/`；原包大小、SHA、mtime 均保持不变。

源骨架 65 骨、厘米单位、+Y 上/+Z 前；目标原 `body.glb` 87 骨，SHA-256 `ca43f303d96cd17990f91fbbf48378132ee4dca39e3f38df4b61ce9d19dc7ce3`。目标九个 skin 共享相同 87 joints。不同腿段的缩放比例约为大腿 .687、小腿 .669、足段 .625；不使用统一身高比例复制 local quaternion/translation。

[mixamo_retarget.py](../tools/mixamo_retarget.py) 解析 FBX `PreRotation × LclRotation × inverse(PostRotation)`，在原 30 Hz 关键帧时刻恢复全局变换。转换使用源全局 rest-basis delta 和目标 rest basis，再按目标父链重建局部旋转；保留目标静态骨长、八个腿骨的局部平移和 unit scale。原 Hips 曲线单独存档，移除净 XZ 漂移基线并保留缩放后的非线性骨盆摆动；yaw 单独储存，姿势里只去除一次。任何 Animation 资源都没有场景 root 的 position/rotation track。

[mixamo_blender_check.py](../tools/mixamo_blender_check.py) 用 Blender 5.2.0 LTS、`--background --factory-startup`、FBX 原轴/PrePostRotation，独立导入并采样 65 × (50+50+29+29) = **10,270 骨帧**。未打开/保存用户 `.blend`，未运行 Godot。

对照最大位置误差 4.479e-6 m、最大全局旋转误差 0.000432328°；rest 基准最大位置误差 2.971e-7 m、旋转误差 0.000410791°。原始逐骨数据、Blender 参数/工具 SHA 和对照结果见 `.tools/mixamo-turn-prototype/blender/`，tracked 摘要为 [provenance.json](../assets/animation/experiments/mixamo/provenance.json)。这证明源采样/rest 变换一致，不等于目标脚滑或玩法已经验收。

## 三种可视模式

预览场景为 [mixamo_turn_preview.tscn](../scenes/experiments/mixamo_turn_preview.tscn)，四列对应四片段，三行依次如下。自动播放按原始秒数推进，片段结束后暂停再重置；空格暂停。独立预览 root 可以按源 yaw 转动，但 `apply()` 不改变该 root，更不改变游戏物理 root。

1. `source_baseline`：九骨 rest-basis 基线，保留骨盆摆动；此模式没有足底后处理。目标尺寸导致推断接触区间内足底滑移最高 19.71 cm，明确不合格，保留用于对照。
2. `source_yaw_pelvis9`：原 yaw 预览、九骨骨盆摆动，加离线推断接触修正。`spine`、`hemF`、`hemB` 三个边界骨作全局补偿，保持原上身/衣服/手部的 **global pose**；这会改变边界的 **local pose**，不能称纯九骨覆盖。骨盆最大额外下沉约 7.19 mm。
3. `fixed_authority_leg8`：去 yaw、hips 保持现有 source hold 原值；只写八腿骨，全部上身 local/global pose 保持。离线八骨样本基于 rest hips，运行小样可将同一约束对实际原上身的 animated hips 做独立 IK 修正。此模式丢失作者骨盆摆动，可能降低自然度；仍需播放判断。

足底约束是 **synthesized 后处理**。接触标签来自源 toe 和目标 heel/ball 的低高度/低速度候选，门限 3 cm / .25 m/s，三帧(.1s)平滑取得/释放；没有伪造 authored contact 标签。测量使用原 Character 的 ankle=.085、heel=.065、ball=.11 两点代理，不是完整鞋底蒙皮顶点。本小样没有自动为 Mixamo 添 Start/Stop/pivot 片段。

在线八骨修正保存 raw up/low/foot global basis；用最短 swing 改变肢段方向并保留原轴向 twist。膝方向从 raw knee 对 **raw ankle** 的 signed plane 得到，再随 endpoint swing 搬运到新目标方向。把 raw knee 直接投影到新的约束 ankle 轴，会在原膝没有换侧时错误地换侧，首轮到第三轮验证确实发现此问题。此修正没有对错误旋转做时间滤波，也没有放宽脚触地/连续性门限。

### 离线量化结果

下面是 30 Hz 离线 FK 的完整约束样本结果；Godot 实际 animated hips、资源导入、渲染插值和武器保持另由运行契约测量。不能把此表当运行验收。

| 动作 | 基线最大候选滑移 m | 九骨完整接触误差 m | 八骨完整接触误差 m | 八骨最大 reach clamp m |
|---|---:|---:|---:|---:|
| 左近180° | .074146 | <1.2e-10 | .017398 | .017398 |
| 右近180° | .197121 | <1e-10 | <1.1e-10 | 0 |
| 左90° | .050613 | <1e-10 | <9e-11 | .005900 |
| 右约103° | .080999 | <1.3e-10 | .007130 | .007130 |

九骨完整约束样本分别 36/29/18/16 个；八骨分别 11/17/7/7 个。离线八骨不移动 hips 来掩盖 reach clamp。全部原始关键帧和派生结果在 [turns.json](../assets/animation/experiments/mixamo/turns.json)，baseline/九骨/八骨各四个独立 Animation `.tres`。

## 播放结构与接口

选择 **AnimationPlayer**：四个固定非循环单次动作，手动采样原时间。当前生产 AnimationTree 和 MM 保持原样。实验后处理与游戏状态机/物理完全分开。

```text
MixamoTurnPreview
├── AuthorYawPreviewRoot 或 FixedAuthorityVisualRoot
│   └── 原 InkAvatar / 原 87 骨 Skeleton3D
│       └── 同父节点 MixamoExperimentalOneShots (AnimationPlayer, manual)
└── Camera3D / 灯光 / 代理平地
```

[mixamo_turn_prototype.gd](../scripts/animation/experiments/mixamo_turn_prototype.gd) 的接口：

```gdscript
var experiment = MixamoTurnPrototype.new()
experiment.configure(avatar._skeleton)
avatar.animate(dt, original_state) # 原上身、瞄准、MM/IK 先正常运行
# 在 apply 前保存原87骨 raw position/rotation/scale。
experiment.apply("mixamo_left_turn", source_seconds,
    "fixed_authority_leg8", true, true)
# 下一次 source animate 前精确恢复原87骨包，不将实验姿势回灌。
experiment.dispose()
```

同一接口可由 C# 调用 GDScript 实例，不需在当前 GDScript 游戏安装 Mono：

```csharp
var script = GD.Load<GDScript>("res://scripts/animation/experiments/mixamo_turn_prototype.gd");
GodotObject trial = script.New().AsGodotObject();
trial.Call("configure", skeleton);
trial.Call("apply", "mixamo_left_turn", sourceSeconds,
    "fixed_authority_leg8", true, true);
trial.Call("dispose");
```

Godot 4.7 的 3D Animation 资源采用 packed `[time, transition, x,y,z,(w)]` key 格式；生成器与 [官方 Animation::_set 源码](https://github.com/godotengine/godot/blob/4.7-stable/scene/resources/animation.cpp) 对齐。

## 复现与验收状态

```powershell
# 离线转换，不调用 Godot
& 'C:/Users/aresr/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' tools/mixamo_retarget.py
# 独立 Blender 对照，无用户场景输入
& 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe' --background --factory-startup --python-exit-code 1 --python tools/mixamo_blender_check.py -- --compare-raw .tools/mixamo-turn-prototype/raw_source.json --rest-sampler tools/mixamo_retarget.py
# 以下仅由 Root 串行执行；先进行 fresh import
./tools/run_godot.ps1 -GodotArgs @('--headless','--path','H:/GDP/inkwave/splatink','--script','res://tools/verify_mixamo_turns.gd')
./tools/run_godot.ps1 -GodotArgs @('--headless','--path','H:/GDP/inkwave/splatink','--script','res://tools/verify_mixamo_turns.gd','--','--native-locomotion-mm')
./tools/run_godot.ps1 -GodotArgs @('--path','H:/GDP/inkwave/splatink','--script','res://tools/verify_mixamo_visual.gd','--rendering-method','mobile')
# 三模式近景；frame20-38覆盖原失败位置，按60Hz原时间采样
./tools/run_godot.ps1 -GodotArgs @('--path','H:/GDP/inkwave/splatink','--script','res://tools/verify_mixamo_turn_detail.gd','--rendering-method','mobile','--','--detail-turn=left_turn_90','--detail-start-frame=20','--detail-end-frame=38')
# 完整已捕获序列编码，FFmpeg不插帧/回圈/变速
./tools/mixamo_make_preview_video.ps1 -Clip left_turn_90
./tools/mixamo_make_preview_video.ps1 -Clip right_turn
```

运行契约覆盖 7 武器 × 4 片段 × 两个派生模式、原87骨/原bytes、精确mask/骨长、world root 与 MM/IK clock 不变、武器 muzzle 与上身 global pose、八骨上身 local pose、60 Hz连续性(<.35 rad)以及实际 FK完整接触(<.03m)。输入时序差距与 source hold 的起始姿势跳变量单独记录，不通过放宽门限隐藏。它还输出五个姿势截图和 `shots/mixamo-turn-contract.json`。

### Root 实际引擎结果

所有 Godot 导入/运行由 Root 串行执行，本动画 agent 未启动 Godot。前三轮失败证据保留，没有覆盖成“通过”：

| 版本 | 实际 checks / failures | 发现 |
|---|---:|---|
| initial | 605325 / 1552 | fixture没有在下一source tick前恢复原87骨包；源9上身补偿反馈累积；八骨IK跳变 |
| isolated | 985341 / 28 | exact raw restore后上身通过；只剩28个八骨旋转不连续，最差2.883371rad |
| shortest swing | 985341 / 28 | 去掉额外轴向twist，最差约1.244rad；仍有膝方向投影换侧 |
| signed raw-plane OFF | **985341 / 0** | 门限不变，八骨最差 .304480rad |
| signed raw-plane native ON | **985355 / 0** | 七武器真实provider/query/234pose bucket另加14断言；门限不变 |

最终 ON 证据为 [mixamo-turn-contract-native.json](../shots/mixamo-turn-contract-native.json)、`pc-mixamo-turn-native.log/.stdout`；OFF 证据为 `mixamo-turn-contract-plane.json`、`pc-mixamo-turn-plane.log/.stdout`。Root 扫描这四份最终日志/标准输出，没有 shader/runtime ERROR、WARNING 或 Unicode 诊断。

1834 个实际 FK完整接触样本：源9最大误差 **.001017322m**，fixed8最大 **1.922e-7m**，均低于原 `.03m`；60Hz片段内部最大旋转变化分别 **.207603rad / .304480rad**，均低于原 `.35rad`。上身全局位置最大误差 **4.790e-7m**、basis最大 **4.298e-7**，低于原 `2e-6`；枪口位置误差 **0**。原87骨raw恢复、世界root与原MM/IK时钟均通过。

单独直采 offline 八骨、**不对当前 animated hips refine** 时，60Hz旋转最大 .301119rad，但完整接触误差达到 **.115338m**。因此“离线rest hips接触通过”不能代替实际上身 parent 条件下的实测；当前线上后处理只在这个独立实验中使用。

ON 实际 provider 全部为 `native MMAnimationLibrary exact contiguous search`，每个 bucket 234 poses。报告累计 query_count 为 shooter156、roller312、charger468、blaster624、dualies780、slosher936、splatling1092；计数器随weapon reconfigure保留，每族此次实际新增 **156** 查询，合计 **1092**。四个新 turn 仍由实验 AnimationPlayer 覆盖下肢，**没有加入原生搜索数据库**；ON 证明原native provider继续运行和权威时序保留，不证明新turn已由原生查询选择。

仍有明确未验收项：Source hold→片段首帧没有惯性过渡，ON的首帧姿势差最高源9 **.650474rad**、fixed8 **1.646606rad**；这些值只记录，没有作为已过渡/滑顺结论。原source-yaw预览与快速物理输入的时序不匹配。通过 `.35rad` 内段门限也不能单独证明优雅观感。基线最高约4–20cm的候选滑移与后处理结果是相同实验条件下比较，不能推及实战瞬间反向移动。

GPU已完成五张总览、左90°原失败位置frame20–38诊断19张、左90°完整frame0–56(57张)、右近180°完整frame0–98(99张)。Root扫描D3D12两条完整近景的log/stdout干净，旧膝翻转位置的衣服、腿、鞋完整可见。这仍是独立姿势预览，不是实际输入/控制器/帧间呈现插值的录像。

完整原时间60Hz对照视频：[左90° preview.mp4](../shots/mixamo-detail-left_turn_90/preview.mp4)、[右近180° preview.mp4](../shots/mixamo-detail-right_turn/preview.mp4)。FFprobe实测两路1440×900、60/1fps、56/.933333s与98/1.633333s；没有loop、timewarp或生成插值帧。源PNG包含`t=duration`终点边界，为不多保持1/60s，视频编码到最后时间区间，终点PNG仍供复查。每路`sequence.json`/`video_record.json`记录原时间、模式、SHA、编码器；`mixamo_make_preview_video.ps1`可重现。

### Mac 同一冻结候选的 headless 验证

Root 在独立 `/Users/ryanliu/splatink-build/20261004-mixamo-turns` 复制既有 stage，排除 `.godot` 与 `*.import`，再叠加同一 PC 候选 delta；没有修改动作曲线。冻结包为 `.tools/mixamo-turn-prototype/pc-candidate.tar.gz`，249655 bytes、23 文件，SHA-256 `025f4406fedd911bbe563f9f39b79b496bc962b2b3c2ec8d9eb2816c70a80702`。Root 使用 [run_macos_mixamo_contracts.sh](../tools/run_macos_mixamo_contracts.sh) 串行执行两次 fresh import，然后分别运行 portable 和 native ON 契约；本 agent 未运行远程引擎。

| Mac headless 模式 | checks / failures | 实际 FK 接触样本 | fixed8 最大帧间旋转 |
|---|---:|---:|---:|
| portable | **985341 / 0** | 1834 | .304479986 rad |
| native ON | **985355 / 0** | 1834 | .304479986 rad |

Mac native ON 的源9/八骨最大完整接触误差分别为 `.001017322m / 1.922e-7m`；上身 global position 最大误差 `4.78986e-7m`、basis `4.29815e-7`、枪口 `0`。七武器全部实际运行 `native MMAnimationLibrary exact contiguous search`，每族 bucket=234；累计 query_count 与 Windows 一致：shooter156、roller312、charger468、blaster624、dualies780、slosher936、splatling1092，即每族新增156次、总计1092次。原 `.35rad / .03m / 2e-6` 门限均保持。

证据：[Mac portable JSON](../shots/mac-mixamo/mac-mixamo-turn-portable.json)、[Mac native ON JSON](../shots/mac-mixamo/mac-mixamo-turn-native.json)，以及同目录两次 import、两次契约的八份 log/stdout。Root 回收后再次扫描；本 agent 对本地副本复核，没有 ERROR、WARNING 或 Unicode 诊断。全部文件 SHA 写入 [provenance.json](../assets/animation/experiments/mixamo/provenance.json)。此次只在已冻结候选之外补记验收元数据，tar 及其成员清单保持原样。

随后 Root 用独立 `run_macos_mixamo_visual.sh` 在同一冻结 Mac stage 运行 native ON 总览：**5 captures / 0 failures**，Metal 4.0、Forward Mobile、Apple M2 Max。取回的 [050 总览](../shots/mac-mixamo/mixamo-turn-050.png) 中衣服、腿和武器可见；`mac-mixamo-visual-native.log/.stdout` 均无 ERROR、WARNING 或 Unicode 诊断。总览角色尺寸较小且存在标签遮挡，只作姿势与材质静态核查，不用它替代近景连续观感检查。

**Mac 已验证 headless 骨架、约束、实际 native query，以及五张静态 GPU 总览；没有 Mac 连续视频、真实游戏输入或新包导出。** 初始 contracts helper 的可选 GPU 开关保持 `off`，GPU 总览由 Root 后续单独运行；上方完整近景序列与 MP4 仍只有 Windows 版本。Source hold entry 和真实快速转向的未验收限制继续适用。

**`accepted_for_production=false` 保持：没有默认接入数据库、控制器或网络，不声称真实跑动/急停/联网转向已经通过。**

本小样的12个派生 `.tres` 是四个 standing turn × 三种模式，并非包内12个原动作或六个移动循环。六循环另有 [mixamo-loop-feasibility.md](mixamo-loop-feasibility.md) 的只读速度/接触评估，目前尚未重定向入库。已有真实游戏 Native MM 的鼠标急转对照见 [locomotion-real-chain.md](locomotion-real-chain.md)，选帧判据实验见 [mm-discriminative-hysteresis.md](mm-discriminative-hysteresis.md)；这些对照使用原动作库，不证明本小样的转向已在实战被选择。
