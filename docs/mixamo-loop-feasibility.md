# Mixamo 六个循环动作的移动适配评估

2026-10-04。结论：保留现有 Motion Matching 作为下半身选择器，Mixamo 可提供走、跑、横移动作素材。该包不能按原时间直接替换并满足当前 kid 的 6 m/s 跑速；仍需目标空间的步幅、节奏、接触与过渡适配。本轮没有将六个循环接入正式动作库。

## 来源与可复现证据

读取用户提供的 `E:/backup/Locomotion Pack.zip`，1,023,751 bytes，SHA-256 `e838c2f95645d2202b88ae972adb9560aefae0bfcb13e2082a4e37b4b70aac86`。包内为 12 个 65 骨 FBX：六个移动循环、Idle、Jump、四个站立转向。目标使用原 `assets/characters/body.glb` 的 87 joints，SHA-256 `ca43f303d96cd17990f91fbbf48378132ee4dca39e3f38df4b61ce9d19dc7ce3`。

只读分析脚本为 `.tools/mixamo-loop-analysis/read_only_audit.py`，19377 bytes，SHA-256 `ecec87273d97409dc9aaab538d73f01e0c4a258b257e69adacf9dbe09be62c00`；报告为同目录 `report.json`，62737 bytes，SHA-256 `12921ecc3e7ab4ebc0ed43d127af81d8072a6dfc74fddaa7e7d82e150a39d84b`。报告保存真实文件名、每项来源 SHA、目标段长、接触候选帧、原始 FK、循环端点和诊断限制。脚本只写自己的报告，不提取或修改 ZIP，不运行冻结生成器的 main，不生成动画，不调用引擎。全部读取输入的大小、mtime 和 SHA 在分析前后保持一致。

```powershell
& 'C:/Users/aresr/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' -B 'H:/GDP/inkwave/splatink/.tools/mixamo-loop-analysis/read_only_audit.py'
```

## 实际移动与速度

六个源动作均由 Hips 携带累计平面位移，没有单独 Root。这是 traveling animation，不能把累计 Hips 位移当作局部骨盆摆动叠加到游戏的物理移动上。

目标/源大腿比例左右约 `.686756/.685945`，小腿约 `.668987/.669225`，足段约 `.624064/.626241`；大腿加小腿平均比例 `.677816`。各段比例不同，因此以下是按腿长估算的参考速度，不能当成已验收的目标角色运动速度。

| FBX | 原周期 s | 源 Hips 净行进速度 m/s | 按腿长参考速度 m/s | 达到 6 m/s 的参考播放倍率 |
|---|---:|---:|---:|---:|
| walking.fbx | 1.033333 | 1.585797 | 1.074879 | 5.5820 |
| running.fbx | .700000 | 4.159457 | 2.819347 | 2.1282 |
| left strafe walking.fbx | 1.033333 | 1.645451 | 1.115314 | 5.3797 |
| right strafe walking.fbx | 1.033333 | 1.645451 | 1.115313 | 5.3797 |
| left strafe.fbx | .666667 | 4.295940 | 2.911857 | 2.0605 |
| right strafe.fbx | .666667 | 4.295939 | 2.911857 | 2.0605 |

跑步源 Hips 净前进 `2.911620m`；快侧移约 `±2.863960m`。按上述比例维持步幅，跑周期需约 `.328924s`，快侧移约 `.323540s`。这说明约两倍节奏是需要评估的适配方案，不代表这种节奏已经自然或满足 Splatoon 风格。

现有 matcher 的播放倍率上限是 `1.8`，上述跑/快侧移动作在该上限下的参考速度约为 `5.0748/5.2413m/s`。原库 run 的 `5.5m/s` 与横移的 `4m/s` 是虚拟运动标签；当前游戏实际 dry kid runSpeed 为 `6m/s`。不能通过换标签宣布脚滑已经解决，也不应拿走路动作硬凑跑速。

## 足部与循环端点

使用真实源 FK，在 toe 高度不超过本侧最低值 `3cm`、世界 XZ 速度不超过 `.25m/s` 的候选段，扣掉 Hips 净行进基线后，反向足速中位数约为走 `1.59m/s`、跑 `4.158m/s`、走侧 `1.647m/s`、快侧 `4.30–4.37m/s`，与源实际行进相符。候选是推断接触，源文件没有作者标注的 contact 曲线。

独立的九骨 rest-basis FK 基线保留目标段长及源骨盆摆动，不使用 IK。在以 `6m/s` 移动时，源候选段中较优 heel/ball 的滑速中位数为跑 `3.13–3.20m/s`、快侧移 `3.01–3.12m/s`、走 `4.92–4.93m/s`；在腿长参考速度下约 `.03–.094m/s`。这是速度不匹配的基线证据，**不是实际 Avatar 的脚滑验收**。未校地的 sole 最低 Y 约 `−.008` 至 `−.026m`，还需目标足部校正。

扣掉源真实净行进后，六个循环的下肢 FK 端点位置最大差约 `2.3119e−5m`，全部 65 骨最大差约 `6.5160e−5m`，旋转最大差 `.016561°`。未发现有意义的循环端点跳变。若直接重复原累计 Hips 位移，才会造成平面位移重置或与物理 root 双重移动。

## 现有小样和实施路线

现有 `assets/animation/experiments/mixamo/turns.json` 和 12 个 `.tres` 是**四个站立转向 × 三种模式**，均为非循环资源，不是包内 12 个动作均已转换，也不包含六个移动循环。baseline/source9 的 Hips XZ 首尾为零且保留中间摆动；fixed8 不写 Hips position track。已有转向适配与 PC 验证见 [mixamo-turn-prototype.md](mixamo-turn-prototype.md)。

建议下一步先适配 running 与快侧移：分离源累计平面行进，仅以它作为轨迹证据，保留非线性骨盆摆动；在目标空间比较原节奏、约两倍节奏和经过制作的步幅，测量触地、可达距离、过渡及上半身/枪口保持，再进入真实输入链。持续约 `3m/s` 的速度差不能靠 foot lock 长期掩盖。

后续已制作这三个快移动循环的18个隔离小样，并完成Windows七武器、Mac资源/FK契约和GPU静态显示诊断。重定时减小部分离线脚滑，但18候选仍全部有质量失败，尚未进入正式库，见 [mixamo-loop-candidates.md](mixamo-loop-candidates.md)。这把适配风险落实到实际资源，不改变本评估的“不能直接替换”结论。

包中仍缺后退、对角、作者制作的起步/急停及跑动 pivot。Motorica 参考包含起停和跑动转向，但其当前适配小样仍有质量失败，见 [motorica-locomotion-candidates.md](motorica-locomotion-candidates.md)。两类素材可补充现有选择器，不能代替目标角色制作及真实游戏验证。

原生插件、参考项目、ZIP、原角色、Mini Tanks 客户端与服务端保持未修改。只读循环分析脚本不调用Godot、Blender或SSH；后续实际资源诊断由Root唯一串行执行。Windows/Mac查询及真实游戏输入对照另见 [mm-discriminative-hysteresis.md](mm-discriminative-hysteresis.md)。


后续已制作21个修整对照并完成Windows/Mac资源检查，仍全部有质量失败；见 [修整评估](mixamo-loop-refinement.md)。这不改变本页原候选的冻结结论。
