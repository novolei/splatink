# Mixamo 三个移动循环重定向候选

2026-10-04。已把前跑、左右快侧移制作成 **18 个独立实验 Animation 资源**，用于比较骨盆处理和实际播放节奏。离线结构契约通过，但18候选全部存在质量失败；Windows shooter 的实际导入诊断同样未通过角步长质量门限。`production_accepted=false`、默认关闭，正式 Avatar、控制器和 MM 数据库没有引用这些候选。

六循环的只读原始评估见 [mixamo-loop-feasibility.md](mixamo-loop-feasibility.md)。本次只制作其中三个快移动循环，没有把派生版本计为新增作者动作覆盖。

## 输入与可复查文件

原包 `E:\backup\Locomotion Pack.zip`：1,023,751 bytes，SHA-256 `e838c2f95645d2202b88ae972adb9560aefae0bfcb13e2082a4e37b4b70aac86`。原 `assets/characters/body.glb`：87 joints，SHA-256 `ca43f303d96cd17990f91fbbf48378132ee4dca39e3f38df4b61ce9d19dc7ce3`。三份源 FBX 各65骨、原30Hz关键帧，只有 Hips 根骨，没有单独 motion Root。

| 原文件 | bytes | SHA-256 |
|---|---:|---|
| running.fbx | 339889 | `e083e4870b8694f8baac03133c36a02d55e49713ac39a0ad009faec14885f484` |
| left strafe.fbx | 337633 | `737ab53106bcbad140041bae67ee8168e03e522955dec4702ff4a0ca1f6e2d48` |
| right strafe.fbx | 337633 | `0bf129106c646f9e2af64d83be22c235ff0bb5de5e70e990656e567ff818a97a` |

[mixamo_loop_retarget.py](../tools/mixamo_loop_retarget.py) 直接读取 ZIP，复用既有冻结 FBX parser/math 定义，不调用旧 contact corrector、Godot、Blender 或 SSH。原包、原模型、参考解析器、生产数据库和 matcher 等被监视输入的大小、SHA及mtime在生成前后相同，记录于 [provenance.json](../assets/animation/experiments/mixamo_loops/provenance.json)。

本次复核的生成脚本 SHA-256 为 `5a94114f498c70a8b95cdeade0ed6cb2e7198a1622cd97cc13d6ce73205305a2`；[loops.json](../assets/animation/experiments/mixamo_loops/loops.json) 为 `280f8c0e37b7e03618d035f27c4e4a4c3b2823703e4677099462d5df9edaaa11`；离线 `.tools/mixamo-loop-prototype/report.json` 为 `8a1ec083aa5d43063e65f19de8cfde18cdef8a1ab4abf09a65e71e5e139989d1`；上述 provenance 为 `c5ecee5ff0a342718571e58ddff5abff8635c99443252b93d3391b2ed7efe308`。

## 18候选的实际含义

三个源循环 × 三个空间模式 × 两个时间模式 = 18个 `.tres`。全部保留目标原骨长、非 Hips 局部平移及单位缩放；没有 Actor root、控制器或上身动画轨道。

| 空间模式 | 实际处理 |
|---|---|
| source9_baseline | 九个 lower 骨旋转加 Hips position，共10轨；移除源累计线性XZ移动，保留按腿长缩放的非线性骨盆摆动与rest-relative Y |
| fixed8_uncorrected | 只写八腿骨旋转，共8轨；保留相同姿势旋转，不写 Hips |
| fixed8_endpoint_reprojected | 只写八腿骨旋转；在固定rest Hips下尝试重现 baseline 踝端点，保留目标两腿段长度、带符号膝平面、原轴向twist和脚世界旋转 |

原 Hips 轨迹单独作为 metadata 保留，不叠加到物理移动。两个时间模式为 `original_time` 与 `leg_reference_retime6`；后者实际缩短资源时长及关键帧时间，不是只改虚拟速度标签或质量统计中的速度。候选采样周期如下：

| 源循环 | 原周期 s | 腿长缩放参考速度 m/s | 适配6m/s节奏倍数 | 新周期 s |
|---|---:|---:|---:|---:|
| 前跑 | .700000 | 2.819347 | 2.128152 | .328924 |
| 左快侧移 | .666667 | 2.911857 | 2.060540 | .323540 |
| 右快侧移 | .666667 | 2.911857 | 2.060541 | .323540 |

该节奏来自源平面净移动和目标/源大腿+小腿长度比例，仍是参考估算。当前正式运行的播放速率上限1.8没有调整，正式移动速度也没有降低；这些时长只存在于独立候选。

## 离线结果：部分脚滑下降，质量仍未通过

每个候选按实际时间在60/30Hz采样三个周期，以合成6m/s Actor平移估算鞋底proxy的世界运动。这个平移只用于离线测量，没有写进资源或运行时物理位置。

以下列出 source9_baseline 的两种时间，接触位移取左右脚最大值，角步长为全部lower局部旋转最大值：

| 循环 / 时间模式 | 60Hz接触段最大位移 m | 30Hz接触段最大位移 m | 60Hz最大角步长 rad | 30Hz最大角步长 rad |
|---|---:|---:|---:|---:|
| 前跑 / 原时间 | .584553 | .537025 | .401714 | .803428 |
| 前跑 / 6m/s参考节奏 | .084249 | .020886 | .707679 | .882634 |
| 左快侧移 / 原时间 | .683067 | .631829 | .370627 | .741254 |
| 左快侧移 / 6m/s参考节奏 | .038615 | .050614 | .684132 | .930322 |
| 右快侧移 / 原时间 | .583874 | .512871 | .359367 | .718735 |
| 右快侧移 / 6m/s参考节奏 | .031098 | .022250 | .701980 | .938690 |

source9 的60Hz接触候选脚XZ速度中位数，从原时间约3.1–3.2m/s降至约.13–.25m/s，说明速度匹配能缓解这个离线proxy中的一部分滑动。但更快的周期增加相邻采样的角变化；局部60Hz `.35rad` 门限、接触段 `.03m` 门限仍有失败。单个30Hz位移较小可能来自接触重采样和采样相位，不能作为更好的接触验收。

固定 Hips 后直接保留源腿旋转，侧移残余更加明显：`fixed8_uncorrected` 的参考节奏版本60Hz最大接触段位移，左/右分别约 `.704255/.560966m`，接触候选脚XZ速度中位数约6.3–8.5m/s。这说明只加快节奏并不普遍修复固定骨盆下的轨迹。

端点重投影也有明确几何限制。固定 Hips 的两段腿无法够到部分 baseline 踝目标；最大 reach clamp 前跑 `.030120m`、左 `.107962m`、右 `.100091m`，均超过原 `1e-5m` 端点门限。求解器把端点夹到可达长度并记录误差，没有拉长腿段或把夹紧结果计为原目标通过。该模式的参考节奏60Hz最大接触段位移仍约 `.104620/.136810/.069984m`；最高30Hz角步长约 `1.216737rad`。

离线报告为 **0结构失败、18/18候选质量失败**。资源均 finite、quaternion归一化、无root/上身轨道，说明文件结构可用，不代表动作表现合格。后续必须处理骨盆轨迹、目标触地和过渡，不能用放宽门限接受这些候选。

## 实际资源导入诊断

[verify_mixamo_loops.gd](../tools/verify_mixamo_loops.gd) 延后加载同一SceneTree的 Node helper；[mixamo_loop_prototype.gd](../scripts/animation/experiments/mixamo_loop_prototype.gd) 用真实 AnimationPlayer 手动采样实际 `.tres`，按导入后的原87骨名字映射。source9模式同时恢复三个上身边界的原global pose，保持武器与上身；fixed8保留生产 Hips。每次采样后恢复身体和衣服原authority pose，再让原MM继续运行。

以下只记录已复核的 Windows shooter Native headless V2 快照，证据为 [mixamo-loop-native-v2.json](../shots/mixamo-loop-native-v2.json) 和同名 `.log`：

该次console输出由Root的引擎工具返回，但未独立归档为 `.log.stdout`；本快照不计为完整双侧日志验收，后续重跑须单独保存标准输出。初版与V2记录继续保留。

| 项目 | 实测结果 |
|---|---:|
| 结构检查 / 失败 | 984111 / 0 |
| 角步长质量失败 | 68 |
| 案例 | 72：18资源 × rest_hips/production_aim_hold × 60/30Hz |
| imported AnimationPlayer 对独立JSON FK最大位置误差 | 1.894045e-7m |
| 上身global position / basis最大误差 | 3.656102e-7m / 5.170510e-7 |
| 枪口最大位置误差 | 0 |
| 最大60Hz / 30Hz腿角步长 | .756893rad / 1.216737rad |
| 最大未混合切入姿势差 | 2.260210rad |
| 原库实际Native查询 / 每次实际访问行数 | 829 / 234 |

角步长门限保持60Hz `.35rad`、30Hz `.7rad`，68项失败保留；这里不做离线合成平移/接触proxy验收。未混合entry只记录，没有过渡处理，不能称为丝滑切入。`production_aim_hold` 是调用原 Avatar 动画的权威姿势上下文，仍不是实际控制器输入、移动或战斗。

初版误将 glTF skin joint slot 当成 Godot Skeleton3D bone index，出现8个结构失败，保存于 `shots/mixamo-loop-native-first.json/.log`。V2 fixture改为从原GLB独立检查slot→name，再检查导入后的bone name/parent；原资源字节未改，门限未放宽。该错误属于验收映射，不能隐藏初版失败或宣称它是源重定向问题。

原provider仍为 `native MMAnimationLibrary exact contiguous search`，原库1638姿势、63D、当前武器234行；18个候选由实验AnimationPlayer覆盖下肢，**没有加入原生查询库**。829次原库查询证明已有provider继续工作，不证明它已选择这些新循环。

### 最终双侧日志与 Mac 复查

为补齐console归档，Root保留上述V2后，串行完成以下V3运行；每路 `.log` 与 `.log.stdout` 独立保存并扫描，均无runtime/shader ERROR、WARNING或Unicode诊断。V3没有改资源或采样算法。

| 平台 / provider / 武器 | 每路检查 | 结构失败 | 每路角步长失败case | 每路cases |
|---|---:|---:|---:|---:|
| Windows Native / 全部七武器，各一条运行 | 984111 | 0 | 68 | 72 |
| Windows portable / shooter | 984110 | 0 | 68 | 72 |
| Mac M2 Max ARM64 Native / shooter | 984111 | 0 | 68 | 72 |
| Mac M2 Max ARM64 portable / shooter | 984110 | 0 | 68 | 72 |

Windows为 `shots/mixamo-loop-native-{shooter,roller,charger,blaster,dualies,slosher,splatling}-v3.*`、`mixamo-loop-portable-v3.*`。七路Native各实际查询原库829次、每次234行；全部枪口误差为0，上身位置最大误差不超过`3.717086e-7m`、basis不超过`5.170510e-7`、独立JSON FK位置不超过`2.000589e-7m`。这证明本批导入资源在该姿态上下文中可保持上身契约，不能代替动作选择或实际世界触地验证。

Mac副本为`/Users/ryanliu/splatink-build/20261004-mixamo-loops`，从冻结V3 MM QA副本复制并进行两次全新导入；日志和JSON取回 `shots/mac-mixamo-loops/logs/`、`output/`。两个provider保持相同失败case数量，Native查询仍829次/234行，上身位置最大`3.656102e-7m`、枪口0。原参考项目及旧导出没有改动。

25文件窄归档 `.tools/mixamo-loop-prototype/20261004-candidate-v3.tar.gz` 为104645bytes、SHA-256 `00669b915d3942d84e17611f102b3d469475eb088911aace75d9107216034df2`。manifest验证每个文件及原body、featurebin、matcher、Mac dylib的SHA；归档不包含GPU visual helper。准备/诊断由Root唯一串行操作，没有覆盖旧QA副本。

这里的68是**72个“资源×Hips背景×采样率”case中失败的case数**，与离线报告“18/18唯一候选有质量失败”口径不同。它们都是失败，不是98万项检查通过即可接受。步长包含toe/foot各局部关节，不能把某一关节最大值解释为整个身体的旋转。

### GPU 姿势显示证据

Root用D3D12 Mobile/RTX5090分别渲染前跑、左右快侧移的三种空间模式，各四个独立相位。最终每路133 checks/0 failures、4 PNG，两份日志干净；证据为`shots/mixamo-loop-{running,left_strafe,right_strafe}-gpu-v7/`及同名前缀`.log/.log.stdout`，共12张PNG。

自动检查在正常画面中先记录真实Skin/Cloth/Eyes的mesh、skin、surface及原始可见性。仅在实验中关闭这些body mesh的投影，然后比较正常图与只隐藏这些网格的参考图；头发/武器保留。躯干和左右足区域有直接RGB变化，不靠头发或枪的颜色代替身体。原可见状态恢复，viewport坐标明确转换到截图像素。Root另实际查看PNG确认人物、服装、鞋及枪的姿势显示。

早期running的V4缺坐标缩放导致36失败，V5对白鞋亮度的假设导致12失败，报告和图片保留。V6差分门槛通过，但review发现一律show会掩盖原本隐藏的网格；V7把可见性检查移到隐藏前并恢复原值。未降低质量阈值或覆写失败记录。

这些是独立静态采样，不能证明两倍节奏自然、完整移动连续性或真实MM库已接入。后续动态输入与导出验证仍须在候选质量达标后执行。

## 接触证据与后续验收范围

接触候选来自源30Hz toe/toe-end高度和世界XZ速度：clip最低toe高度上方 `.03m` 内、XZ速度不超过 `.25m/s`。没有作者接触标签。离线目标诊断使用最近源关键帧标签；鞋底点为已有runtime的heel/ball几何proxy，不是实际鞋网格。没有目标地面高度校准、terrain query或world foot lock；这些接触位移不能与真实 Avatar 的完整权重 FootPlant anchor误差混为一谈。

补充结果覆盖Windows七武器、Mac shooter和GPU静态姿势，但没有连续画面、实际输入或导出包验收。循环包仍缺作者制作的后退、对角、起步、急停及跑动90°/180°pivot；三个循环即使完成速度适配也不能补齐这些覆盖。正式角色、MM库、控制器和物理root继续使用原实现。候选保留供进一步打磨，`controller_input_test=false`、`production_accepted=false`，没有接受手感、性能或整体locomotion观感。


后续已制作21个修整对照并完成Windows/Mac资源检查，仍全部有质量失败；见 [修整评估](mixamo-loop-refinement.md)。这不改变本页原候选的冻结结论。
