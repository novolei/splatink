# PC 下半身与显示位置协调实验

2026-10-04。**默认关闭，未接受为正式玩家体验。** 使用原来的 Native Motion Matching 和原87关节角色；未把新 Mixamo 候选加入正式动作库。Mixamo 素材评估见 [21个循环修整候选](mixamo-loop-refinement.md)。后续[骨盆协调实验](coherent-pelvis-locomotion.md)改善144帧腿部跳变，但因原骨骼连接变形和枪口显示偏移仍未接受。

## 实现与边界

新增 `--presentation-interpolation=coherent`，仅用于本地、地面、稳定 kid 形态的 Native MM 角色。显示位置在前后物理包之间插值，朝向保持当前物理朝向。八个腿骨先插值，再用无状态两骨几何重建前后物理帧已求解的世界 FK 脚端；目标来自实际 FK，不是原 FootPlant anchor。不伸长局部骨骼、不降低骨盆。

每次呈现先恢复物理包；进入下一物理步前按原始 position/quaternion/scale 精确恢复，包括被几何改写的非动态关节。部分 `hair_1_*` 模型使用 thighR/shinR 权重，这些模块关节也同步并恢复。render 不调用 MM、AnimationTree、FootPlant 或 spring step，不推进动画时钟。

相机继续获取当前权威目标。权威枪口 getter 使用物理包缓存，可见枪口另以实际 hand FK 独立观测。显示模型与权威射击点可能相差一物理帧距离，不能用 getter 不变冒充可见枪口不变。

实现：[Avatar接线](../scripts/characters/ink_avatar.gd)、[呈现几何](../scripts/animation/experiments/ink_coherent_presentation.gd)。物理控制器、相机代码及服务未改。

## 生命周期与跨平台检查

已修复两个 coherent 专用问题：移动中重生时，旧显示 local X/Z 不能进入新物理包；关闭后再开启，须等下一物理步重新确认准入。传送路径恢复 tick local X/Z/basis，保留 Actor 设置的新 Y，再 fresh capture；开关路径 restore、invalidate 并清除准入标记。

最终 [Windows V5](../shots/coherent-contract-v5.json) 与 [macOS V3](../shots/mac-coherent-presentation-v3/output/coherent-contract.json) 各 **109148 checks / 0 failures**。覆盖1260次呈现、360次模块快照、全部87关节精确恢复、非腿关节不变、时钟/FootPlant状态、物理 root、权威 sockets、7武器重建、形态/空中/远端准入、移动中传送和开关准入。

这不是观感验收。独立移动样本有7次不可达目标：最坏目标距离 `.553238988m`，固定两骨最大距离 `.538217127m`，实际 FK 误差 `.015020671m`。世界骨长投影变化最大 `.000392318m`，局部骨长保持；不能宣称世界几何完全不变。

旧 Mac V2 运行时配合新 V5 检查，触发 [7项预期失败](../shots/mac-coherent-presentation-v3/output/coherent-legacy-regression.json)，复现传送和开关缺陷。新 V3 通过。负对照日志故意保留 ERROR，未计入32份最终干净日志。Windows V1/V2/V4失败记录也保留：涉及整根变换写入的浮点 basis 扰动、测试误用单次大 dt、测试用 double 字面量精确比较 float32 Y。

Mac 首次准备因基线 InkPosePresentation SHA 不同被拒绝，未创建 stage；随后明确将当前基类列入隔离 overlay。最终5文件包31720 bytes，SHA256 `39bf159139b7b67681733e22ebac9d3dc9cd347aef5ebd9b451980bd6f2271ee`，保存在 `.tools/coherent-presentation-macos/20261004-coherent-presentation-v3.tar.gz`。Mac 使用 ARM64 Godot 4.7.1、独立 QA stage 和 engine.lock；本轮未进行 Mac GPU 实战输入。

## Windows 真实输入对照

Godot 4.7.1 / a13da4feb，D3D12 Mobile，RTX 5090，1280×720。真实 main/start_match，经实际 W/A/S/D、fire、jump、form 输入；急转序列额外使用真实鼠标 +90°、−180°和停步 +90°。8个生产 Actor，另外7个使用诊断 idle bots；低画质、VSync OFF、固定 cap、无同步截图。这不是八个活跃 AI 战斗性能或发布包验收。

新增高物理优先级 observer 在 game tick 后只读记录每个物理帧；frame_post_draw 另记录显示 FK、独立可见枪口、两个相机/FOV、接触/权重/anchor 和预期 root。工具：[实际链](../tools/verify_locomotion_real_chain.gd)、[只读observer](../tools/locomotion_physics_observer.gd)、[分析](../tools/analyze_locomotion_real_chain.py)。

OFF/ON 只指 coherent；Native MM 两路均开启，判据实验关闭。腿变化为 rad。接触误差为**移动且完整现有接触权重**时 ankle FK 到原 anchor 的最大距离。

| 条件 | render样本 OFF / ON | 最大grounded腿变化 OFF / ON | 移动完整接触样本 OFF / ON | 对应最大接触误差 m OFF / ON |
|---|---:|---:|---:|---:|
| 144 cap 普通输入 | 1842 / 1843 | .334004 / .693865 | 12 / 12 | .010822 / .009765 |
| 30 cap 普通输入 | 384 / 384 | .637263 / .651436 | 5 / 5 | .012015 / .010754 |
| 144 cap 六倍时间压力 | 307 / 310 | 1.243756 / 3.094986 | 0 / 0 | 未覆盖 / 未覆盖 |
| 144 cap 鼠标急转 | 2591 / 2591 | .416122 / .735516 | 17 / 17 | .010822 / .009238 |
| 30 cap 鼠标急转 | 540 / 540 | .790336 / .749240 | 6 / 6 | .012015 / .011134 |

10路共 **141结构checks / 0 failures**，逐帧 finite、双日志干净。普通/急转每路分别768/1080个实际物理帧，六倍压力129帧。ON 普通/急转分别583/895个准入物理包，压力100个；所有 root/local/捕获关节三组件均与物理包精确一致。OFF 无呈现捕获包，明确未覆盖，不以0不一致冒充恢复验收。

原始报告为 `shots/pc-coherent-real-*-v1.json`，见 [完整汇总](../shots/pc-coherent-real-summary-v1.json)。普通/压力/急转两路分别257/188/341次原生查询，仍选择原234行 shooter bucket。两次独立输入运行可能存在时序落点差异，不能把最大值之差全部归因于算法。

30 FPS局部屏幕拟合无足够样本，明确未覆盖。完整移动支撑样本很少，不能以静止样本代替。部分脚端到旧 anchor 的较大距离发生在微小残余释放权重阶段，不等于仍应锁定的脚滑；完整支撑、获得和释放须分别评估。

## 质量失败的具体原因

普通144最大跳变在 sample91、起步 `.633333s`、tick326、alpha `.25`。右脚接触/权重由 `true/1` 变为 `false/.670320`。用独立记录的物理关节及 rig transform 重建，目标请求约 `.53930889m`，两骨最大 `.53821720m`，仅超出 **1.09169mm**，却使膝弯高度从91.45mm降至0再回到47.62mm。shinR变化 **.69386455rad**，该关节物理步变化仅 `.10790375rad`；膝平面没有翻转。脚端小误差隐藏了明显的关节不连续。

这项独立几何推断覆盖1387个具有相邻权威包的准入样本，仅发现一个超出10微米的目标。v1实际链未记录 helper runtime IK profile，真实 clamp 总数与 unsupported-affine 数量仍未知。不能用推断代替运行时计数，详见 [时序和几何审计](../.tools/coherent-presentation/144-timing-audit.md)。

普通144 ON 可见/权威枪口最大距离 `.091672m`，30 ON `.035542m`，压力 ON `.550002m`。这是显示位置落后物理位置的可见结果，尚需实战验证喷射点与判定的协调。

frame_post_draw 墙钟统计不能代表最终显示节奏。965个连续准入移动帧对按 `(tick+alpha)/60` 插值坐标计算，速度p95约6.000213、最大6.000613m/s；回调间隔不均时墙钟出现29.848m/s尖峰。当前没有 `_process` 时间、实际呈现时间或 GPU present 时间，不能据此宣布插值时序倒退，也不能宣称显示已匀速。

后续须协调骨盆与下半身姿势，或采用保持膝弯连续且明确披露脚端误差的过渡策略，同时保留上半身瞄准和物理判定的边界。单独打开 root 插值或把脚端逼到最大伸展，不足以实现丝滑移动。

## 素材与发布边界

最终 [审计](../shots/coherent-presentation-final-audit-v1.json)：32份最终日志无 ERROR/WARNING/Unicode 诊断，61个冻结输入 SHA/size/mtime 不变，正式两个 matcher 和三个数据库文件保持原快照。Mixamo ZIP、原角色及冻结候选未改；Mini Tanks 内容与服务未修改。本轮没有新导出包、手机或 iOS 工作，未接受本实验或21个Mixamo修整候选进入正式体验。

当前建议是**保留 Motion Matching 插件，用 Mixamo 补充并重新组织动作素材，继续处理接触与过渡**。插件查询能够工作；证据更指向素材、骨盆/脚部约束和显示层的协调问题。
