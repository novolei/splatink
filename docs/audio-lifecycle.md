# 音频生命周期候选

2026-10-04。此改动只处理 `InkAudio` 自己拥有的资源；具体两个退出残留对象的类型尚未得到引擎证明。

改动前已实测的隔离事实：Mac Godot 4.7.1 的 headless 真实 Game 从 playing 返回 menu 后退出，重复报告两个 ObjectDB 残留；native MM 关闭且扩展不存在时仍能复现。提前释放 Game 并等待两帧仍报告相同警告。QA 中停止 81 个播放器、解除其 stream、清音乐 Tween 和流缓存后等待两帧，native MM 开启和关闭均不再报告。此证据支持继续检查音频所有权与退出时序，不证明残留对象类别或具体根因。

`InkAudio._exit_tree()` 现在调用幂等的 `shutdown()`：停止所有播放器并解除 stream，kill 并解除音乐 Tween，清掉 pending、loop 索引、池句柄、流缓存与音乐元数据，清理 Boss director 的战斗状态与 owner 引用。播放器节点继续由原父子所有权销毁，退出递归过程中不手动 remove/free 子节点。`shutdown()` 对这个实例是终止操作；后来的播放、事件与暂停入口不会重新建立播放器池。平常 `clear_gameplay()` 继续保留池和菜单音乐，因此换曲、暂停与菜单操作没有每帧重建。

候选未改全局 quit，也未添加人为退出等待。最小真实菜单链的 MM 开启/关闭各一次没有关闭警告，但三轮压力链的 Mac `normal`、`queue-free` 和 `pool` 均仍报告两个 ObjectDB 对象；普通退出尚未通过完整验收，不能把最小链或带等待的 QA drain 成功当作普遍修复。

## 串行验证

由 Root 串行运行，同一工程只允许一个 Godot 进程。下面的 `$Godot` 应替换为当前批准的 Godot 4.7.1 可执行文件路径，Mac 可用同等参数在 QA 副本运行。

```powershell
& $Godot --headless --path H:\GDP\inkwave\splatink --script res://tools/verify_audio_lifecycle.gd -- --exit-mode=normal --output=res://shots/audio-lifecycle-normal.json
& $Godot --headless --path H:\GDP\inkwave\splatink --script res://tools/verify_audio_lifecycle.gd -- --exit-mode=queue-free --output=res://shots/audio-lifecycle-queue-free.json
& $Godot --headless --path H:\GDP\inkwave\splatink --script res://tools/verify_audio_lifecycle.gd -- --exit-mode=pool --output=res://shots/audio-lifecycle-pool.json
```

正常模式是完整真实 Game：playing → 反复换曲、声音、loop、暂停/恢复、后台/前台 → menu → 普通 `SceneTree.quit()`。它没有调用人工 drain 或 shutdown，也没有在清理之后等待帧。默认三轮；`--cycles=12` 增加复用检查。正常菜单等待默认 1.2 秒让既有音乐淡入完成，`--exit-delay=0` 可覆盖仍在淡入时直接关闭。

`queue-free` 模式仅通过原父子生命周期释放整个 Game，然后等待两帧作时序对照。`pool` 模式从树中移除 Audio，观察自动 `_exit_tree` 的同步清理，再检查重复 shutdown 和晚到播放不会恢复终止实例；播放器节点最后由父子所有权销毁。

fixture 的 JSON 只保存标量、资源 ID 和通过 WeakRef 读取的引用计数，观察代码不跨帧保留 AudioStream/Tween/Director 的强引用。读取引用计数的函数会暂时持有观察对象，因此计数用于记录，不断言精确阈值。只读观察私有池用于追踪 transient stream，没有修改池、缓存或 stream 字段的 QA drain。检查覆盖 81 个播放器复用、旧音乐副本及停止 loop 副本释放、菜单音量/音乐功能、清理幂等与 director/Tween 释放。

首版 Windows normal fixture 的 90 项检查中，只有最后一个 `background loop lifecycle_2_menu` 的 WAV WeakRef 在退出前仍存活（观察时引用数 2）；退出快照所有 stream/cache/Tween/director 清零，进程未报告 ObjectDB 警告。已只读定位到同 commit `a13da4f` 的引擎源码：`AudioStreamPlayer3D::play()` 将 playback 存到 `setplayback`（`scene/3d/audio_stream_player_3d.cpp:649–655`）；同帧 `stop()` 只取消 `setplay` 并清 internal playback 列表，没有解除该引用（671–674）；换 stream 也没有清它（599–601）。该 playback 强持 WAV 的 `base`（`scene/resources/audio_stream_wav.cpp:611–614`）。随后真正物理处理会提交并解除 `setplayback`（289–295），或者播放器复用/销毁时释放。首版 fixture 在同一帧启动并停止每个 loop，最后一份没有下一次复用；源码与最后唯一一份存活的结果吻合，尚未声称它就是原始 Mac 的两个对象。

修正版普通 loop 先等待跨过实际物理处理再暂停/后台停止，仍严格要求每份 transient WeakRef 在菜单退出前消失。`queue-free`/`pool` 另外刻意制造同帧取消，观察 WAV 与 AudioStreamPlayback 的 WeakRef，仍严格要求两者在原播放器节点销毁后消失；不通过放宽引用计数、忽略最后条目或手动解除私有字段来通过测试。普通 quit 没有增加音频清理后的帧等待。`ink_audio.gd` 候选保持冻结 SHA256 `EE61DCD5F33E13D01A8E4CE37D064BF4F7701C1F60947CFCC566108DE3B85686`。

## 验收判据

- `AUDIO_LIFECYCLE` 的 `failures` 为空，playing/menu 均实际到达。
- 普通退出仍打印 `AUDIO_LIFECYCLE_EXIT`；应为 `shutdown=true`、`attached_streams=0`、`playing=0`、`pooled_handles=0`、`cached_streams=0`、`active_loops=0`、`pending=0`、`tween_owned=false`、`boss_owned=false`。该时点节点仍可有 81 个子播放器，随后场景树销毁它们。
- Mac 普通日志在实际进程关闭之后没有 `ObjectDB instances leaked`、`Leaked instance` 或资源仍在使用警告。程序 exit code 0 不能单独证明这个条件。
- 原复现 `tools/diagnose_menu_shutdown.gd` 必须不带 `--drain-audio`、不带 `--release-game` 再通过。MM 开启/关闭至少各做普通退出对照；扩展的 orphan StringName 问题按独立证据记录，不将它等同于 AudioStream 泄漏。
- Windows 完成普通/pool 对照后，单独正常渲染运行验证菜单音乐、淡入、音效、暂停与后台恢复可听行为。headless 只证明脚本/引用生命周期，不能确认可听输出。

## 已回收结果与版本边界

以下进程均由 Root 串行运行；实现代理仅静态读取代码和回收文件，没有运行 Godot 或 SSH。生产音频候选仍为上面的 `EE61DCD5…`；fixture v2 的 SHA256 为 `D93AB05648891FE487583A584B57B531EE40A5F5CF3773C94FB400CC96464EB4`。

| 平台与路径 | 脚本结果 | 进程结束后的日志 | 结论 |
| --- | --- | --- | --- |
| Windows 正常渲染，fixture v2 `normal` | 108 检查，0 failures；playing/menu 实际到达；退出资源所有权字段清零 | `.log` 与 `.log.stdout` 无 ERROR/WARNING/Unicode/泄漏记录 | 该次验证通过 |
| Windows headless，fixture v2 `pool` | 147 检查，0 failures；30 份 `must_release` 资源全部消失；同步退出资源所有权字段清零 | `.log` 与 `.log.stdout` 无 ERROR/WARNING/Unicode/泄漏记录 | 该次池退出验证通过 |
| Mac headless，原始菜单 diagnostic，native MM 开启、扩展存在 | `audio_drain_requested=false`、`game_release_requested=false`；playing/menu 实际到达，orphans=0 | `.log` 与 `.log.stdout` 均无警告或泄漏记录 | 原始最小链的该次候选运行通过 |
| Mac headless，原始菜单 diagnostic，native MM 关闭、扩展存在 | `native_mm_requested=false`；无 drain、无提前释放；playing/menu 实际到达，orphans=0 | `.log` 与 `.log.stdout` 均无警告或泄漏记录 | 原始最小链的该次 MM 关闭对照通过 |
| Mac headless，fixture v2 `normal`，native MM 开启、扩展存在 | 108 检查，0 failures；28 份 transient WAV 在菜单退出前全部消失；退出资源所有权字段清零 | `.log.stdout` 在退出快照后报告 **2 ObjectDB instances were leaked**；`.log` 没有收录这条关闭警告 | **普通退出仍未通过验收** |
| Mac headless，fixture v2 `queue-free` | 143 检查，0 failures；30 份 `must_release` 资源全部消失；同步退出资源所有权字段清零 | `.log.stdout` 仍报告 **2 ObjectDB instances were leaked**；`.log` 无该关闭警告 | **提前释放 Game 仍未通过关闭日志验收** |
| Mac headless，fixture v2 `pool` | 147 检查，0 failures；30 份 `must_release` 资源全部消失；同步退出资源所有权字段清零 | `.log.stdout` 仍报告 **2 ObjectDB instances were leaked**；`.log` 无该关闭警告 | **单独释放 Audio 池仍未通过关闭日志验收** |

可回审文件：Windows 的 `shots/pc-audio-lifecycle-normal-v2-gpu.json` / `pc-audio-lifecycle-pool-v2.json` 及各自 `.log`、`.log.stdout`；Mac 的 `shots/mac-audio-lifecycle/menu-shutdown-off.json` / `menu-shutdown-off-mmoff.json` 与 `audio-lifecycle-normal.json` / `audio-lifecycle-queue-free.json` / `audio-lifecycle-pool.json` 及各自 `.log`、`.log.stdout`。`menu-shutdown-off` 是历史文件名，该次 JSON 明确记录 `native_mm_requested=true`，不能从文件名推断 MM 关闭。只读取 Godot 日志文件会漏掉 Mac fixture 的关闭警告，必须检查回收的 stdout。Windows 渲染结果验证了播放状态、淡入和功能 API，尚无主观听音验收记录。

资源观察有明确时点：`normal` 的 `resource_references` 在普通 quit **之前**采样，28 份旧 transient 已消失，但当时的 18 个 `exit stream` 条目、8 个 cache 条目、Tween 与 director 仍存活；随后 `AUDIO_LIFECYCLE_EXIT` 才记录脚本所有权字段清零。不能把正常模式 JSON 当作退出之后全部 WeakRef 释放的证明。`queue-free` / `pool` 的报告则在销毁 Audio/Game 并等待两次 process frame 后采样：58 个观察条目中 57 个已消失，包括 28 份旧 transient、同帧取消的 WAV/Playback、缓存、Tween 与 director；尚有 **一个 `exit stream` / `AudioStreamWAV` 条目 alive=true、references_now=2、must_release=false**。这个结果在 Windows pool-v2 和 Mac 两模式均存在，Windows 关闭日志仍干净。

`exit stream` 是 `_watch_owned()` 按子播放器顺序建立的通用标签，没有直接记录 player bus 或 track。该活跃条目是最后一个 stream，依据 `InkAudio._setup()` 最后创建 Music 播放器及当前 track=`menu`，推断它是当时菜单音乐的 WAV 副本；该归属尚非 fixture 的显式身份字段。其 WeakRef 被读取时观察函数临时增加一份引用，剩余 owner 类型并未记录。不能声称“所有 watched WeakRefs 已死亡”，也不能将采样时仍存活的一份 WAV 直接认定为进程关闭后警告中的两个对象。

初始最小 overlay tar 是 `.tools/audio-lifecycle/20261004-audio-lifecycle-candidate.tar.gz`，9,108 字节、4 个文件，SHA256 `f0c1fb8b4f8e474e35df45da6e5aa419b9e039ebb243e8f2b574b1dea79bf32e`。该 Mac QA stage 随后单独覆盖了 fixture 为 v2 `D93AB056…`，生产音频候选没有改变。因此上述 v2 结果来自“初始候选 overlay + 后续 fixture v2 覆盖”；不能说初始 tar 本身已经包含 v2，也不能把两者称为同一个经过验证的 bundle。

## 尚未证明的后台播放链

同版本引擎源码还提供了比标量清零更深一层的退出候选。`AudioStreamPlayerInternal::stop_basic()` 调用 `AudioServer::stop_playback_stream()` 后清空播放器的 Ref（`scene/audio/audio_stream_player_internal.cpp:277–281`），但是服务端停止只把播放链标记为 `FADE_OUT_TO_DELETION`（`servers/audio/audio_server.cpp:1289–1319`）。下一次音频 mix 才移除链节点（534–538），主线程 cleanup 随后执行解除 playback 引用的析构函数（734–740、1630）。`AudioServer::finish()` 先停驱动并删除总线（1653–1662）；析构与 `SafeList` 析构只清已进入 graveyard 的节点，没有遍历仍在活动 head 的播放链（2142–2147；`core/templates/safe_list.h:203–242`）。主循环退出先删除 SceneTree，之后才关闭 AudioServer（`main/main.cpp:5253、5321–5323`）。

此次 Mac 使用 `--headless`，该参数同时选择 `headless` 显示驱动与 `Dummy` 音频驱动（`main/main.cpp:1500–1503`）；除非后续 CLI 显式覆盖音频驱动，不能将这次结果直接归因于 CoreAudio。Dummy 的音频线程按缓冲间隔混合（`servers/audio/audio_driver_dummy.cpp:56–73`），`finish()` 设置退出标记并等待线程退出，没有强制最后一次混合（135–145）。Windows 正常渲染与 Mac headless 的驱动条件不同；跨平台 AudioServer 的播放链与 Dummy 线程关闭调度仍是具体待验路径。

上述源码提供了“WAV 副本仍被 PlaybackWAV / 服务端活动链持有”的候选解释，但关闭日志没有给出残留类型，**尚未证明这就是本次两个对象**。queue-free / pool 的当前 `exit stream` 仍存活与该方向相容，不能称为所有流已死亡的反证；同样，Windows pool-v2 也观察到这一份 WAV 而关闭日志干净，故采样状态不能单独证明关闭泄漏。fixture v2 的 28 份旧 transient 及两份刻意同帧取消资源均已死亡，因此首版最后一份同帧取消 WAV 的解释是一个已单独修正的 fixture 时序问题，不能直接等同于这次 Mac 两个未知退出对象。正常模式的观察函数只保留 WeakRef、标量和 ID，短暂的资源局部变量均在无 await 的观察函数返回时解除；当前没有发现跨帧强引用资源的观察路径。

当前结论是候选同步释放了 `InkAudio` 的脚本所有权，但尚未彻底解决 Mac 压力链的退出警告。生产代码保持冻结。queue-free / pool 的脚本检查通过且关闭日志仍报警，已说明提前释放对应节点并等待两帧不足以满足该链的验收；下一步需要定位实际关闭对象及剩余 owner，再确定生产调用时机或引擎诊断。不能只靠数量相同、最小链一次通过或在全局 quit 增加等待宣称修复。
