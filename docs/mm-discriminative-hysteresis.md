# MM 过渡比例判据实验

`--mm-discriminative-hysteresis` 默认关闭。这个实验保留当前最近邻搜索及其完整成本，仅在判断是否切换动作时，排除当前武器候选库中所有行都完全相同的特征维度。它不是完整游戏的输入、画面或手感验收。

## 问题与范围

现有 63D 库包含 7 个预测朝向分量，索引为 `44,47,50,53,56,59,62`。当前 7 个武器各有 234 行；这些分量在每个武器库中都为零。查询的朝向可以非零，所以这一组维度给每个候选加上同一项成本 `C`。这不改变数学上的最近邻排名，却改变原来的比例门槛：

```
完整候选成本 = B + C
完整续播成本 = T + C
原判据：B + C < 0.72 × (T + C)
等价：  B < 0.72 × T - 0.28 × C
```

原始数据测量中，预测朝向带来的公共成本约为 `20.74411835 × theta²`，其中 `theta` 用弧度表示。180° 时约为 `204.73624`。例如 shooter 的 run 第 0 帧作为查询、run 第 6 帧作为续播时，区分成本分别为 `0` 和约 `77.615953`。完整成本的原比例判断为假，去除公共项后的比例判断为真。这个例子发生在同一循环内，不涉及新增动作。

代码不会永久屏蔽这一组朝向索引。它扫描每个当前武器库，逐维计算实际特征值的精确最小值和最大值；只有两者完全相等才作为公共项。当前真实固定维度还包括预测时间为零的位置分量 `42,43`。以后导入有变化的转向朝向，该维度会自动保留。

## 实现契约

只修改 `scripts/animation/ink_motion_matcher.gd`。开启实验时先直接求和公共成本。公共成本非零时，对搜索返回的最佳行和续播行分别重新累加非固定维度的加权平方差，再使用原来的 `0.72` 比例。没有从大数总成本中减去公共项。

公共成本严格等于零时，完整保留原 provider 的成本与比例结果，并标记 `zero_common_passthrough`。不使用 epsilon；以后没有固定维度的库也会自然进入这条路径。因为 Native 原成本使用 Float32，而新的两行重算使用 GDScript 的双精度，即使数学公共成本为零，换一种算术也可能在比例边界改变结果。这个透传避免了没有公共项需要修正时改变已有行为。

独立 review 提供的 shooter 边界查询是 `q = Float32(0.132508129546182 × row145 + 0.867491870453818 × row151)`，续播 row151、最近 row161，固定维度的查询均为零。Windows Native 完整成本约为 `B=0.9812245965003967`、`T=1.3628119230270386`，原比例为假；双精度重算约为 `B=0.9812246209543687`、`T=1.3628120989382946`，比例为真。新版代码在这个零公共成本案例中保持 Windows provider 的假值。Mac ARM64 原成本有不同的舍入边界，原比例为真；新版在 Mac 保持真值。透传保留各平台已有行为，不要求不同 provider 或平台逐位相同。

完整搜索、最佳 pose、完整 `cost` / `continuation_cost`、Native API、归一化、查询间隔、播放速率、时钟、0.14 秒冷却、0.16 秒同循环距离门槛，以及跨动作的突然输入旁路均保留。开关关闭时仍执行原始完整成本比例算术，额外的决策成本重算不会执行。

Native API 不可用时仍由原 `configure` 路径返回失败；Native 查询失败仍保留原来的可见错误和无效总成本，实验不会静默改用脚本搜索。非有限总成本不会进入新的决策重算。这个修改不补偿无效库或无效归一化。

`debug_state().discriminative_hysteresis` 包含：

- 开关、决策是否评估、零公共项是否透传、当前固定与非固定维度、最佳与续播 pose。
- 原完整成本、直接求和的决策成本，以及单独直接求和的公共成本。
- `legacy_improved`、`new_improved`，原冷却、距离和输入旁路状态。
- 两个比例判据不同的查询数量，以及在当前查询状态下最终切换门槛不同的数量、增加或抑制的切换数量。
- `last_query_weapon` 标明最后一次实际搜索的武器；换武器时清空，并将决策快照标记无效，避免把旧查询解释为新武器的数据。

这些计数比较同一个当前查询状态的两个决策。由于一次新增切换会改变后续播放状态，它们不等同于两次独立完整游戏运行的因果差值。实际 ON/OFF 游戏仍需各自记录和比较。

## 独立诊断工具

`tools/verify_mm_discriminative_hysteresis.gd` 是一个轻量 `SceneTree` 入口，在树初始化后的 deferred 回调中加载并挂载 `tools/mm_discriminative_hysteresis_fixture.gd` Node helper。入口不静态预加载 Avatar、matcher 或扩展资源；helper 不创建第二个 `SceneTree`。这是按真实链验证技能要求调整的 scratch 启动方式。

Helper 使用真实 87 骨骼和真实 63D 特征库。Fixture 只替换查询构造函数，portable 的精确搜索与 Native `MMAnimationLibrary.query_normalized_vector` 均调用实际实现；它不会伪造候选或 Native 计数。

Native 完整成本另有独立的 Float32 参考实现。external `_compute_feature_costs` 使用 `float delta`、`float pose_cost`，按维度 `0..62` 顺序累加。Helper 的默认 `uncontracted` 模型用可复用的 `PackedFloat32Array` 单元素槽，在差值、平方、乘权重、累加后逐次舍入，对应实测 Windows 构建。显式 `--native-f32-model=arm64-fma` 模型在差值、平方后舍入，随后把 `square × weight + cost` 一次舍入，对应实际 Mac ARM64 反汇编中的 `fsub/fmul/fmadd`。模型不能由返回成本反推，也不会按 OS 自动猜测。两种模式都严格比较成本，不增加容差。Native 的候选库顺序用实际 `_native_to_source` 映射，独立完整扫描也按该顺序处理相等成本。

双精度、trajectory-first 的数学参考仍完整保留，用于验证数学最近候选及直接求和的判据成本；JSON 额外记录 provider 相对双精度及 Float32 参考的差值。原 `_near` 容差没有放宽。开启与关闭实验的 provider 完整成本仍要求严格相等。这两种参考明确对应不同的已有算术，不能把其小幅差异归因于新开关。

覆盖 7 武器的 0°、±45°、±90°、±180° 查询；检查 ON/OFF 完整搜索结果和完整成本严格一致，另用不剪枝的标量求和验证成本。还覆盖同循环相位校正、跨循环、冷却阻挡、距离边界、循环首尾最短距离、原输入旁路、时钟/速率、远端查询间隔及禁用匹配。Native 模式逐次检查真实查询计数增长与实际访问 234 行。保留原动态固定维度检查：临时改变内存中的一个值，并在返回前恢复，不写源特征文件。

新增 7 武器的零公共成本边界对照，要求 ON/OFF 的判据、切换、动作、相位及速率完全相同。另在每个武器库的一行中临时改变所有现有固定分量，构成真实 63D/234 行、没有固定维度的内存派生库；两个 Native 诊断实例通过原真实构建函数分别配置该库，再进行实际 paired query，验证相同透传行为。测试后恢复所有内存值和这两个实例的原库。共享 Native 缓存、实际源文件、CPP/DLL 字节均不修改。派生库只用于诊断，不是新的制作内容或正式动作库。

由主代理使用唯一串行引擎包装器运行：

```powershell
& H:/GDP/inkwave/splatink/tools/run_godot.ps1 -GodotArgs @(
  '--headless', '--path', 'H:/GDP/inkwave/splatink',
  '--script', 'res://tools/verify_mm_discriminative_hysteresis.gd',
  '--log-file', 'H:/GDP/inkwave/splatink/shots/mm-discriminative-portable.log',
  '--', '--output=res://shots/mm-discriminative-portable.json'
)
```

Native 模式在 `--` 后加 `--native-locomotion-mm`，并使用独立的 native JSON 和日志路径；当前 Mac 冻结构建另加 `--native-f32-model=arm64-fma`。每次诊断会自行创建实验开启与关闭两个 matcher。真实游戏对照另用 `--mm-discriminative-hysteresis` 控制整个运行，不依赖 fixture 的属性覆盖。

## 验证状态与限制

2026-10-04，主代理串行完成 Windows 和独立 Mac 副本的 V3 查询诊断：

| 平台 / Provider | 明确的 Native 算术模型 | 检查 | 失败 | paired 实际查询 | log / stdout |
| --- | --- | ---: | ---: | ---: | --- |
| Windows Native | uncontracted | 2421 | 0 | 224 | 干净 |
| Windows Portable | 不适用 | 2166 | 0 | 224 | 干净 |
| Mac M2 Max ARM64 Native | arm64-fma | 2421 | 0 | 224 | 干净 |
| Mac M2 Max ARM64 Portable | 不适用 | 2166 | 0 | 224 | 干净 |

Windows 报告为 `shots/mm-discriminative-{native,portable}-v3.json`，Mac 为 `shots/mac-mm-hysteresis-v3/output/mm-discriminative-{native,portable}.json`。每路保留 `.log/.log.stdout`；Mac 还保留两次全新 import 的两份日志。全部检查完整 OFF/ON 搜索及完整成本相等，Native 另严格验证独立 Float32 成本、最近候选及实际每次访问234行。Mac 属于 headless 查询验收，没有代替 GPU 输入或导出包体验验收。

零公共项 shooter 最近 row161；Windows Native 的 OFF/ON 判据都为假，Mac Native 与 portable 各自的 OFF/ON 都为真。每个平台均保持已有结果，ON 的 `predicate_changes/transition_changes` 为零。没有固定维度的派生库也保持透传，结束后恢复原内存及实例库。换武器归属、varying/tiny-varying、冷却、距离、时钟、播放速率和真实 Native API 检查均保留。

非零公共项修正仍实际生效：shooter 180° fixture 最佳 row145，公共成本约 `204.736235545064`，OFF 不切换、ON 切换；区分成本为 `0/77.6159531176477`。这是受控查询，不能直接说明真实游戏更顺滑。

### 保存的失败和参考模型来源

初轮 portable 1710/0、196 paired queries，晚加载 portable 1710/0，日志干净。晚加载 Native 首次1809项检查有14项失败，均为±45°完整续播成本对双精度参考的差异，保留 `shots/mm-discriminative-native-late.*`。shooter 例为 `90.4119567871094` 对 `90.4119678392142`。独立分步 Float32 模型逐位复核196/196成本一致。Windows V2随后 Native2420/0、portable2165/0，各224 paired queries；其报告仍保留。

Mac V2 portable2165/0；Native2420项检查有105项失败，保留 `shots/mac-mm-hysteresis/mm-discriminative-native.*`。其中104项是 Windows 分步舍入参考与 Mac 实际融合乘加不同，另一项是 Windows 专用的零公共项假值断言。完整 OFF/ON 成本和候选相等，没有因新开关改变完整查询。

模型选择来自实际 ARM64 编译对象的只读反汇编，而非放宽误差或拟合 provider 值：`fsub` 后 `fmul` 生成平方，`fmadd` 将权重乘法和累加一次舍入。实际源 SHA-256 `d0960038d198416332c920f8cad1bb4c2d61d6605a797e467a0a1e1acd67d9ae`，编译对象 `7521592a81b92af17c2711c4a8d66394ecdb4dc11dbe8d6aaedd2e20c0aabb3e`；原构建与隔离 stage 的 debug dylib 均为 `542b4df0b2fff8479d4a112498704e767901e955e979fe9db38be26b82aa878c`。反汇编及 SHA 记录保存于 `.tools/mm-discriminative/mac-arm64-cost-disassembly.txt`、`mac-fma-input-sha256.txt`。

独立 `.tools/mm-discriminative/arm64-fma-audit.py` 从原 Float32 特征与声明的 query recipe 重新生成查询。FMA 模型与 Mac 最佳/续播成本224/224逐位一致，完整234行独立扫描的最佳行112/112一致。Fraction精确 RN-even 单舍入复核14,112个选中行运算项，无模型二次舍入差异；rounder另能检出人为二次舍入反例。分步模型224/224匹配保存的 Windows reference，与 Mac有104项不同。报告为同目录 `report.json`。这只证明该冻结输入集，不能推广为任意未来查询、跨平台逐位一致或观感改善。

V3 fixture 明确声明模型，原 `_near` 阈值不变；生产 matcher 与 V2完全相同。四文件 V2归档10958bytes、SHA `05571ce68c5c51578b5cd09cb8706a39156a142fef19b59a88871fbfa60cd7aa`；V3归档11224bytes、SHA `60f492738ccf9c41694deab84143557da5706f30d1051b78afeee9ac090055eb`，保存于 `.tools/mm-discriminative/20261004-candidate-{v2,v3}.tar.gz` 和各自 manifest。V3 Mac 副本为 `20261004-mm-hysteresis-v3`；旧 V2副本和失败记录未覆盖。Native源码、二进制及原特征库未修改。

### 实际 GPU 输入对照

真实 `main.tscn` 经 `Input.parse_input_event` 进入生产控制链，使用原87骨 Avatar、Native MM、原 FootPlant，未注入姿势或物理位置。Windows Godot4.7.1、D3D12 Mobile、RTX5090、1280×720，低画质、七个 idle bots、lower呈现、关闭同步截图。普通序列12项检查，扩展鼠标序列16项检查；以下十路均零失败、观测finite、`.log/.log.stdout`干净。

| cap / 输入 / 开关 | render样本 | 查询 | 过渡总数 | 比例差异 / 同状态过渡差异 | grounded最大相邻render腿变化 rad | 完整接触FK最大误差 m |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 144 / 普通 / OFF | 1843 | 257 | 32 | 0 / 0 | .306517243 | .0108224945 |
| 144 / 普通 / ON | 1838 | 257 | 32 | 4 / 0 | .300639242 | .0108224945 |
| 30 / 普通 / OFF | 384 | 257 | 31 | 0 / 0 | .660782039 | .0120152039 |
| 30 / 普通 / ON | 384 | 257 | 31 | 5 / 0 | .659228742 | .0120152039 |
| 144 / 六倍时间 / OFF | 307 | 188 | 38 | 0 / 0 | 1.062557697 | .0003368616 |
| 144 / 六倍时间 / ON | 308 | 188 | 42 | 8 / 2 | 1.062557697 | .0000460691 |
| 144 / 扩展鼠标 / OFF | 2591 | 341 | 43 | 0 / 0 | .347807527 | .0108224945 |
| 144 / 扩展鼠标 / ON | 2569 | 341 | 43 | 7 / 1 | .347807527 | .0108224945 |
| 30 / 扩展鼠标 / OFF | 540 | 341 | 42 | 0 / 0 | .693752289 | .0108051989 |
| 30 / 扩展鼠标 / ON | 540 | 341 | 42 | 8 / 1 | .775838017 | .0120152039 |

汇总为 `shots/pc-hysteresis-real-summary-v2.json`，原始文件名在各条 `source_file` 中。普通144 OFF在C0透传修正前运行，关闭路径与最终代码相同；其余V2为最终生产代码。早期144 ON V1仍保留，但不混入本表。六倍时间只是异常值/切换压力，不能作自然运动依据。

比例差异与同状态过渡差异比较**一次 ON 查询的同一状态**下两个门槛，不是两个独立运行的总过渡数相减；额外切换会改变后续状态。普通144/30没有实际门槛差异；鼠标急转每路ON出现一次。144扩展最大变化没有减少，30扩展由`.69375`增至`.77584rad`，不支持接受默认开启。各次输入落点/render相位可能略有差异，单次最大值也不能全部归因于开关。

实验继续默认OFF。检查通过证明查询契约及可观测切换行为，未证明整体locomotion自然、完整性能改善或导出包体验通过。游戏root仍60Hz、支撑脚与瞄准链的呈现问题另见 [locomotion-real-chain.md](locomotion-real-chain.md)。当前正式库没有新增作者制作的起步、急停、跑动pivot；本实验没有接入Mixamo/Motorica数据，或改变物理root。循环素材评估见 [mixamo-loop-feasibility.md](mixamo-loop-feasibility.md)。
