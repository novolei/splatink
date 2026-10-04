# Motion Matching 插件评估

2026-10-04。结论：这套方案值得采用其动作制作和查询策略；Splatink 最需要补的是起步、刹停、转身与步态过渡内容。建议先为原角色制作这些动作，再试验仅接管地面 locomotion 的插件适配器。保持原 87 骨角色、七种武器握姿、脚部接触和物理控制。

本轮只读检查三个参考目录、冻结补丁、二进制哈希与既有测试记录，并核对官方上游源代码。没有运行、导入、构建或修改参考工程，也没有更换 Splatink 运行时插件。

## 原生源码、演示、已验玩家与当前项目

| 工程 | 实际内容 | 与 Splatink 的关系 |
| --- | --- | --- |
| `F:\Downloads\godot-motion-matching-master\godot-motion-matching-master` | 完整原生 C++ 工程；HEAD 是本地自定义基线，工作区已含与 Rooftop 冻结补丁一致的增量 | 有限原生适配器的推荐代码来源 |
| `F:\Downloads\godot-motion-matching-demo-master\godot-motion-matching-demo-master` | 演示工程、Motorica 素材、使用代码、预编译 GDExtension；已有本地修改 | 可复用动作数据制作、Humanoid 重定向和调试方法 |
| `D:\Godot resource\rooftop-bird-team` | 面向当前 24 骨 Mesh 的 MM255 玩家与冻结 Windows 原生扩展 | 查询、步态语义、惯性化和状态边界的主要参考 |
| `H:\GDP\inkwave\splatink` | 从 INKWAVE 原角色动作生成的可移植姿势查询器 | 已参考 Rooftop 的设计概念，尚未加载它的原生插件 |

F 盘 demo 的 Git HEAD 为 `872b104880de39a7794629bdaa296dd25071683a`，最后提交为 2026-08-10 的跳跃切片。其 [README:3](<F:/Downloads/godot-motion-matching-demo-master/godot-motion-matching-demo-master/README.md:3>) 明确是扩展的使用演示；目录中没有原生 `src/`、`SConstruct`、`godot-cpp/` 或 `.gitmodules`。Git 历史、Motorica 标签和自定义 API 说明它已有本地扩充，不能把它视作未经修改的上游初版。

新提供的 F 盘 native 目录具有完整 [SConstruct:47](<F:/Downloads/godot-motion-matching-master/godot-motion-matching-master/SConstruct:47>)、`src/` 与实际 godot-cpp。只读核对结果：HEAD 正是 `0208dd54902cca8a3bb016ed6591bfc933e2243a`；17 个 tracked 修改和 2 个新增 gait 文件合计 19 个文件，逐个 `git hash-object` 与冻结 patch 的目标 blob 比较，**19/19 完全一致，0 差异**；godot-cpp HEAD 也匹配 `7e18e40d7591429f915035a7de7cf79457d555cc`。准确原生源码已找到，缺少源码的限制已解除。没有本轮新构建结果。

## 原 demo、官方上游和 Rooftop 增量

F 盘的 [构建脚本:59](<F:/Downloads/godot-motion-matching-demo-master/godot-motion-matching-demo-master/build_motorica_library.gd:59>) 已包含 Crouch/Stationary 标签，[脚本:181](<F:/Downloads/godot-motion-matching-demo-master/godot-motion-matching-demo-master/build_motorica_library.gd:181>) 调用 `bake_from_nodes()`；磁盘有 254 个 Motorica FBX，另追加 MixedLocomotion1。[Meshy 场景:29](<F:/Downloads/godot-motion-matching-demo-master/godot-motion-matching-demo-master/character/meshy/meshy_character_scene.tscn:29>) 已含 RetargetFoot、Inertialization，以及关闭的 FootIK。[MM 节点:7](<F:/Downloads/godot-motion-matching-demo-master/godot-motion-matching-demo-master/character/meshy/mm_animation_node_meshy.tres:7>) 配置 20 Hz 查询、0.15 continuation margin、0.18 s 最短切换；[默认 main_vrm:32](<F:/Downloads/godot-motion-matching-demo-master/godot-motion-matching-demo-master/scenes/main_vrm.tscn:32>) 使用 `root_motion_amount=0.3`。这些配置不能直接套到 Splatink 的物理控制上。

官方上游本轮读取的 master HEAD 为 `5fe36ad06fbd203df52e3ecb8e5c01b0363f81d5`。它提供 AnimationTree 集成、轨迹/骨骼特征、烘焙和 KD-tree 查询；其 DampedSkeletonModifier 是持续追踪目标姿势的弹簧平滑。Rooftop 所用的新步态特征、查询调度与惯性化补丁属于额外实现。[上游说明](https://github.com/GuilhermeGSousa/godot-motion-matching/blob/5fe36ad06fbd203df52e3ecb8e5c01b0363f81d5/README.md)、[查询源码](https://github.com/GuilhermeGSousa/godot-motion-matching/blob/5fe36ad06fbd203df52e3ecb8e5c01b0363f81d5/src/mm_animation_library.cpp)、[姿势平滑源码](https://github.com/GuilhermeGSousa/godot-motion-matching/blob/5fe36ad06fbd203df52e3ecb8e5c01b0363f81d5/src/modifiers/damped_skeleton_modifier.cpp)。

Rooftop 当前正式查询采用 C++ contiguous exact scan 与维度 early-out，极少数完全同价情况保留旧 KD tie 行为。不能将其性能解释成常规 KD-tree 加速。[冻结补丁:480](<D:/Godot resource/rooftop-bird-team/docs/godot-prompter/standards/patches/mm255-native-0208dd54902c-aa4c3be232d9.patch:480>)。

上游扩展使用 MIT 许可，F 盘原生源码也保留同一许可，应保留版权和许可文本；这份代码许可没有说明 Motorica FBX 和各角色资产的授权。本地 demo 的 motion_matching 目录未附许可证副本，迁移时应使用真实资产各自的授权记录。[本地 LICENSE.md:1](<F:/Downloads/godot-motion-matching-master/godot-motion-matching-master/LICENSE.md:1>)、[上游 LICENSE.md](https://github.com/GuilhermeGSousa/godot-motion-matching/blob/5fe36ad06fbd203df52e3ecb8e5c01b0363f81d5/LICENSE.md)。

## 动作内容与现有能力

| 项目 | Rooftop 当前正式玩家 | Splatink 当前实现 |
| --- | --- | --- |
| 动作库 | 255 段、53,849 姿势、67D；10 Hz 数据库采样 | 42 段、1,638 姿势、63D；30 Hz 数据库采样 |
| 特征 | 21 轨迹 + 42 骨骼 + 3 标签 + 1 步态 | 21 虚拟轨迹 + 42 骨骼位置/速度 |
| 移动内容 | 八向 Walk/Run、Sprint、弧线、Start/Stop/Pivot/TurnInPlace/Transition | 七武器各自 idle/walk/run/strafe-left/strafe-right/backpedal |
| 节奏 | 连续稳定 0.30 s 后进入 LoopPhase；仅稳定循环按真实 authored 根速度拟合 | 原地动作按显式速度标签拟合；没有 authored Stop/Pivot 片段 |
| 脚部 | RetargetFoot→Inertialization→VisualLean；正式 FootIK 关闭 | 原 IK 解算、地形采样、脚锁、接触释放和受击 catch-step |
| 战斗 | 独立十条上半身旋转轨的 Aim/Fire/Reload；没有正式枪模、手指和枪口 | 原七武器、手指握姿、双手瞄准、实际/虚拟枪口与原攻击动作 |

数据证据：[Rooftop README:9](<D:/Godot resource/rooftop-bird-team/game/player/motion_matching/README.md:9>)、[Release 身份日志:3](<D:/Godot resource/rooftop-bird-team/builds/mm255-final-frozen/release/mm255-validation.log:3>)、[Splatink 数据:1](H:/GDP/inkwave/splatink/data/motion_matching.json:1)。10 Hz 指候选姿势采样，动画轨道仍连续求值，不表示动画以 10 FPS 播放。

Rooftop 的优势是有足够的动作内容，让查询器在刹停、反向和转弯时选择完整的重心变化。Splatink 已有真实姿势/速度查询、continuation hysteresis 和惯性化，缺少这些过渡片段是更直接的观感限制。[当前查询器:78](H:/GDP/inkwave/splatink/scripts/animation/ink_motion_matcher.gd:78)、[惯性化:45](H:/GDP/inkwave/splatink/scripts/animation/ink_inertializer.gd:45)。

Rooftop 的步态与稳定阶段策略值得移植；0.30 s 仅控制稳定循环候选，并非移动输入延迟。其查询有 20 Hz 稳态、30 Hz forced 上限和初始立即查询。本地实际条件见 [玩家:2830](<D:/Godot resource/rooftop-bird-team/game/player/motion_matching/mm_tps_player.gd:2830>)、[调度补丁:1062](<D:/Godot resource/rooftop-bird-team/docs/godot-prompter/standards/patches/mm255-native-0208dd54902c-aa4c3be232d9.patch:1062>)。Splatink 当前为本地 20 Hz、远端 8 Hz，意图突变可提前查询；扩大动作库后应重新评估 forced-query 开销。

Rooftop 的 FootIK 正式关闭，是因为当前 24 骨模型的膝盖弯曲平面不稳定。[场景:255](<D:/Godot resource/rooftop-bird-team/game/player/motion_matching/mm_tps_player.tscn:255>)、[说明:116](<D:/Godot resource/rooftop-bird-team/game/player/motion_matching/README.md:116>)。这部分不能替换已调好的 Splatink 脚部接触。

## 惯性化、渲染平滑与性能

Rooftop 原生惯性化补丁会在新动作切入时保留输出姿势，处理零 delta 与同一物理 tick 多次评估，并提供 teleport reset；新目标动画立即继续，偏移随后衰减。[补丁:3966](<D:/Godot resource/rooftop-bird-team/docs/godot-prompter/standards/patches/mm255-native-0208dd54902c-aa4c3be232d9.patch:3966>)。Splatink 也使用位置和 quaternion-log 偏移，并按新动作目标速度计算惯性偏移。

实际 C++ 切换逻辑保证 C0 姿势连续，但没有重新计算“旧输出速度减新目标速度”的 offset velocity；现有衰减速度会继续使用。Splatink 的 `local_velocity_at()` 与 `_begin()` 已计算该差值，因此不能把 native 实现一概认作更强的速度连续性方案。[实际 native:138](<F:/Downloads/godot-motion-matching-master/godot-motion-matching-master/src/modifiers/mm_inertialization_modifier.cpp:138>)、[Splatink:100](H:/GDP/inkwave/splatink/scripts/animation/ink_inertializer.gd:100)。移植应保留或按相同验收补足这项行为。

这与 60 Hz 权威骨骼在高刷新率画面中的 render interpolation 是两个问题。Rooftop 开启全局 physics interpolation，[project.godot:295](<D:/Godot resource/rooftop-bird-team/project.godot:295>)；该设置本身不能作为骨骼最终 pose 在 144 Hz 连续呈现的证据。Splatink 独立的呈现缓冲原型保持默认关闭，等待成本合格；插件迁移也不会自动消除这项开销。[呈现缓冲:3](H:/GDP/inkwave/splatink/scripts/animation/ink_pose_presentation.gd:3)、[默认配置:47](H:/GDP/inkwave/splatink/scripts/characters/ink_avatar.gd:47)。

Rooftop 文档记录的 headless 压力结果是单人 p95/max 1.424/2.042 ms、八人 5.753/13.952 ms。它不是 Splatink 八角色、完整场景、实际 GPU 的新验收，也不能与当前游戏 FPS 直接比较。[历史记录:199](<D:/Godot resource/rooftop-bird-team/game/player/motion_matching/README.md:199>)。

Rooftop 的质量工具明确是 baseline guard，关节/头部门限为 60°/45°；不能仅凭通过就断言更丝滑。[质量工具:24](<D:/Godot resource/rooftop-bird-team/tools/validate_motion_matching_quality.gd:24>)。Splatink 既有真实物理轨迹记录为 105 检查/0 失败、最终可见 pose 最大单帧变化 0.341704 rad（19.58°）、接触误差最大 0.01063 m。[既有日志:24](H:/GDP/inkwave/splatink/shots/pc-motion-inertia-corrected.log:24)。迁移试验应保持现有门限，并比较同输入轨迹、同相机、同武器的最终 IK 后姿势和真实画面。

## 原生版本与可复现边界

Rooftop 运行映射明确选中 `.mm255stagger2.dll`，最低 Godot 4.7、reloadable=false；冻结验证引擎为 `4.7.1.stable.official.a13da4feb`。[运行映射:4](<D:/Godot resource/rooftop-bird-team/addons/motion_matching/gdmotionmatching.gdextension:4>)、[版本记录:15](<D:/Godot resource/rooftop-bird-team/docs/godot-prompter/standards/mm255-native-build-provenance.md:15>)。本轮直接计算哈希，与记录一致：

| 制品 | SHA-256 |
| --- | --- |
| `bin/windows/libgdmotionmatching.windows.template_debug.x86_64.mm255stagger2.dll` | `eb6fe9e8fdbfca7fa845c3f0ab34d14d297062fcf8cf2889c1163bf327177f84` |
| `bin/windows/libgdmotionmatching.windows.template_release.x86_64.mm255stagger2.dll` | `2e16b66e83046d019a192e7a4289ff52781f95d7a80d72c43c6c90f1a1230082` |
| `mm255-native-0208dd54902c-aa4c3be232d9.patch` | `ef1cf21c7dbd3a0779283ff2545feef8f7a42714e411bb352bdb112b1e051e18` |

完整来源：[provenance:24](<D:/Godot resource/rooftop-bird-team/docs/godot-prompter/standards/mm255-native-build-provenance.md:24>)。记录的 native 基线为 `0208dd54902cca8a3bb016ed6591bfc933e2243a`，快照 tree 为 `aa4c3be232d94b7201d30395dfcc51d69a2c71d1`，godot-cpp 为 `7e18e40d7591429f915035a7de7cf79457d555cc`。新提供的 F 盘 native 目录已经恢复这份基线、全部 19 个冻结增量文件和匹配依赖，后续应从它的独立快照编译。该本地基线含此前的 TagFeature、RetargetFoot、惯性化、continuation 和触发式播放扩充；其 HEAD 历史与当前在线 master 不同。保留完整本地基线及新增文件比只保存普通 `git diff` 更可靠。

F 盘当前映射为较早的非版本后缀 DLL，最低兼容 4.4、reloadable=true；Windows debug 哈希为 `1376ffb34d0154b4806bdd7d47c35f82ce84fefe6a799afcb7bed77d4f8aa268`，所映射的 Windows release 文件缺失。Demo 本身无法证明这枚 DLL 对应哪一个原生 C++ commit。[F 盘映射:4](<F:/Downloads/godot-motion-matching-demo-master/godot-motion-matching-demo-master/addons/motion_matching/gdmotionmatching.gdextension:4>)。

两处同名 `motorica_meshy_library.res` 也不同：F 盘 SHA 为 `e2c9f12656207be1bd897d405c979bd623dfeedf6a1f22006f0c2a3cb8e46e52`，Rooftop 源库 SHA 为 `fce2c6e9e25ab7166bb16d8bc968687e2a6a3b57925b2d4e4037ac10f9ace7f6`。Rooftop 的 255/53,849/67D 是其已验收目标库的身份，不能据此宣称 F 盘整个工程与冻结版本完全一致。

当前冻结承诺只覆盖 Windows x64 single precision。macOS/其他平台映射存在，并不能证明包含相同补丁或已验证；Win 与 macOS 应从同一完整快照构建并分别进行真实运行验收。[支持边界:62](<D:/Godot resource/rooftop-bird-team/docs/godot-prompter/standards/mm255-native-build-provenance.md:62>)。

## 推荐实施顺序

1. 先补目标骨架上的起步、刹停、90°/180° pivot、斜向过渡与脚接触标记。优先保留原循环动作和墨汁角色弹性；重定向时按真实层级、rest、腿长、脚底高度校正，在原 87 骨模型上重新烘焙特征。保留脸、头发、服装、手指和源武器动作。
2. 做一个 shooter 地面 locomotion 小样适配器，保留现有 provider 切换入口。AnimationTree 混合武器上半身，动作切换后惯性化，随后保留原脚部/双手接触；Kid/Squid/Swim/Climb/Air/Special 等分支继续独占各自状态，进入和退出时重置查询历史。CharacterBody/源控制器独占世界位移，`root_motion_amount=0`；authored 根轨迹只用于查询和节奏数据。
3. 查询器先保持现有可移植实现；数据扩充后，再比较 Rooftop 冻结 C++ 适配器的同画面收益与完整 CPU/GPU 成本。推荐以 F 盘已核对的完整原生源码建立独立开发快照，保留 Rooftop 已验查询/步态/调度增量，避免采用 demo 的旧 DLL 或直接回退至在线 master。原参考目录继续只读。不要把 Rooftop 的控制器速度、朝向半衰期或 root-motion 混合比例迁入 Splatink，以免改变原瞄准和移动响应。
4. 以相同真实输入轨迹验证启动/刹停/反向、八方向、七武器、形态切换、坡面、接触释放及枪口；保留既有连续性/接触/瞄准门限。随后在 Windows 与 macOS 分别验证同源码的 Debug/Release 包，测八角色与高刷新率画面；有可见收益且成本合格后再决定默认方案。

这套插件最能改善 Splatink 的部分是丰富、适合目标风格的过渡动作，以及让这些动作稳定参与查询的语义设计。原模型和战斗动作保持源风格，移动姿势可以因此更自然；单独替换搜索算法并不能创造缺失的动作。

## 已授权的下半身原生试验

2026-10-04 用户明确要求将 Splatink 下半身接到 motion matching。已从上述 F 盘只读源码建立隔离快照，验证全部 19 个冻结增量，编译 `splatlower1` Windows debug/release 库。新增 `configure_external_database()` 和 `query_normalized_vector()` 只开放原生数据库查询入口，直接调用既有 C++ exact contiguous search，并计算真实 continuation cost。Splatink 继续负责物理速度、意图轨迹、查询时序和现有速度惯性化；不会实例化原插件的 MMCharacter 控制器。

试验入口是 `--native-locomotion-mm`，默认关闭。AnimationTree 的 MotionSelection 仅选 hips/thigh/shin/foot/toe 九条骨骼通道；上半身、头脸、头发和武器动画继续走原图，惯性化也仅写这九根骨骼。当前仍使用 42 段原循环动作和七个 234-pose bucket，没有声称已添加 authored Start/Stop/Pivot。Windows/macOS 的实际原生契约、最终脚 IK 连续性、瞄准和八角色 GPU 场景已验证，网络退出清洁性与同机位玩家观感仍需继续检查。

可复现准备/补丁/构建位于 [prepare_native_mm.mjs](H:/GDP/inkwave/splatink/tools/prepare_native_mm.mjs)、[patch_native_mm.mjs](H:/GDP/inkwave/splatink/tools/patch_native_mm.mjs)、[native_mm_sconstruct.py](H:/GDP/inkwave/splatink/tools/native_mm_sconstruct.py)；运行制品记录在 [provenance.json](H:/GDP/inkwave/splatink/addons/motion_matching/provenance.json)。macOS 使用同源独立构建脚本 [build_native_motion_matching_macos.sh](H:/GDP/inkwave/splatink/tools/build_native_motion_matching_macos.sh)，Root 已从同一修复版归档完成 universal debug/release 编译与实际 macOS 原生契约、包内八角色 GPU 验证。

Root 首轮实际 Windows 引擎结果为 native 2809 检查/0 失败，既有 motion 105/0、aim 78/0，以及真实 GPU 键鼠/墨地/变身输入 33/0。Native 最终 IK 后物理轨迹最大单帧变化 0.347815 rad（19.93°）、髋部变化 0.04495 m、脚接触误差 0.01069 m，保留原 0.35 rad/3 cm 门限。见 [native 契约](H:/GDP/inkwave/splatink/shots/pc-native-mm-fixed-contract.log)、[motion](H:/GDP/inkwave/splatink/shots/pc-native-mm-quality.log)、[实际输入](H:/GDP/inkwave/splatink/shots/pc-native-mm-real-input.log)。这说明下半身原生适配正常，不能证明已比原 provider 更优雅。

首次 import 暴露了源插件编辑器面板的释放缺漏：detach 后未 delete，自定义 UI 子树在退出时泄漏。已只在独立源快照补 `memdelete(_editor)`，更新两枚 Windows 制品和完整源归档；Root 重复 import 的 stdout/stderr 已无泄漏。[窄修说明](H:/GDP/inkwave/splatink/tools/native_mm/editor-lifecycle-fix.md)、[修复后日志](H:/GDP/inkwave/splatink/shots/pc-native-mm-fixed-import.stdout)。三个原参考目录持续只读。

同源 macOS 文件已放入 addon 的 bin/macos，并映射 universal arm64/x86_64；debug SHA-256 为 `542b4df0b2fff8479d4a112498704e767901e955e979fe9db38be26b82aa878c`，release 为 `8a54d9979e42e9df5d00b7769d4247c218d08e6f29f6ba661c564a63f109a375`。Root 的 lipo/依赖检查确认两架构与系统 libc++/System 依赖。真正 macOS Godot 加载后的 native2809、motion105、aim78检查均0失败，378次实际新增查询 median/p95/max 为10/15/21μs；包内八角色原生 GPU 场景平均106.56FPS、p95帧时间10.60ms，见 [Mac构建记录](H:/GDP/inkwave/splatink/builds/20261003180842-macos/output/build_record.json)、[实际GPU截图](H:/GDP/inkwave/splatink/builds/20261003180842-macos/output/mac-gpu.png)。这是该Mac与配置的单次场景数据，不能与Windows不同硬件数据直接比较。

真实双机 LAN 的 Host45/Guest44逻辑记录已通过 native/cadence 检查，但Mac Host退出仍报告2个ObjectDB对象泄漏，因此这轮网络验收不能称为完全清洁通过。后续完全禁用扩展的独立新副本也重现同样警告；提前清音频后，禁扩展与native ON两组均无ObjectDB警告，已排除原生MM/扩展/网络为必要条件。具体两个对象尚未识别，见 [退出诊断](macos-headless-shutdown-diagnostic.md)。独立Mac契约与包内GPU退出没有相同警告。当前原生适配仍为试验入口，默认关闭。

实际 Windows Boss 场景已确认八个角色均使用原生查询（每角色 202–356 次，无 native_error），见 [GPU 记录](H:/GDP/inkwave/splatink/shots/pc-boss-native-mm-on.json)。该轮 off/on 平均 FPS 为 73.07/88.41、p95 帧时间为 34.99/30.95 ms；FX/随机轨迹并非完全一致，所以不能把差值全部归因于原生 MM。独立契约改为只收集真正新增查询后，378 次 native query 为 median/p95/max 10/16/19 μs，[真实查询采样](H:/GDP/inkwave/splatink/shots/pc-native-mm-query-sampling.log)。这与完整八角色帧成本仍是两个指标。

另有默认关闭的 `--presentation-interpolation=lower` 摆腿呈现试验。它只捕获八根腿骨；支撑腿、hips、根节点、上身、武器、头发、眉毛和材质均保留当前物理帧。独立真实FK契约450062检查/0失败，呈现脚接触误差最大1.069cm、上身全局误差0，物理/呈现最大单帧角度分别0.347815/0.306726rad。独立捕获/呈现/恢复 median 为7/4/2μs（呈现最大316μs保留在记录中）。后续完整八角色Boss GPU OFF/ON运行均干净，ON单角色捕获/呈现/恢复 median 9/7/5μs、p95 15/20/10μs；捕获时四角色处于允许呈现状态。FX/AI轨迹不同，103.43/111.64FPS不能算因果提升。见 [试验与局限](H:/GDP/inkwave/splatink/docs/lower-pose-presentation.md)、[FK契约](H:/GDP/inkwave/splatink/shots/pc-lower-presentation-contract.log)。

用户提供的 Mixamo Locomotion Pack 已完成静态审计与四个站立转向独立重定向。原生ON的七武器 × 四片段 × 两模式契约985355检查/0失败，实际1092次新增native查询继续处理原循环库；新turn仍为独立AnimationPlayer小样，未加入搜索库。八腿骨内段最大17.45°，原服装、上身和枪口保留，完整原时间近景视频已生成。但切入姿势差/快速输入转向时序未解决，缺少专门Start/Stop/running Pivot，因此建议继续保留现有native方案、用Mixamo补素材，不能将这包视为直接替换方案。见 [动作包评估](mixamo-locomotion-pack-assessment.md) 和 [转向小样](mixamo-turn-prototype.md)。
