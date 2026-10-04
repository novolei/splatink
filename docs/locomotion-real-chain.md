# 实际游戏移动记录

新增 [coherent 显示位置与下半身协调实验](coherent-locomotion-presentation.md)：10路真实输入对照、逐物理帧只读观察、Windows/macOS 恢复及传送/开关检查。实验仍关闭；完整接触误差略降，但起步膝盖跳变增大，详细证据及未覆盖项见该报告。

2026-10-04，Windows Godot 4.7.1 / a13da4feb，D3D12 Mobile，RTX 5090，1280×720。该记录用于评估已有 Native MM 和 lower 呈现，尚未将 Mixamo/Motorica 候选接入正式游戏。

## 使用的实际链

`scenes/main.tscn → InkGame._local_command → InkPlayerController → InkActor.tick → source_physics → _face/_animate → 原87骨Avatar/Native MM/FootPlant → Avatar._process → frame_post_draw`。

[verify_locomotion_real_chain.gd](../tools/verify_locomotion_real_chain.gd) 延后加载真实 main 场景，将其设为 current_scene，经实际 start_match 进入 playing。保留八个生产 Actor；其余七个使用只用于诊断的 idle bot 命令，局部角色仍通过 `Input.parse_input_event` 的真实 W/A/S/D、鼠标左键、Space、Shift 操作。不直接调用移动处理器，不设角色位置，不注入骨骼姿势。玩家输入包含起步、急停、左右反转、对角反转、边走边射击、落地和 kid/squid 切换。

每个实际 render frame 记录物理帧号、插值fraction、Actor/Avatar root、八腿骨quat、hips屏幕位置、相机/aim_camera、aim_point、枪口、FK脚世界位置和原FootPlant的完整权重接触误差。记录结束释放真实场景。非持久模式不改玩家数据，不发网络请求。

## 初轮截图污染及修正

初次 `pc-locomotion-real-144-off.json` 在同一测量中同步读取五张PNG。GPU读取使下一渲染前积累八个物理tick，造成最高0.8m root步长、1.124rad腿部变化。这不是无截图时的实际帧间运动，不能用它宣称现有MM连续性失败。

已将截图改为显式 `--loco-capture`，正常测量关闭；初轮JSON/日志保留。以下数据均来自无同步截图的同一输入序列。截图文件仅供观察真实画面，不能替代无截图的时序记录。

## 实跑数据

| 输入条件 | 实际render样本 | 本地真实native查询 | grounded locomotion 最大相邻render腿变化 | 完整接触FK最大误差 |
|---|---:|---:|---:|---:|
| 144 Hz cap / OFF | 1843 | 257 | .334004rad | .0108225m |
| 144 Hz cap / lower | 1843 | 257 | .297164rad | .0108225m |
| 30 Hz cap / OFF | 384 | 257 | .637263rad | .0120152m |
| 30 Hz cap / lower | 384 | 257 | .661376rad | .0120152m |
| 144 Hz cap / lower / time_scale=6 | 309 | 188 | 1.062558rad | .0003369m |

144Hz两路均观察原生 `native MMAnimationLibrary exact contiguous search`、234姿势bucket、32次选择过渡。完整接触分别302/303样本。它们的实测wall render速率约144.12/144.11FPS，是低画质、quiet bots、固定cap条件下的记录，不能外推为八个活跃AI战斗的性能。

30Hz每次渲染通常跨两个物理tick，不能套用60Hz单tick的`.35rad`门限。lower在此条件下未降低最大变化，故不能推广为所有刷新率均改善。六倍时间压力使用每个物理tick约`.1s`的游戏dt，记录了更大的步长；它只用于观察异常数值和切换行为，不代表正常速率的优雅移动已通过。

144Hz OFF有1059个grounded移动render，其中618个与上一render是同一物理tick；lower对应1057/616。两者Avatar root仍按60Hz移动。只插值摆动腿没有解决整体世界位置的阶梯更新；不能据此宣布整体locomotion完成。简单打开root插值又会带动支撑脚和瞄准相机，因此后续须同时验证世界触地和权威aim链。

两路相同的`.0108225m`接触误差来自真实FK与原完整权重anchor，不是FootPlant遥测值代替FK。30Hz误差约1.2cm。骨骼局部旋转阈值通过不等于自然观感通过，形态和空中动作另行保留在逐帧数据中。

## 工具和边界

[analyze_locomotion_real_chain.py](../tools/analyze_locomotion_real_chain.py) 校验逐帧观测值finite、按phase统计腿部变化、物理tick数量、root重复帧和接触误差，并可计算hips局部二次拟合的屏幕残差。该残差包含作者步态、相机运动和透视，不能单独归因于插值或CPU。

```powershell
./tools/run_godot.ps1 -GodotArgs @('--path','H:/GDP/inkwave/splatink','--script','res://tools/verify_locomotion_real_chain.gd','--rendering-method','mobile','--','--native-locomotion-mm','--nonpersistent','--benchmark-background','--benchmark-fps=144','--loco-fps=144','--loco-output=res://shots/pc-locomotion-real-144-off-nocapture')
# lower增加 --presentation-interpolation=lower；低帧率同时将两个fps参数设30。
# 压力运行增加 --loco-scale=6；截图独立运行增加 --loco-capture。
```

原始报告在`shots/pc-locomotion-real-{144-off-nocapture,144-lower,30-off,30-lower,144-lower-scale6}.json`，每路对应`.log/.log.stdout`。汇总为`shots/pc-locomotion-real-summary.json`。这是实际开发场景的诊断，尚无此次导出包/Mac同输入序列验收，也没有接受任何新作者候选进入正式动作库。

## 实际鼠标急转与选帧判据对照

同日增加 `--loco-extended-turns`，在上述真实输入序列后追加边射击侧移、鼠标 +90°、反向侧移、鼠标 −180°、后退、停步时鼠标 +90°和释放输入。三次鼠标移动均经 `Input.parse_input_event` 到达实际捕获鼠标的游戏控制器，并检查 look yaw 响应；没有直接设置朝向或骨骼。序列延长到18秒，仅在非持久诊断中使用 sensitivity=1。

以下四路均启用 Native MM 和 `--presentation-interpolation=lower`、关闭同步截图，沿用低画质和七个 idle bots。表中 ON/OFF 只指默认关闭的 `--mm-discriminative-hysteresis` 选帧判据实验，设计和独立查询验证见 [mm-discriminative-hysteresis.md](mm-discriminative-hysteresis.md)。

| cap / 判据实验 | render样本 | native查询 | 整段选择过渡 | 判据差异 / 反事实过渡差异 | grounded最大相邻render腿变化 rad | 完整接触FK最大误差 m |
|---|---:|---:|---:|---:|---:|---:|
| 144 / OFF | 2591 | 341 | 43 | 0 / 0 | .347807527 | .0108224945 |
| 144 / ON | 2569 | 341 | 43 | 7 / 1 | .347807527 | .0108224945 |
| 30 / OFF | 540 | 341 | 42 | 0 / 0 | .693752289 | .0108051989 |
| 30 / ON | 540 | 341 | 42 | 8 / 1 | .775838017 | .0120152039 |

“反事实过渡差异”是在同一次 ON 查询状态下，对原判据和新判据分别结合相同 cooldown、phase gap、intent bypass 得出的切换决定进行比较；它不是两段独立运行的过渡总数相减。开启实验后两种刷新率各有一次不同决定，即使整段过渡数恰好相同。OFF 未计算新判据，因此其差异计数为零不能作为两个判据等价的证据。

每路 **16 checks / 0 failures**，四路的 `.log` 与 `.log.stdout` 均无 runtime/shader ERROR、WARNING 或 Unicode 诊断；逐帧观测数值 finite。144 cap 的最大腿变化没有降低，30 cap 则由 `.693752289` 增至 `.775838017rad`，该次记录不支持“开启后更丝滑”。各路输入落点和 render 相位仍可能略有不同，不能把单次最大值变化全部归因于新判据。实验继续默认 OFF；需要进一步处理素材覆盖、过渡和世界触地，而不是据此接受正式观感。

四路证据为 `shots/pc-hysteresis-real-{144,30}-extended-{off,on}-v2.json` 及各自 `.log/.log.stdout`，汇总 [pc-hysteresis-real-summary-v2.json](../shots/pc-hysteresis-real-summary-v2.json) 同时保留普通序列及六倍时间压力记录。它们仍是 Windows 开发场景诊断，`accepted_for_production=false`；没有此次导出包或 Mac 同输入序列验收，也未将新的 Mixamo 动作接入真实 MM 库。六个循环素材的速度与接触评估见 [mixamo-loop-feasibility.md](mixamo-loop-feasibility.md)。
