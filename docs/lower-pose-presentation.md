# 下半身部分呈现试验

默认关闭。使用 `--native-locomotion-mm --presentation-interpolation=lower` 才会在真实原生 MM 下启用。它只对人形地面 locomotion 的八根腿骨做摆腿插值；当前支撑腿保留物理帧的精确姿势。这不是整个人物的连续插值，也没有加入新的起步、刹停或转身动作。

现有 `AnimationPlayer` 与分层 `AnimationTree` 继续在物理帧计算 MM、惯性化、脚触地、上身瞄准和原游戏动作。`InkPosePresentation` 只读取两个已解算的姿势包，插入显示帧。场景节点不变：

```text
InkActor                    # 物理位置、速度、转向
└── InkAvatar               # 原生 MM / 原游戏 AnimationTree
    ├── InkBody / Skeleton3D (87 bones)
    ├── hair / Skeleton3D
    ├── brows / Skeleton3D
    └── AnimationTree + AnimationPlayer
```

八根骨骼是左右 `thigh/shin/foot/toe`。`hips`、Avatar 根节点、Model、Kid、上身、武器、头发、眉毛、面部参数和材质均保持当前物理帧；相机与枪口查询也保留当前权威位置。跳跃、鱿鱼/游泳/攀爬、超级跳、全身动作或未结束的形态变换会立即恢复并清空显示包，重新进入地面人形时从新包开始。传送和换装也重置包。

支撑腿不写入显示姿势，可避免“旧腿部局部姿势 + 当前移动根节点”产生的脚滑。5.5m/s、60Hz 时根节点每帧移动约9.17cm，简单腿部插值在半帧处可能把已落地的脚拖走约4.58cm。摆腿到支撑腿的切换仍可能暴露物理帧节奏，需用实际渲染验证；本模式不改变原先 `<0.35rad/frame` 和 `<0.03m` 验收限值。

配置只捕获八根腿骨，不捕获模块、场景节点或材质。呈现报告包含 `capture_bones`、`held_bones`、`swing_bones`、`swing_bone_writes`、`held_bone_writes` 和 `node_writes`；支撑腿写次数应为0。还会记录捕获、恢复、呈现的耗时。Godot 仍为整个87骨 Skin 更新矩阵和变形，因此不能按骨骼数量比例推断帧率收益。

Root 串行执行：

```powershell
& $Godot --headless --path H:\GDP\inkwave\splatink --script res://tools/verify_lower_pose_presentation.gd -- --native-locomotion-mm --presentation-interpolation=lower
& $Godot --headless --path H:\GDP\inkwave\splatink --script res://tools/verify_pose_presentation.gd -- --native-locomotion-mm
& $Godot --headless --path H:\GDP\inkwave\splatink --script res://tools/verify_motion_matching.gd -- --native-locomotion-mm
```

独立 lower 契约使用真实原生查询和原控制器加速/刹车/转向轨迹，在120/144/240Hz分数帧检查原始组件恢复、上身全局姿势、枪口、材质、头发/眉毛、MM/IK时钟、七武器/形态/传送和实际呈现脚踝到世界锚点的距离。它同时计数支撑和实际被插值的摆腿样本，避免因为完全没显示插值而误判通过。

GPU144Hz八人基准应分别运行相同配置的 native-MM默认OFF 与 lower-ON，例如：

```powershell
& $Godot --path H:\GDP\inkwave\splatink -- --native-locomotion-mm --autostart=90 --mode=boss --map=tidewater --time=day --benchmark-seed=37 --benchmark-fps=144 --benchmark-background --nonpersistent --profile-render --autopilot --capture=shots/pc-lower-off.png --capture-after=32
& $Godot --path H:\GDP\inkwave\splatink -- --native-locomotion-mm --presentation-interpolation=lower --autostart=90 --mode=boss --map=tidewater --time=day --benchmark-seed=37 --benchmark-fps=144 --benchmark-background --nonpersistent --profile-render --autopilot --capture=shots/pc-lower-on.png --capture-after=32
```

同随机种子不保证不同渲染帧调度下的战斗轨迹完全一致，应比较实际活动人数、支撑/摆腿写次数、动画分段、帧时间和画面，不把差值全部归因于插值。现有 `all`、`local` 和默认OFF行为保持原样。

首次独立真实FK契约已完成450062检查、0失败，呈现支撑脚误差最大0.01068989m，物理/呈现最大角度0.3478149/0.3067257rad，上身全局误差0。采样包含948次严格支撑脚检查、18915次实际改变的摆腿组件；摆腿骨写入19234次，支撑腿插值写入0。捕获/呈现/恢复 median 为7/4/2μs、p95为10/8/3μs，单次呈现最大316μs未删除。见 [原始记录](H:/GDP/inkwave/splatink/shots/pc-lower-presentation-contract.log)。这些是独立契约的脚本耗时，不是八角色GPU帧率，也不代表整个人物已在高刷新率下平滑。

2026-10-04完成当前工作区真实D3D12八角色实战：RTX5090、1280×720/high、4096图集、native-MM开启、seed37、144上限、`autostart=240`、Boss/Tidewater傍晚、32秒进程窗口。OFF/ON各24.85/24.7833秒实战，8个原生查询器，实际平均103.43/111.64 FPS，帧长p95均16.67ms；两份引擎日志和stdout无错误或警告。ON截图时4个角色正处于可插值状态，其他角色因当前形态/动作停用，不能把它称为当时8个角色都在插值。每角色capture/render/restore中位9/7/5µs、p95 15/20/10µs、最大227/194/121µs；支撑腿写次数和节点写次数均0，摆腿每次最多8骨。记录为 `shots/pc-boss-lower-{off,lower}.json/.log/.png`。

该对照证明此入口已在完整战斗里运行，仍未证明整体帧率提升：OFF与ON的角色+AI p95为32.28/7.88ms，战斗路径与活动墨滴不相同，而且逐角色计时只保留前7200样本。保留默认关闭；角色根、上身和支撑腿仍保持60Hz节奏，不能将摆腿插值描述为整个角色的高刷新率平滑。

后续已通过真实 `main.tscn`、真实键鼠事件，在144/30Hz及六倍时间压力下记录实际render帧。144Hz OFF/lower的grounded腿部最大相邻render变化为.334004/.297164rad，完整触地FK误差两路均.0108225m；30Hz最大变化为.637263/.661376rad，说明该入口不在所有刷新率下降低最大角度。每个render通常包含两个物理tick的30Hz记录不能套用60Hz单tick门限。两路144Hz的移动帧约58%仍复用同一root物理姿势，整体位置阶梯问题尚未解决。详见 [实际链记录与截图污染说明](locomotion-real-chain.md)；新增记录不等于此次导出包/Mac连续录像或全局顺滑验收。

GDScript 使用方仍调用 `restore_presentation()`、物理 `animate(dt,state)` 和显示 `present(fraction)`；C# 使用方通过相同 GodotObject API，例如 `avatar.Call("present", Engine.GetPhysicsInterpolationFraction())` 与 `avatar.Get("presentation_mode").AsString()`。呈现不得调用 `AnimationTree.Advance()` 或回写 Actor 物理状态。
