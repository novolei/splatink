# INKWAVE UI Lab 原生移植核对记录

参考为 `H:/GDP/inkwave/tools/ui-lab.html`、`tools/ui-lab.js`、`src/ui/{menus,hud,boss-hud}.js` 与 `styles/{ui,hud}.css`。本记录描述已实现边界和实际验证结果，不等同于全部像素、时间轴或交互已达到 100% 一致。

## 对照材料

- `tools/capture_ui_matrix.mjs`：只读加载源 UI Lab，1280×720，14 个页面及 12 个页面变体，共 26 个 PNG 和 DOM 几何记录。没有改源项目或其服务。Results 源图等待 8 秒，HUD 固定 94.4 秒、72% 墨量、82% 大招、扩散 4。
- `scripts/ui/tests/capture_matrix.gd`：原生单进程顺序显示同样 26 变体，记录 PNG、可见文字/控件矩形、焦点和绘制数。`fixture_mode` 禁止写入用户进度/设置；页面过渡被跳过，结果页保留源计数时间轴。
- `shots/reference/ui/*.png`：源网页截图。`shots/ui-native-matrix-polished/*.png`：本轮原生实图。`scripts/ui/tests/build_compare.py` 可生成 source/native 左右拼图。
- 矩阵 JSON 的 `failures` 只计 PNG/JSON 文件写入失败。引擎脚本或着色器错误必须以 root 的 Godot wrapper 日志独立核对。

源 Lab 的平面假场景、假 Squid 图标和生产 Showcase 的真实世界/人物渲染是两个不同的参考层。原生保持生产 attract 世界与 Loadout/Locker/Results 透明 studio，不用 Lab 的平面假背景替换真实 3D 世界。固定 Jayden 样式按原 `resolveStyle({}, FNV('Jayden'))` 推导：hair 6、skin 6、outfit 7、eyes 3、hat 0、brows 0。

## 已覆盖的原生 UI 边界

| 页面/系统 | 已实现内容 |
|---|---|
| Loading / Title / Main | 原字形与原 SVG 墨团、完整 SVG overflow 卫星滴，进度斜纹/TIP，按键开始，原主菜单和 Profile/Loadout 面板 |
| Mode / Setup | Turf/Boss 两张贴纸卡，源阶段图片、卡片焦点、模式说明/度量，Stage/Day/Dusk/Bot/时长/Loadout/Locker 与开始 |
| Loadout | 源 7 套 weapon SVG、原 NEW、计数、装备墨团/圆勾/橙环，源 stat 五项、分段圆端/比较，sub/special 成本及说明 |
| Locker | 源外观目录、预设/发型/脸/衣服选项，穿戴/随机/改名/自动保存，原 portrait 灯光与 camera 配置，独立 World3D 缩略图 |
| Settings / Howto / Credits | Controls/Video/Audio/Gameplay 分页、即时设置/预览/重置，控制说明与键帽，原版署名及原生适配说明 |
| Online / Lobby | 创建/输入房间码/连接状态/错误提示，5 字符票据/复制，房间人数/队伍/准备状态、主机设置、玩家名牌、武器/外观/表情/退出 |
| Pause / Results / News | 比赛时钟/玩家/队伍 roster/个人数据、继续与退出，原比分/队伍表/奖励/XP/回房间，首次新闻2页/继续/跳过/已读持久化 |
| Match HUD | 源 ceil 计时、8人徽章、分武器准星/墨槽/大招球、命中与伤害/击杀/复活/倒数/开场/judge，源坐标 minimap/4个超级跳跃目标/世界同队标签/prompt |
| Boss HUD | Boss 徽章/名字/百分比/phase/弱点提示、攻击预警/伤害连击数/弱点击中/阶段和结果展示，网络端源 Boss 展示事件 |

PC 控件使用原生 Control。页面尺寸使用原 `u=min(W/100,H*1.7778/100)`，缩略图单次渲染，HUD 名牌预建8个控件，进度/背景/大招球/面板采用批量 Canvas shader。

## 本轮实际结果与修复

`shots/pc-ui-polish-matrix.log` 已生成 26 张图片，但 Lobby 的动态脚本首次加载存在 `owner` 与 Godot Node.owner 名称冲突。因此该轮不能称为完整干净。字段已改为 `room_owner`，随后 `pc-ui-polish-lobby.log` 实际 GPU 重载成功；该图已经替换。

对其余 25 张实图的读取确认：Loadout 的 NEW/1-of-7/装备圈/原 SVG 黑层/圆端 stat/cost 已显示；Settings 已回到源首行焦点并按 Audio/Video 行数缩放面板。大招球 rim 的 smoothstep 符号、Loading 白描边兄弟绘制顺序、展开地图时 prompt/名牌覆盖已修，`pc-ui-polish-five-current.log` 的 `loading/hud/hud-charger/hud-map/lobby` 5页实际 GPU 重捕无 ERROR。

`pc-ui-polish-six-current.log` 的 `setup/setup-boss/settings/settings-video/settings-audio/settings-gameplay` 6页实际 GPU 重捕无 ERROR：mapThumb 的源 iw-fa/iw-fb 类已解析为橙/蓝，Settings 新原全局焦点环按 k560/c34、120Hz 子步进弹簧及1.3秒脉动显示。`build_compare.py --native shots/ui-native-matrix-polished` 已生成5张26变体左右拼图；部分重捕会覆写 matrix.json，工具根据完整PNG集恢复原顺序。

生产 Boss 实图随后发现名牌箭头围绕左上角旋转、名牌比源厚约5px宽约8px、头部投影/屏幕边界非源值。已按 `src/main.js:1076` 和 `styles/hud.css:360` 窄修：30px方向圆心旋转、源 padding/11或10px字体、头骨+.45m/squid视觉位置+1m、20px可见边界/40px边缘。源 Marker 没有射线遮挡、排布去重或逐标签淡入，只按14→34m距离縮小18%/透明45%，未新增隐藏规则。待 root 生产比赛重捕。

News 两页源 DOM 追加原 offset 几何记录，修正 hero/body 的22px列偏差及高度、原双色标题/NEW文本/Beta斜纹/Enter键帽；Lobby blocked START失焦白字和Boss Setup徽章/蓝墨团/原难度描述也已修。随后 `pc-ui-polish-matrix-final.log` 在 root 串行真实 GPU 链路生成全部26页，26个PNG写出成功且日志没有 SCRIPT ERROR/ERROR。该结果证明本次静态矩阵运行干净，不能证明全部像素、交互或时间轴一致。

26页矩阵后的 `news-1.png` 与源同页实际左右检查发现：源卡有明显黑色 drop-shadow/外轮廓与细 grain，原生卡更平且点纹较规则；原生 Continue 自动焦点橙环在源固定截图中没有；原生左上胶带比源贴图角高约25px。以下窄修专门处理了这组已知差异。生产真实3D背景本身另按原 Showcase 校验。

2026-10-04 的 News 窄修读取原 `styles/ui.css`：卡片恢复源白/黑双外框、偏移阴影和170°双色渐变；`--tex-grain` 的原 SVG 字节保留为 `assets/ui/source_raw/news_grain.svg.txt`，一次性浏览器栅格化为140×140透明纹理 `assets/ui/source/news_grain.png`，按实际像素重复；9px点纹保留源135°遮罩渐隐。hero 图片填满原549×309内容区，胶带使用源clip-path、17%×11%尺寸、-33°旋转及角点位置。News 的 Continue/Skip 保留键盘焦点和白色选中填充，只关闭被 News 层遮住的橙色外焦点描边；其他按钮默认行为不变。卡片由一个 Canvas quad 绘制，不新增辅助 Viewport 或每帧构造粒子几何。

Root 的 `pc-news-polished-gpu.log` 串行实际 GPU 链路重捕 `news-1/news-2/main` 三页，PNG/JSON 写出零失败，日志无 SCRIPT ERROR/ERROR；文件在 `shots/ui-native-news-polished/`，`matrix.json` 的 failures 为空。源/原生实图复核显示外框、渐变和胶带已接近源设计，仍有 badge 字距、Cargo 小缩略图圆角白边及部分图标差别。此次接受范围是窄修渲染干净与上述前景改进，不等同于100%像素一致或完整 News 动效/输入时间轴验收。后续生产文件冻结，未扩大修改范围。

## 仍需继续逐项对照的细节

- 文字的源字距、部分数字千位格式、若干键帽与行标题，还存在可见细差；News 最新残差为 badge 字距、Cargo 缩略图圆角白边和部分图标，旧阴影/grain/胶带/外焦点问题的窄修证据见上述记录。
- 页面 hover/parallax/glare、部分 SVG 滴落、地图虚拟光标/吸附/重叠目标分离、个别准星武器细节，应继续按源时间轴和实际键鼠/手柄链路验证。
- 14页26变体的实图是静态前景验证，不覆盖全部弹窗、不同队伍/比赛结果/网络断开/所有 HUD/VFXUI 事件组合。
- LAN 两分支 20 秒 probe 已在 root 串行引擎链路通过结果送达和双方回房间；公网源 relay 互操作仍未实测，不据此宣称互联网服务完成。

远端 climbing bit变化已派生单次 `actor:climb`，代理 avatar 以climb姿态显示；单进程双SceneMultiplayer的20秒实际 probe `pc-lan-climb-abort.log` 已通过 attach/detach 每端恰2次断言、正常结果12秒回房以及主动退出无abort。

用户随后明确 Tab 展开地图必须以实际游戏为参考，替换此前 UI Lab 绘图展开方案。生产源 `src/main.js:921/924`、`src/ui/diorama.js`、`styles/hud.css:609–678` 使用真实世界镜头与五个世界投影 pin；`main.js:1120` 的普通 HUD map 始终 `expanded:false`。此前 `hud-map` 静态截图仅保留为旧 Lab 移植证据，不再作为生产 Tab 地图验收目标。用户要求垂直俯视优先于源 `CameraRig.DIO_PITCH=1.1` 的陡倾斜俯视，镜头调整与生产投影 HUD 正在独立实现。

`scripts/ui/hud_diorama.gd` 使用原生正在绘制的 game.camera 投影，不另建世界、capture camera、图片或地图库。五pin固定队友0–2/Base3/YOU4，死亡倒数与飞行BUSY保留同一槽，虚拟锁鼠/右摇杆光标、72px吸附、点/A/数字跳跃和真实地点的弧线；普通地图面板在展开时隐藏。画面只新增一个 fullscreen finish quad 与预建5个pin，quality low关闭blur；9tap blur是原CSS6px Gaussian的近似，未声称严格像素一致。

`pc-input-contract.json` 最新真实GPU版本29项0失败，`shots/pc-input-live-map.png` 已展示真正垂直实时3D、5pin、旧图片面板隐藏、锁鼠光标不旋转瞄准、死亡队友槽与Key4 Base。首张实图标题缺失、spawn附近名字和Base重叠，已改按 config.MAPS(stage_id) 取生产名。原 `src/ui/diorama.js` 没有防重叠；本次适配原 `hud.js:1210–1238` 的六轮确定性排斥算法，并为文字增加间隔，ground dot/连接stem/跳跃弧线始终使用真实投影点。这一最新可读性改动仍待 root 重捕。

PC 输入真实 GPU 链路已有 root 的20项0失败记录：`shots/pc-input-contract.json/log`。它证实键鼠动作、暂停/恢复与 HUD/Menu 竞态修复；该结果不等同于所有 UI 精度或设备性能通过。
