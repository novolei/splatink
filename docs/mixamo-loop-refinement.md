# Mixamo 移动循环修整评估

后续实战呈现评估见 [coherent 下半身与显示位置协调实验](coherent-locomotion-presentation.md)。该实验沿用原 MM 库，未选择以下 Mixamo 候选；已定位到释放阶段的可达边界导致膝盖跳变，继续默认关闭。

2026-10-04。建议继续保留现有 Motion Matching 插件，把 Mixamo 用作补充动作素材。这两者可以配合：插件负责选帧和过渡，素材仍需要匹配目标骨架、移动速度、落脚和瞄准。当前这批循环不能直接替换正式移动。

本轮生成并冻结 **21 个实验 Animation**：三个源动作各七个对照版本。全部 `production_accepted=false`、默认关闭；它们没有加入正式 MM 查询库。Windows 与 Mac 的实际资源导入、原模型骨骼及服装兼容检查通过，但 **21/21 离线候选仍有质量失败**。

## 修整内容及保持条件

输入是上一轮冻结的 `source9_baseline / leg_reference_retime6`，仅使用前跑和左右快侧移。详见 [原循环候选](mixamo-loop-candidates.md) 和 [整个动作包评估](mixamo-loop-feasibility.md)。21 个派生资源仍只覆盖三个作者动作，不补足启动、停止、移动中急转、后退和斜向移动的完整覆盖。

每个源分别生成：密集原曲线 `raw_dense`；20/35 ms 周期平滑；20/35 ms 平滑加接触窗口内获取/释放；20/35 ms 平滑加提前获取、延后释放并保留脚掌滚动。平滑修改的是踝端点、脚全球旋转和脚趾局部旋转，保留原髋部旋转及摆动，公开相对原曲线的误差。它会改变动作幅度，不能只按最大角步长下降判定更好。

原 87 骨模型及固定骨长保留，没有拉长腿、降低正式玩家的 6 m/s 移动速度或增加物理 Root 轨道。三个实际周期仍为 `.3289238729 / .3235397203 / .3235396667 s`；前跑使用84个均匀区间，侧移各80个，实际频率 ≥240 Hz，原关键帧严格落在网格中。增加采样数本身不会降低原动作角速度。

源动作的急剧脚掌翻转已经出现在原 FBX 中。侧移还包含约71–82度的髋部转向；强制固定髋部方向会改变腿根位置，使部分原落脚目标超出腿长可达范围。保留髋部转向需要在下半身处理完整结束后恢复上半身边界，再执行原瞄准和服装同步。

## 离线质量结果

每个版本在60/30/144 Hz、四个采样起始相位、三个连续周期下测量。以下角步长包含九个 lower 骨；接触跨度位移和最低脚底代理 Y 取三种频率的最大/最小值。旧门限保持60 Hz `.35 rad`、30 Hz `.7 rad`、接触跨度 `.03 m`。144 Hz 记录角变化而不新增比例缩放的角门限。

| 源 / 版本 | 60 Hz最大角步长 rad | 30 Hz最大角步长 rad | 最大接触跨度位移 m | 最低heel/ball代理Y m |
|---|---:|---:|---:|---:|
| running.fbx / raw_dense | 0.720458 | 1.024855 | 0.091917 | -0.020313 |
| running.fbx / smooth35 | 0.322559 | 0.618367 | 0.145067 | -0.001542 |
| running.fbx / smooth35_anticipatory_roll_contact | 1.238509 | 1.468498 | 0.053719 | -0.088939 |
| left strafe.fbx / raw_dense | 0.741877 | 0.948495 | 0.106611 | -0.028330 |
| left strafe.fbx / smooth35 | 0.404786 | 0.615654 | 0.170885 | -0.007959 |
| left strafe.fbx / smooth35_anticipatory_roll_contact | 1.337638 | 1.613803 | 0.096492 | -0.078031 |
| right strafe.fbx / raw_dense | 0.701980 | 0.971043 | 0.058903 | -0.027580 |
| right strafe.fbx / smooth35 | 0.704327 | 0.798246 | 0.119226 | -0.009794 |
| right strafe.fbx / smooth35_anticipatory_roll_contact | 1.209117 | 1.453005 | 0.049105 | -0.084336 |

跑步35 ms版本降低了角步长，但接触跨度位移达到约14.5 cm。普通锁脚版本在满权阶段的代理 anchor 误差可小于0.753 mm，获取和释放过程仍有较大跳变；这个满权数字来自离线报告，不能代表整个接触窗口。

提前获取的版本保留整个原接触掩码，没有通过缩短接触时间规避检查。它锁定单个 heel/ball 点并保留脚掌滚动，但另一代理点满权时可入地7.8–9.1 cm，整体最深约9.2 cm。这是失败，不能用锁定点误差小证明整只脚正常。

接触标签来自源 ToeBase/Toe_End 高度和世界XZ速度推断，**不是作者标记，也不是目标鞋网格碰撞**。目标heel/ball代理均在 foot 骨局部：`[0,-.085,-.065] / [0,-.085,.11]`；toe 骨只提供独立动画轨。窗口 anchor 只在开始时取一次，跨周期沿同一线性6 m/s轨迹平移，方向来自源FBX净位移：前跑+Z、左文件+X、右文件−X。所有合成 Root 位移都只用于测量，未写入玩家移动。

[冻结离线报告](../.tools/mixamo-loop-refined/report.json) 完整保留所有失败、reach clamp、骨盆调整、两脚地面高度和源曲线误差；[生成器](../tools/mixamo_loop_refine.py) 与 [历史说明](../.tools/mixamo-loop-refined/README.md) 可复查。

## Windows / Mac 实际资源检查

[验证入口](../tools/verify_mixamo_loops_refined.gd) 延后加载原 Avatar 和独立 AnimationPlayer，实际采样 `.tres`；再将导入 Skeleton 的 FK 与 JSON 关键帧插值独立比较。126 cases = 21资源 × rest/生产瞄准姿势上下文 × 60/30/144 Hz，每个case三个周期。控制器和Root保持不动，生产瞄准上下文调用的是原 Avatar 动画，**不是实际输入或移动测试**。

| 平台 / provider | 结构检查数 | 结构失败 | cases | 保留质量问题条目 |
|---|---:|---:|---:|---:|
| Windows / native | 2000532 | 0 | 126 | 294 |
| Windows / portable | 2000531 | 0 | 126 | 294 |
| Mac M2 Max ARM64 / native | 2000532 | 0 | 126 | 294 |
| Mac M2 Max ARM64 / portable | 2000531 | 0 | 126 | 294 |

四路最终V2 `.log` 与 `.log.stdout` 均归档且无ERROR/WARNING/Unicode诊断；Mac两个新导入pass的双日志也干净。原上身全球位置误差最大约4.24e−7 m、basis约5.24e−7，枪口位置误差0，独立JSON FK误差约2.21e−7 m，固定骨长误差小于9e−8 m。服装被改动的骨骼跟随身体，其他局部姿势保持。

294是多个case的多个诊断问题条目，不能当作294个独立动作。引擎测的是整个推断接触窗口，包括获取/释放；它未单独验证离线满权亚毫米列。根本质量失败仍保留。

V1采样器用相邻离散接触标签AND，会提前一个密集区间结束接触。独立审查发现后，V2改为完整窗口和跨周期判断，并用原30 Hz源关键帧最近邻标签独立核对，另覆盖右脚跨首尾回归。动作资源字节未变；V1脚底测量直接使用windows，所以旧质量统计未被缩小，但V1不作为最终标签正确性证据。

原生查询继续访问**原数据库每武器234行**；这些实验循环没有成为native MM候选。兼容检查不代表新库选帧、转向过渡或玩家手感已通过。

证据：[Windows Native V2](../shots/mixamo-loop-refined-native-v2.json)、[Windows portable V2](../shots/mixamo-loop-refined-portable-v2.json)、[Mac Native V2](../shots/mac-mixamo-loops-refined-v2/output/mixamo-loop-refined-native.json)、[Mac portable V2](../shots/mac-mixamo-loops-refined-v2/output/mixamo-loop-refined-portable.json)。

## 连续画面对照

三段1280×720、120帧、60 Hz、2秒的姿势实验室视频，左为密集原曲线，中为35 ms平滑，右为35 ms提前落脚约束。采用同一原角色、衣服和武器，质量失败仍存在。

- [跑步](../shots/mixamo-loop-refined-running-gpu-v1/comparison.mp4)
- [左快侧移](../shots/mixamo-loop-refined-left_strafe-gpu-v1/comparison.mp4)
- [右快侧移](../shots/mixamo-loop-refined-right_strafe-gpu-v1/comparison.mp4)

每路GPU诊断253检查/0结构失败，并对四个取样姿态做独立身体隐藏前后像素对比，证明身体及左右脚确实绘制。该证明没有覆盖所有120帧的网格变形；固定60 Hz图像序列也不证明实际144/30 FPS手感、性能、真实运动、导出包或MM选帧。视频采于V1标签修正前，但渲染只读取时间和姿势，不读取该contact字段，曲线字节与最终V2一致。

## 数据身份与接入前提

`loops.json`：5,268,332 bytes，SHA-256 `e3890bf374465be9b4c9b1db04379f5007f4ef13498dcc7f1f07294b160a64d0`。
离线report：402,529 bytes，SHA-256 `bbc07b16b8564a42d589efb231f50d93f1cf79c692f5486c85a94c96ab988aa5`。
61个原包、模型、旧实验和生产输入的SHA/size/mtime在生成前后相同；v5到v6的21个TRES和loops.json共22曲线文件字节一致，v6只补充入地失败报告。

最终Mac V2是独立30文件QA overlay：1,605,030 bytes，SHA-256 `3f54fe9170d989ad2725d7ceef8a25b7a16e804e4c6d52c735a4e55d1e4dcfe5`，保留原模型、数据库和两份ARM64原生扩展身份。它没有导出游戏或修改参考工程。

未来接新动作库前，要隔离目前static matcher数据与按武器命名的native缓存，保持原 Avatar 和候选 Avatar 同场景互不污染。本轮只完成 [暂存接入提案](../.tools/mm-dataset-proposal/README.md)，正式两个matcher及原数据库未改。提案未运行Godot，仍有编译、启动读盘成本和实际COW内存行为待验证；它严格拒绝非均匀时钟，不能直接接收这些非整周期fps的精确重定时资源。不得把提案或原库查询次数算作新Mixamo数据库接入成功。

要进入正式移动，仍需可信的鞋底接触定义、完整过渡动作、运动中骨盆和上身补偿，随后在真实main scene/Input路径下对比144/30 FPS和time_scale压力，并验证PC导出包。当前没有接受任何修整候选。
