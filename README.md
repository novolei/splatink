# Splatink 原生开发项目

Godot 4.7.1 项目，当前优先 Windows/macOS 的画面、操作与联机体验。Android 后续处理，iOS 工作已暂停。当前是持续打磨中的开发版本，不代表所有像素、动画或交互已经完成 100% 对照。

## 运行

本目录是独立原生项目仓库。克隆前安装 Git LFS，克隆后执行 `git lfs pull`，确保模型、音频、地图和原生插件库已经下载。Godot 游戏运行所需资源均保存在本仓库；重新从网页生成资源的开发工具另外需要原 INKWAVE 网页参考工程。

用 Godot 打开本目录的 `project.godot`，运行主场景 `scenes/main.tscn`。自动生成的导入缓存保留在 `.godot`，不需要放进版本库。

PC 默认控制：WASD/方向键移动，鼠标瞄准/左键射击，Shift 潜墨，Space 跳跃，E 副武器，F/Q 大招，Tab/M 地图，地图中 1–4 超级跳跃，Esc 暂停。菜单提供键鼠和手柄导航。

开发验证统一通过 `tools/run_godot.ps1` 串行调用引擎。它使用独立互斥锁，避免多个代理同时写入项目导入缓存。运行中的用户编辑器不属于验证进程。

## 当前实现与验证边界

- 四张地图使用原程序生成的几何、碰撞/导航数据、材质库、环境与装饰，包含白天/傍晚主题。
- 七种武器、潜墨/回墨、涂地、受击/复活、Bot、Boss、结算与本地 ENet 房间流程已有原生实现。
- 原角色/武器与换装目录已经导入，原骨架/动作接入运动匹配、惯性混合和脚部/瞄准修正。
- 下半身原生 Motion Matching 试验已接入：`--native-locomotion-mm` 使用你提供的 C++ 插件查询，过滤九根髋部/腿脚骨骼。当前默认关闭，仍保留原物理控制与上半身武器动画；原循环动作尚未补专门的起步、刹停和转身动作。评估和实际检查见 `docs/motion-matching-plugin-assessment.md`。
- 油墨绘制、PMREM 反射、材质与 HDR 泛光由 GPU 执行；CPU 保留规则、权威状态和导航。
- UI 以 `../tools/ui-lab.html` 及生产网页模块为依据，固定截图用于逐页对照。Tab 展开地图遵循生产对战的 diorama 链路和最新要求，显示垂直俯视实时场景；它不使用 UI Lab 的图片地图。3D 场景与 UI Lab 的平面示意背景分别核对。

测试目录中的 source contract 数据由原网页模块实际计算或 GPU 渲染得到。PNG 写入成功或程序退出码为零不代表通过；必须同时检查日志中的脚本、解析、着色器和运行时错误。性能结果只适用于对应机器、场景、分辨率和测试窗口。

UI 细节及剩余差异见 `docs/ui-lab-port-review.md`。Mini Tanks 仅作为只读参考，隔离复用方案见 `docs/mini-tanks-server-reuse-audit.md`；没有修改它的客户端、服务端或现有服务。公网 relay/独立专服尚需完整真实链路验证。

本轮 PC 检查与性能采样的有效范围见 `docs/pc-polish-verification-2026-10-03.md`。无人值守性能检查必须显式添加 `--benchmark-background --nonpersistent`，并核对报告中的 `playing_seconds` 和 `focus_paused`，避免把失焦暂停期间的空闲渲染当作对战性能。

直接从 Godot 运行时的落地、受击反馈、瞄准辅助及渲染缓存修正见 `docs/pc-polish-2026-10-04.md`；报告分别列出实际通过的场景与仍需打磨的移动、插值和帧时间范围。

PowerShell 调用包装脚本时，以 `-GodotArgs @('--path', '<项目绝对路径>', '--', '--benchmark-background', '--nonpersistent', ...)` 传参。把裸 `--` 写在脚本参数间会被 PowerShell 消耗，导致游戏参数未进入 `OS.get_cmdline_user_args()`。固定帧上限探针用游戏参数 `--benchmark-fps=144`，游戏设置会覆盖引擎级 `--max-fps`。

## 可重复的开发工具

`tools/build_development.ps1 -Platform Windows` 在新目录制作私有快照、独立引擎缓存与模板，导出后运行原生包启动、对战和 GPU 检查。产物在 `builds/<时间>-windows/output`，不是发布版本。

加上 `-NativeLocomotionMM` 会要求包内实际 GPU 对战启用全部八个原生下半身查询器，并生成可双击的 `Splatink-NativeMM.cmd`。直接运行项目时可用 `tools/run_godot.ps1 -GodotArgs @('--path', 'H:\GDP\inkwave\splatink', '--', '--native-locomotion-mm')`。完整可复现 C++ 源包和补丁在 `tools/native_mm`；原 F:/D: 参考目录保持只读。Windows 与 macOS 的动态库都从相同补丁源码构建，具体平台运行证据单独记录。

`tools/export_source_radiance.mjs` 冻结原天空的 HDR/PMREM；`tools/export_source_library_mips.mjs` 保存原 GPU 的 sRGB/线性材质 mip 链；`tools/export_source_bloom.mjs` 保存原五级 Gaussian 参数。游戏运行时直接使用这些资源，不实时重烘焙环境反射。

角色程序化生成组件属于游戏打磨完成后的下一阶段。

首次 Git 检查点的范围与移动实验状态见 `docs/git-checkpoint-2026-10-04.md`。大型逐帧诊断、私有构建快照和本机工具缓存保留在本地，不进入版本库。
