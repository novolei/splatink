# Locomotion Pack 静态评估

评估日期：2026-10-04。输入为用户指定的 `E:\backup\Locomotion Pack.zip`。本次只读原包，直接解析 ZIP 中的 FBX；未启动本地或 Mac Godot，未修改生产角色、动画库、控制器或 Native MM。

## 结论

这个包最有价值的补充是 **4 个有实际朝向变化的转向片段**。包内另有 6 个移动周期、1 个待机和 1 个跳跃。它没有 authored Start、Stop、跑动 Pivot、斜向移动或后退片段，不能补齐现有 42 个循环动作缺少的全部过渡覆盖。

这 4 个转向适合作为 87 骨角色的 lower MM 重定向候选；是否改善观感，仍需重定向后按真实输入轨迹播放验证。静态数据不能证明动作接入后的脚滑、姿势连续性或武器保持已经合格。

## 输入与可复查证据

- ZIP 大小：1,023,751 bytes；12 个文件；解压后总大小：5,061,036 bytes。
- ZIP SHA-256：`e838c2f95645d2202b88ae972adb9560aefae0bfcb13e2082a4e37b4b70aac86`。
- 包内全部为 FBX，无 glTF/GLB、网格、贴图或额外 README。
- 静态解析脚本：`.tools/mixamo-locomotion-audit/audit_pack.py`。
- 原包清单、逐文件 SHA、骨架、曲线、位移及接触候选数据：`.tools/mixamo-locomotion-audit/pack-audit.json`。
- 目标原角色静态骨架数据：`.tools/mixamo-locomotion-audit/target-rig-audit.json`。
- 脚本直接读取 ZIP，拒绝绝对路径、`..`、盘符等不安全 member 名；没有解包。审计目录已验证在 Splatink workspace 内且无 reparse point。
- 原 ZIP 读取前后大小及修改时间一致。

解析方法是 Python 二进制 FBX 7700 节点/曲线解析、FBX 时间 ticks 换算和骨架 FK。FK 包括 `PreRotation × LclRotation × inverse(PostRotation)`、父子变换与缩放；原包没有非零旋转/缩放 pivot 或 offset。曲线本身为均匀 30 Hz；表中的帧数包含末尾关键帧，时间来自实际曲线首尾，未以文件名推测。

## 实际动作清单

位移和角度均在**源 FBX 空间**测量。位移已经由厘米换算为米。yaw 是 `Hips` 全局旋转对源 +Z 方向的 XZ 投影并连续展开，不等同于最终游戏角色朝向；尤其右 90° 文件不得硬标为精确 90°。

| 实际文件 | bytes | 帧数 | 时长 s | Hips 净 X/Z 位移 m | Hips 净 yaw ° | 静态分类 |
|---|---:|---:|---:|---|---:|---|
| `left strafe walking.fbx` | 376,977 | 32 | 1.033333 | +1.700300 / 0 | ≈0 | 侧移走周期 |
| `right strafe walking.fbx` | 376,977 | 32 | 1.033333 | −1.700299 / 0 | ≈0 | 侧移走周期 |
| `left strafe.fbx` | 337,633 | 21 | 0.666667 | +2.863960 / 0 | ≈0 | 快侧移周期 |
| `left turn.fbx` | 443,713 | 50 | 1.633333 | −0.007917 / +0.010350 | +176.144493 | 近 180° 转向候选 |
| `right strafe.fbx` | 337,633 | 21 | 0.666667 | −2.863959 / 0 | ≈0 | 快侧移周期 |
| `right turn.fbx` | 443,713 | 50 | 1.633333 | −0.001317 / +0.009333 | −175.070577 | 近 180° 转向候选 |
| `idle.fbx` | 788,081 | 251 | 8.333333 | 0 / 0 | 0 | 待机周期候选 |
| `jump.fbx` | 507,729 | 66 | 2.166667 | ≈0 / ≈0 | ≈0 | 单次跳跃；不应因首尾相同而循环 |
| `running.fbx` | 339,889 | 22 | 0.700000 | 0 / +2.911620 | ≈0 | 前进跑周期 |
| `walking.fbx` | 376,977 | 32 | 1.033333 | 0 / +1.638657 | ≈0 | 前进走周期 |
| `right turn 90.fbx` | 365,857 | 29 | 0.933333 | +0.001721 / +0.010023 | −102.641280 | 约 90° 类右转候选；以实测曲线处理 |
| `left turn 90.fbx` | 365,857 | 29 | 0.933333 | −0.010090 / −0.001402 | +90.000085 | 90° 左转候选 |

所有文件均为 FBX version 7700，由 `FBX SDK/FBX Plugins version 2020.2` 导出；每个文件只有一个 `mixamo.com` AnimationStack。不能以这个重复的 stack 名直接注册多个动作，应以源文件建立稳定的独立 clip ID。

### 移动周期与 loop

六个移动文件的首尾持续移动，没有静止→加速或减速→静止的 authored 段。源 Hips 平面速度范围如下：前走 1.361–1.874 m/s；前跑 3.946–4.337 m/s；左右侧移走分别 1.460–1.889、1.470–1.834 m/s；左右快侧移分别 3.917–4.834、3.962–4.730 m/s。不能把周期中的任意窗口改名为 Start/Stop 后宣称补齐作者制作的启动/停步。

六个移动周期移除净位移后，首尾足部相对 Hips 的位置差不超过约 0.000001 m；全部骨全局旋转的首尾最大差不超过 0.016561°。这支持它们是周期候选，但 FBX 中没有显式 loop 标志；最终导入仍须按 clip 语义设置并验证 seam。

四个转向首尾朝向不同，应按非循环片段处理；其净 Hips XZ 位移仅约 1 cm，却有 0.252–0.640 m 的累计 XZ 路径，包含身体随换脚移动的轨迹，不能简单丢弃整条平面轨迹。它们没有前跑速度，不应标为跑动 Pivot。

侧移动作 Hips 平均 yaw 分别约 +68.30°/−68.43°（走）及 +76.58°/−77.19°（快）。保留 Hips 的 lower mask 会保留这些骨盆转向；它们是否符合七类武器的朝向保持，需要播放确认，不能只凭 `strafe` 文件名认为是全程朝前的侧步。

## 源骨架及目标重定向

12 个 FBX 的 rest 骨架完全一致；各有 65 个 `mixamorig:*` LimbNode。只有动画和骨节点，没有 `Geometry`、`Deformer` 或 Mesh，因而没有可验证蒙皮外观的源角色。

源根骨就是 `mixamorig:Hips`，没有单独的 motion root。源 +Y 为上、+Z 为前、+X 为侧轴；`UnitScaleFactor=1` 表示厘米，米制换算为 0.01。Hips rest 高度为 0.926612 m；所有骨原点的 Y span 为 1.778863 m。骨原点 span 不是 mesh 包围盒身高。

目标 `body.glb` 的 SHA-256 为 `ca43f303d96cd17990f91fbbf48378132ee4dca39e3f38df4b61ce9d19dc7ce3`。9 个 skin 共享相同顺序的 87 joints，根链 `InkBody → Model → Kid` 为 identity，没有隐藏的 0.01 scale。目标 Hips rest 高度为 0.640000 m，骨原点 Y span 为 1.338527 m；头发骨抬高了该 span，因此不能用整高比统一缩放所有腿部轨迹。

| 源 Mixamo 骨 | 目标原角色骨 | 来源一致性 |
|---|---|---|
| `mixamorig:Hips` | `hips` | 根骨角色不同；需拆分轨迹和 Hips 姿势 |
| `mixamorig:LeftUpLeg` | `thighL` | 下肢拓扑可对应 |
| `mixamorig:LeftLeg` | `shinL` | 下肢拓扑可对应 |
| `mixamorig:LeftFoot` | `footL` | 下肢拓扑可对应 |
| `mixamorig:LeftToeBase` | `toeL` | 目标无对应 Toe_End |
| `mixamorig:RightUpLeg` | `thighR` | 下肢拓扑可对应 |
| `mixamorig:RightLeg` | `shinR` | 下肢拓扑可对应 |
| `mixamorig:RightFoot` | `footR` | 下肢拓扑可对应 |
| `mixamorig:RightToeBase` | `toeR` | 目标无对应 Toe_End |

| 几何量 | 源左 / 右 m | 目标左 / 右 m | 目标/源近似比 |
|---|---|---|---|
| 大腿长度（UpLeg→Leg / thigh→shin） | 0.400838 / 0.401312 | 0.275278 / 0.275278 | 0.687 / 0.686 |
| 小腿长度（Leg→Foot / shin→foot） | 0.393041 / 0.392901 | 0.262939 / 0.262939 | 0.669 / 0.669 |
| 脚段（Foot→ToeBase / foot→toe） | 0.184443 / 0.183802 | 0.115104 / 0.115104 | 0.624 / 0.626 |

目标九骨 rest rotation 全为 identity，源腿/足有较大 PreRotation，例如左大腿约 `(-4.744, 0.736, -171.201)°`、左足约 `(71.233, 2.954, 0)°`。只按名称复制源 local Euler/quaternion，会把源骨轴姿态套在目标骨轴上。必须应用 rest/basis correction，并按目标父链重新求 local rotation；保留目标原骨数、骨长、静态局部平移、原七武器上身与手部动画。

尺寸比例并不统一。需要将厘米单位换算和角色比例修正分开，在目标骨长上重建足部位置/接触；直接把所有源局部 translation 乘一个身高比例，无法保证 toe、foot 与地面保持一致。

## Root 位移和接触

六个移动周期均有累计 Hips 平面位移。直接接入姿势 track 会使视觉角色每周期前移 1.64–2.91 m 或侧移 1.70–2.86 m，再叠加现有物理移动，产生双重位移和重置跳变。

源 Hips 平面位置/朝向需要先作为**数据库轨迹证据**单独保留，再把姿势转换到当前控制器使用的局部参考系。现有物理位置、速度、碰撞、朝向和输入控制仍由控制器负责。禁止把源 Hips 位移或 turn yaw 接管为物理 root motion。转向只有 Hips，没有干净的 actor-root yaw track；需分离作者转身与骨盆残余摆动，避免游戏朝向和 Hips 各自叠加一次旋转。

FBX 没有显式 foot-contact/footstep 标签；静态文件可以计算源骨架足部高度和速度。审计 JSON 提供一个仅供调试的候选推断：以每只脚该 clip 最低 toe 高度为地面候选，`ToeBase` 或 `Toe_End` 低于地面 +0.03 m 且 XZ 速度 ≤0.25 m/s 时，记为接触候选。采样为 30 Hz；候选不是作者标签，也没有确认鞋底接触。

例如源前跑：左脚候选 0.300–0.433 s；右脚 0–0.100 s、0.633–0.700 s。源左 90° 转：左脚候选 0–0.033 s、0.400–0.933 s；右脚 0–0.433 s、0.767–0.933 s。源跳跃存在明显腾空，Hips Y range 约 0.520 m，但这只说明动画；不能替代物理跳跃或生产落地事件。

源 `Toe_End` 没有目标对应骨，而且目标足段比源更短。接触候选须在重定向后的目标 rig 上重新计算，再检查旋转支撑脚时的足部滑动、脚掌穿地和骨盆高度；不能原样复制本审计的源接触窗口作为验收结果。

## 建议顺序与仍缺的数据

1. 先以 `left turn 90.fbx` 和 `right turn 90.fbx` 做小规模 lower 九骨重定向对照；保存实际轨迹与非循环边界。右转标签保留源文件名，角度以实际参考朝向提取，不人为修成 90°。
2. 再验证 `left turn.fbx` / `right turn.fbx` 的近 180°站立转向。它们仅补低速/站立转向候选，不补跑动 Pivot。
3. 六个移动周期只有在需要不同节奏或低速侧移时再评估。原七武器已有六类循环，增加这些无武器周期不等于增加七套 authored 武器动作。
4. `idle.fbx` 和 `jump.fbx` 对本次 Start/Stop/Pivot/斜向缺项没有直接补齐作用；跳跃应放到明确的空中/落地流程单独验证。

仍需另找或制作：静止→走/跑 Start、走/跑→静止 Stop、跑动 90°/180° Pivot、前后左右斜向移动，必要时包括对应起停与左右支撑脚版本。将循环镜像、旋转、裁剪、减速或混合出来的片段可以作为合成候选，但必须标明来源，不能计为新 authored 覆盖。

转向接入前的实际验收应覆盖：原87骨和九骨mask保持、目标骨长/静态平移保持、七武器上身保持、clip结束不绕回、物理控制不变、输入方向与源左右轴转换正确，以及目标足部接触与真实轨迹播放。

2026-10-04 已继续完成独立四转向重定向小样，见 [mixamo-turn-prototype.md](mixamo-turn-prototype.md)。源 65 骨采样与后台 Blender 独立对照通过；原 87 骨角色的七武器 × 四片段 × 两派生模式契约在 portable/native provider 下分别通过 985341/985355 检查，1834 个实际 FK 完整接触样本。最终固定八腿骨候选的内部单帧变化最大 .304480 rad，上身位置误差 <.5 µm，枪口误差为零；左90°和右近180°已捕获完整原60Hz姿势序列，GPU日志和stdout均干净。

这些结果验收独立小样的内部连续性和骨架保持。切入现有 source hold 的姿势差仍未处理（八腿骨最高1.646606 rad），源0.933/1.633秒转身未适配当前快速转向响应；动作未加入原生数据库/真实控制器，`accepted_for_production=false`。保留现有原生MM方案和对照小样，不能据此宣称起停、跑动反转或实战转身已完成打磨。

随后已完成六个移动循环的只读速度/接触评估，见 [mixamo-loop-feasibility.md](mixamo-loop-feasibility.md)。按目标腿长估算，前跑和快侧移的参考速度约2.8–2.9m/s，适配当前6m/s干地 kid 跑速约需2.1倍节奏；循环首尾良好仍不能消除直接替换的脚滑。六循环尚未重定向或加入正式数据库。建议保留现有 Native MM，以这些素材补充动作，再验证目标接触和真实输入；已有选帧判据实验与真实鼠标急转的局限见 [mm-discriminative-hysteresis.md](mm-discriminative-hysteresis.md) 和 [locomotion-real-chain.md](locomotion-real-chain.md)，该实验仍默认关闭。
