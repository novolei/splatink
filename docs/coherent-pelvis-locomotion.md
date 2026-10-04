# PC 骨盆与下半身协调实验

2026-10-04。**有改善，仍未接受为正式玩家体验，默认关闭。** 保留用户的 Native Motion Matching、原87关节和正式动作库；Mixamo 的21个修整候选仍未写入正式数据库。本轮继续定位移动动作的跳变，不代表完整复刻、发布包或平台性能验收。

## 当前结论

144 cap 的真实行走/反向/射击输入中，稳定地面腿关节最大相邻变化：关闭插值 `.334004rad`，旧 coherent `.780613rad`，新 coherent-pelvis `.248757rad`。新方案消除了本轮观测到的腿部 reach clamp，脚踝 FK 对呈现目标最大误差约4微米。

但是，新方案为保持当前上半身 rig-space 全局姿势，改变了 Hips 到 spine/hem 的局部位置和连接长度。真实普通144输入最大 spine 缩短 **38.587mm**，约占原105.076mm连接长度的36.7%；契约覆盖范围中最大长度变化 **68.845mm**。骨骼精确恢复、脚目标误差小和没有 reach clamp 均不能证明皮肤变形可接受。

普通30 cap 最大腿变化从 `.637263rad` 增到 `.681112rad`，没有跨帧率一致改善。普通144输入可见枪口到权威射击点最大距离约 **97.619mm**，六倍时间压力下约 **572.857mm**。因此本轮不能默认启用该方案。

## 实现与空间含义

新开关 `--presentation-interpolation=coherent-pelvis`。仅作用于本地、稳定 kid 形态、地面、Native MM 准入状态。显示 root 只插值位置，朝向仍为当前物理朝向；Hips 世界位置及旋转随前后物理包协调插值，再以两骨几何重建世界脚目标。八个腿骨、Hips 和实际三个上半身边界被捕获和恢复，换装模型同步对应分支。

上半身保持的是**当前物理姿势在 Skeleton 的 rig-space 全局变换**，不是世界位置、原始局部骨长或最终蒙皮形状。相机仍取当前权威目标，可见身体 root 存在插值延迟；权威枪口 getter 保持不变，可见枪口另以真实 hand FK 观测。不能将 getter 不变描述成画面枪口没有偏移。

实现：[Avatar](../scripts/characters/ink_avatar.gd)、[新骨盆helper](../scripts/animation/experiments/ink_coherent_pelvis_presentation.gd)。[旧实验](coherent-locomotion-presentation.md)的 helper 和工具保持字节冻结；没有改变物理控制器、相机、正式 matcher/数据库或 Mini Tanks。

首次契约脚误差约 `.2517mm`。方向修正改用显式 shortest-arc quaternion 之后，在同一契约输入下降到 `.9848µm`。本地 godot-cpp 头文件存在近似同向返回 identity 的分支，解释与量级吻合；未核对 Godot 4.7.1 核心的对应实现，结论以实际修正前后测量为准。

## Windows / macOS 契约

[Windows V2](../shots/coherent-pelvis-contract-v2.json)与[Mac V1](../shots/mac-coherent-pelvis-v1/output/coherent-pelvis-contract.json)各 **398949 checks / 0 failures**，1260次呈现、360份模块恢复快照。覆盖全部87关节原始三组件精确恢复、未选关节局部组件、所有非下半身骨骼/模块的 rig-space 全局姿势、MM及FootPlant时钟、物理root/朝向、权威sockets、7武器、形态/空中/远端准入、移动中重生和开关重新准入。

两平台契约均无 reach clamp，脚目标误差最大 `.984830µm`，骨盆位置误差 `.953674µm`。身体/模块上半身位置误差分别小于 `.478µm` / `.364µm`。**这些仅为契约成功。** 世界腿长投影变化仍达 `.053942mm`，1246/1260样本 rig 世界变换非均匀；保留原始局部scale不等于保持完整世界affine旋转/骨长。

Mac 使用192.168.80.177、ARM64 Godot4.7.1、独立stage、engine.lock和两次 fresh import。5文件隔离包35147 bytes，SHA256 `cffe5e8ac0dba89013e6794f159798593562f5dcea781cd6fd1fc7e9a4399324`，见[manifest](../.tools/coherent-pelvis-presentation-macos/20261004-coherent-pelvis-v1.json)。未运行 Mac GPU 实战，也未重新导出任何平台发布包。

## 实际输入对照

Windows Godot4.7.1 / a13da4feb，D3D12 Mobile、RTX5090，1280×720、低画质、VSync OFF。真实main/start_match及W/A/S/D、射击、跳跃、变身；急转增加实际鼠标 +90° / -180° 输入。8个生产Actor，其中7个为诊断idle bots。Native MM两路都启用，匹配判据实验关闭；新Mixamo数据未选用。

以下10路OFF/ON分别指关闭呈现/新骨盆呈现，另有一条旧coherent144对照。全部无同步截图。移动完整接触指脚踝FK至现有anchor，且地面、移动、contact真、weight > .999；不是新脚底接触标签。

| 条件 | render OFF / ON | 最大地面腿变化 rad OFF / ON | 移动完整接触数 OFF / ON | 对应最大接触误差 m OFF / ON |
|---|---:|---:|---:|---:|
| 144普通 | 1843 / 1838 | .334004 / .248757 | 12 / 12 | .010822 / .008427 |
| 30普通 | 384 / 384 | .637263 / .681112 | 5 / 5 | .012015 / .008344 |
| 144六倍时间 | 305 / 306 | 1.243756 / 1.062558 | 0 / 0 | 未覆盖 / 未覆盖 |
| 144鼠标急转 | 2591 / 2588 | .416122 / .248757 | 17 / 16 | .010822 / .009522 |
| 30鼠标急转 | 540 / 540 | .783075 / .765409 | 5 / 6 | .011773 / .011450 |

11路合计 **165结构checks / 0 failures**。普通/急转物理样本分别768/1080；压力129。新ON分别583/895/100个准入物理包，捕获的组件/root均与真实权威物理包精确一致；OFF无可用捕获包，明确未覆盖。有限完整移动接触不能证明长时间脚底无滑动，部分释放的残余anchor误差也不能当作仍应锁定的脚滑。

旧coherent144有1个实测5.266mm reach clamp；新ON本轮观测的腿诊断没有 clamp。原数据及所有分位、相位、接触、枪口和空间误差见[汇总](../shots/pc-coherent-pelvis-real-summary-v2.json)。两次输入运行的时序落点仍可能略有差异，不把最大值的全部差异归因于算法。

## 时间与画面证据的限制

新只读observer在物理game之后及每帧Avatar/game/camera之后记录数据，同时保留frame_post_draw。11路的关联process frame offset及root差均为0，说明这些CPU观察点读到同一个root；**实际Avatar.present调用时刻和GPU/显示器呈现时刻仍未知**。不能据此证明真正显示帧节奏平稳或移动端性能。

工具：[新实际链](../tools/verify_locomotion_pelvis_real_chain.gd)、[新只读observer](../tools/locomotion_pelvis_physics_observer.gd)、[新分析器](../tools/analyze_locomotion_pelvis_real_chain.py)。runtime诊断公开clamp、unsupported、骨盆、上半身边界及模块误差；计数仅覆盖观察到并按helper render id去重的样本。

另有[5次截图的144运行](../shots/pc-coherent-pelvis-real-144-on-v1.json)，14结构checks / 0。同步截图造成最高8个物理tick跨越，所以只作实际场景画面证据，不加入无截图性能/跳变对照。已查看起跑、横移反向、射击三个截图；单张截图不能验证连续动作或最坏局部皮肤变形。

新ON普通144中1375/1394个呈现诊断的骨盆完整世界scale投影不受当前实现支持，30普通287/292；其他路也有此状态。腿solver的unsupported-affine为0是另一项诊断，不能覆盖掉骨盆非均匀世界旋转/scale限制。实际世界脚旋转投影误差最大约 `.008053rad`，未宣称世界affine姿势精确。

## 保留与下一步

[最终审计](../shots/coherent-pelvis-final-audit-v1.json)：36份引擎log/stdout均无错误或警告；61份只读素材/候选输入及5份正式matcher/数据库快照的SHA/size/mtime保持；旧coherent helper、旧工具和旧离线证据字节未改。未部署服务、未改Mini Tanks、未做新发布包。

保留现有MM作为下半身动作选择器，Mixamo继续作为可重定向的动作素材来源。当前优先应查明权威Hips本身的大幅位置变化，并协调身体与相机的显示时序；不再把移动下半身与固定上半身之间的局部平移补偿当作正式解决方案。动作匹配、素材质量、脚部约束和呈现时序分别验收。

独立离线重建进一步指向当前[FootPlant髋部修正](../scripts/animation/ink_foot_plant.gd)：`maxf(drop*0.85,_hip_drop)` 的瞬时项会绕过 `_hip_drop` 的平滑；接触变false时required drop立即归零，释放权重尚有 `.67032`，随后切回衰减状态。144普通ON的tick324→325中，重建的预FootPlant Hips y只升约1.940mm，已录最终物理Hips却下降46.373mm；tick326又回升39.339mm。

这里的 `_hip_drop` 和 required drop **未直接记录**：它们来自原始GLB/当前惯性化公式与已录物理组件的反推，以及后续释放公式的交叉核对，不能当作新增引擎观测。下一修正应以隔离开关先验证物理脚部约束的连续髋部修正，并补充实际状态记录，不立即改正式动作库或替换MM。设计细节见[下一方案分析](../.tools/coherent-pelvis-presentation/next-design.md)，证据边界见[独立审查](../.tools/coherent-pelvis-presentation/independent-review.md)。
