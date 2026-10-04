# 液滴批量提交实验

状态：实验已实现并经真实 GPU 契约和八角色场景对照，默认关闭。当前数据不支持开启批量路径，也不改变权威 CPU 玩法判定。

`InkDropPool.batch_submission_enabled` 默认为 `false`。命令行 `--fx-drop-batch` 开启实验；省略该参数保留原逐实例 setter。两条路径使用同一份 Float32 积分、碰撞、海面、落地涂墨、回调、回收和随机顺序。容量、质量上限、射线额度以及 source exporter 均未改变。

批量路径在初始化时预分配 `capacity * 20` 个 Float32；每个实例依次写入 12 个 row-major Transform3D 分量、4 个裸线性 RGBA 分量和 4 个 custom 分量，然后在有活动液滴时提交一次完整 buffer。格式按 [Godot RenderingServer 官方说明](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-method-multimesh-set-buffer)。活动数量仍由 `visible_instance_count` 控制。脚本更新时不 resize 或 slice；引擎 PackedArray/RenderingServer 内部的复制成本需要实测，不宣称完全无分配。

原 setter 路径的 transform/color/custom 计算与调用保持原样。默认 2,048 槽时 scratch buffer 为 160 KiB；批量路径即使只有少量活动液滴也提交完整容量，因此低活动数量可能不划算。

## 计时口径

仅 `--profile-render` 启用新增计时。`InkFx.update_profile` 最小转发让现有根采集器记录：

| 报告字段 | 范围 |
| --- | --- |
| `fx_drops_integrate_cpu_ms` | packed 更新循环扣除单独计时的碰撞/落地；含 expiry、swap、分支和计时自身开销 |
| `fx_drops_collision_land_cpu_ms` | 实际 cast、命中/海面落地、涂墨与回调、接触退休 |
| `fx_drops_draw_submit_cpu_ms` | 半径/伸缩/投影/38Hz 摆动、basis、setter 或 buffer 写入与提交、visible count |
| `fx_drops_submission_calls` | 实际实例数据提交 API 数量：setter 为 `3 * active`，batch 为非空时 1，否则 0 |
| `fx_drops_batch_enabled` | 0 或 1 |
| `fx_drops_buffer_floats` | scratch buffer 的 Float32 数量 |

最后三项没有时间单位。原 `fx_drops_cpu_ms` 仍是外层整个 `drops.update`，还包含相机 uniform 写入等外围成本；不能把新增子项再次加到外层预算。没有扩大根任务的 7,200 样本窗口。

## 独立契约和微基准

`tests/drop_batch_contract.gd` 要求真实 rendering backend/window。Dummy renderer 的诊断包不构成实际 MultiMesh buffer 验证，读不到完整 native buffer 时测试失败。

契约复用原 `data/fx_drops.json` 的 8 段、379 帧 CPU 输入，并逐帧比较两条路径的全部粒子存储、槽序、随机消耗、探测/涂墨/落地事件，以及真实 native buffer 的活动字节、decoded transform/color/custom。额外覆盖三次射线预算、落地回调追加 beads、clear、运行中切换提交路径和 HDR/alpha 颜色。

微基准使用同一冻结 CPU 快照执行 `update(0, camera)`：活动数量 0/64/564/1,167/1,386/2,048，固定容量 2,048，每项交替先执行 setter 或 batch，8 次 warmup 后记录 40 次，两次提交之间不改变模拟状态，成对提交后让 renderer 前进一帧。结果写入 `shots/drop_batch_benchmark.json`，只比较 `draw_submit_*_us` 和整个 update 的成本，不能据此直接换算整游戏 FPS。

根任务串行执行示例：

```powershell
& 'H:\GDP\inkwave\splatink\tools\run_godot.ps1' -GodotArgs @('--path','H:\GDP\inkwave\splatink','--rendering-method','mobile','--script','res://tests/drop_batch_contract.gd','--','--nonpersistent')
```

随后保持原门限分别在 OFF 和 `--fx-drop-batch` 下执行 `fx_drops_contract.gd`、`fx_sprites_contract.gd`、`fx_colors_contract.gd`、`fx_contract.gd`。这些已有 source fixtures 不修改、重新导出或放宽门限。

## 完整场景对照

独立契约通过后，以当前真实 GPU baseline 相同的质量/尺寸设置执行以下 OFF 命令；ON 只增加 `--fx-drop-batch` 并改变截图输出名。两次保持 native-MM 和 presentation 插值开关一致。重复交替顺序，观察真实帧长和相同活动数量下的液滴分项；渲染调度可能改变战斗/FX 轨迹，不能把整局差值完全归于提交方式。

```powershell
& 'H:\GDP\inkwave\splatink\tools\run_godot.ps1' --path 'H:\GDP\inkwave\splatink' --rendering-method mobile -- --autostart=240 --mode=boss --map=tidewater --time=dusk --autopilot --nonpersistent --benchmark-background --benchmark-fps=144 --benchmark-seed=37 --profile-render --capture=res://shots/pc-boss-drop-batch-off.png --capture-after=32
```

比较 `fps_average`（实际 frame count / render dt 总和）、`frame_p95_ms`、`playing_seconds`、活动液滴数量与上述 CPU 子项。不要使用 `engine_fps_monitor_average` 推断收益，也不要把只测主 viewport 的 GPU 时间当作完整 GPU 帧预算。

## 2026-10-04 实测

RTX 5090、D3D12 Forward Mobile 下，独立原生 buffer 契约47,527项通过、0失败；日志和 stdout 均无引擎错误。已有 source 契约在 OFF/ON 下分别通过：drops21,267、sprites33,911、FX49；颜色固定1,390项加当次随机提交包2,504/2,514项均通过。随机提交包数量不同没有减少固定断言。记录为 `shots/pc-drop-batch-contract.log`、`shots/drop_batch_benchmark.json` 和 `shots/pc-drop-batch-*-{off,on}.log`。

同一冻结快照的 draw submit 中位/p95（µs）如下。两路径活动数据相同，提交顺序交替；它只衡量该调用，不是游戏帧率。

| 活动液滴 | setter | batch |
| --- | --- | --- |
| 64 | 61 / 86 | 81 / 111 |
| 564 | 390 / 575 | 364 / 697 |
| 1,167 | 785 / 1,099 | 747 / 1,148 |
| 1,386 | 922 / 1,331 | 881 / 1,390 |
| 2,048 | 1,336 / 2,050 | 1,308 / 1,897 |

完整八角色 Boss 场景为1280×720/high、4096图集、native-MM开启、pose presentation关闭、seed37、144上限、`autostart=240`、Tidewater傍晚，各24.7833秒实战。OFF/ON实际平均130.89/113.43 FPS、帧长p95 11.11/16.67ms；draw submit中位/p95 .337/.739 与 .411/.843ms，整个 drops update中位/p95 .601/1.165 与 .703/1.356ms。两份日志及stdout干净，原生查询器均为8。记录为 `shots/pc-boss-drop-batch-{off,on}.json/.log`。

该场景中活动液滴中位468/517、p95 1,014/1,106，两局轨迹并非完全相同，不能把整局差值全部归因于 buffer 提交。但微基准和场景对照都没有足够证据支持默认启用；继续保留原 setter。这个窗口的配置也不同于旧 `autostart=180` 基准，不用跨窗口 FPS 差宣称整体优化收益。
