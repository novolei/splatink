# Mac headless 退出诊断

2026-10-04。仅 QA 诊断；未修改生产音频、Motion Matching 源码/DLL 或任何 Mini Tanks 内容。

普通 Mac M2 Max Godot 4.7.1 的实际 Game 返回菜单后退出，stdout 报 `2 ObjectDB instances were leaked at exit`。Windows 同场景没有该警告。此前真实 LAN 逻辑通过，但受这个退出警告影响，不能称完全清洁通过。独立包内 GPU 运行没有重现该警告。

Root 使用 `tools/diagnose_menu_shutdown.gd`：原 Game、QuietBots、Tidewater 实战进入 playing、返回真实菜单；不打开 ENet，不读写玩家存档。所有 Mac 引擎调用共用 `splatink-build/engine.lock`。

| 普通 headless 对照 | 扩展/原生查询 | 提前释放 | 退出 stdout |
|---|---|---|---|
| 原基线 | 扩展加载、MM ON | 无 | 2 ObjectDB 警告 |
| 仅关 MM | 扩展加载、MM OFF | 无 | 同样 2 ObjectDB 警告 |
| 全新副本禁用扩展 | ClassDB 无 MMAnimationLibrary、MM OFF | 无 | 同样 2 ObjectDB 警告 |
| 禁用扩展、提前清音频 | 同上 | 停全部播放器、stream=null、kill Tween、清流缓存、等两帧 | 无 ObjectDB 警告 |
| 原扩展与 MM ON、提前清音频 | 原生 ON | 同上 | 无 ObjectDB 警告 |
| 禁用扩展、提前释放 Game | 无扩展、MM OFF | queue_free Game、等两帧 | 仍有 2 ObjectDB 警告 |

每组都进入 playing/真实 menu，报告孤立 Node 数为零。禁扩展副本从旧 PC QA stage 独立复制，排除 `.godot` 与唯一 `.gdextension`，添加 addon `.gdignore`，两次全新导入均干净。没有改原快照的扩展映射。报告显式记录 `native_extension_present=false`，不能把“关 MM 标志”等同于“不加载扩展”。

音频隔离使退出警告消失，因果范围已缩小到音频资源/播放/Tween 释放时序；仍未识别警告中两个对象的确切类型。提前清音频同时改变多项所有权，不能把数量二直接认定为 WAV+Playback。清音频保留 Game；仅提前销毁 Game 后对象数从 6901 降到 2581，却未消除警告。

原生 MM 实例、扩展加载以及网络都不是复现这条 ObjectDB 警告所必需的条件；不能用它作为插件不适合的证据。headless 报告 `headless_gpu_instance_present=false`；`InkStage` 仅在非 headless 且有 RenderingDevice 时创建 `InkPaintGPU`，因此此前猜测的 InkPaintGPU/Texture2DRD 二对象链不适用于这些运行。

原扩展 verbose 运行另有 170 个 orphan StringNames，大量未实例化类名也为 total=2，与 godot-cpp 静态类名及 binding callback map 残留相符；dylib 卸载时序尚未证明。它们不等同于上述两个 ObjectDB 实例，不能据此改 native 初始化等级或批量清缓存。

复现：`tools/run_macos_menu_shutdown.sh <QA-root> <verbose:on|off> <native:on|off> <none|audio|game>`。默认保持历史 ordinary/native ON；隔离参数仅改 QA 脚本。原始退出警告记录保留，不用音频隔离结果覆盖原实际 LAN 验收。
