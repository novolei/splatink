# PC 玩法与 FX 源码对照

更新至 2026-10-04。该文档记录 `scripts/game`、`scripts/fx` 的已验证范围与剩余差距。Godot 导入、合同执行和实际 GPU 运行均由根任务串行执行；本子任务只运行原网页源码导出器。列出的通过项不代表全游戏已达到 100% 一致。

## 投射物、投掷物与范围伤害

| 原源码执行入口 | 原生对照范围 | 最新执行证据 |
| --- | --- | --- |
| `Projectiles._step`、`fireCharger` | 42 类弹丸接触、8 类蓄力射线；原玩家/Boss/墙面查询顺序、半径、甩墨衰减、直接命中与 volley 排除 | 419 项通过；`shots/pc-projectile_contacts-throwables.log` |
| 原投射物逐帧更新 | 13 段、596 帧；延迟跨零当帧推进、严格寿命边界、重力、拖曳、尾滴距离累计 | 7,175 项通过；`shots/pc-projectile_motion-throwables.log` |
| `Projectiles._updateBombs` | 8 段、334 帧；地板/侧壁/陡面/格栅反弹，原引信与 beep 时间、体积/音高、退场当帧不再翻滚；云弹在完整积分位置打开且严格 `age > 1.1`；炸弹保留原无 8 秒空中超时 | 6,734 项通过；`shots/pc-throwables-throwables.log` |
| `_explodeBomb`、`_blastBurst`、`_sloshSplash`、`Actor._slamImpact` 和 `Physics.los` | 28 类、原受害者顺序/排除/径向伤害；25cm 遮挡、末端 25mm/65mm 边界、格栅、Blaster 原点高度、Slosher 同 volley 去重与 Slam 内外圈 | 373 项通过；`shots/pc-area-los-contract.log` |
| `Projectiles._updateClouds`、`Actor.damage/splat` 和 `Physics.los` | 8 段、77 帧；联机 foreign ghost 墨雨伤本地 owned Actor，自己云不再向 proxy 发送重复 hit；单次死亡/击杀归属、队伍/存活/距离/高度、固体/格栅遮顶、无敌与 Slam 护甲、活跃及退场时间 | 2,439 项通过；`shots/pc-storm-los-contract.log` |

原 `Physics.los` 查询忽略格栅，并在终点前 5cm 截止。原生 `_world_los` 现在统一用于以上范围伤害和墨雨遮顶；移除了此前“遮挡点距受害者不足 40cm 仍可伤害”的原生豁免。Bomb 的 LOS 起点为爆点上方 0.3m，Blaster 为爆点本身，Slosher 为上方 0.25m，Slam 为上方 0.8m，均按原源码保留。

普通弹丸、枪口遮挡、Charger 射线与线条落墨查询忽略格栅；炸弹/云弹碰撞、云的初始寻地、墨雨落地和 Blaster 爆点向下落墨查询包含格栅。这些调用通过实际 Actor 的源碰撞后端查询，测试 fixture 没有该后端时才使用等价的碰撞 mask。

墨雨联机伤害使用现有 `InkNetwork.owns_actor(victim)` 和 `Actor.damage` 的 victim-owner guard。Ghost 云依旧不进行自己的墨雨涂墨或 Boss 雨伤害；受害者 owner 结算死亡时，原死亡墨爆和 `splatted`/`hit` 确认仍发生。上述合同执行了真实原生 Actor，但网络是复刻 production owner-first 行为的 probe；**真实双机器 cloud kill 归属尚未单独验证**，不能用一般 LAN 生命周期通过代替该场景。

## 已验证的 FX 范围

| 对照 | 范围 | 最新证据 |
| --- | --- | --- |
| 原 `FxHooks._projectiles` 和 `FX.sloshTrail` | 每类累计距离与阈值、年龄/延迟/距离可见性、48 次共享预算、回收对象重置、Slosher 头尾配方 | 2,690 项通过；`shots/pc-fx_projectile_hooks-drops.log` |
| 原 puff/glow Float32 池 | 874 帧；轨迹、随机旋转、浮力、尺寸/淡出、覆盖回收与实际 GPU 提交包 | 33,911 项通过；`shots/pc-fx-sprites-current.log` |
| 原 droplet Float32 池 | 8 段、379 帧；轨迹、半径、速度伸缩、相机投影、38Hz 摆动、碰撞/海面/回收顺序、落地事件与 GPU 实例提交 | 21,267 项通过；`shots/pc-fx_drops-drops.log` |
| 色板、线性配方与环境光 | 6 套色板，原 `Color.lerp` 白/暗/HDR 混色，光照配置、团队颜色识别与提交空间 | 最新 1,390 固定断言与 2,513 随机提交包断言通过；`shots/pc-fx_colors-throwables.log` |

颜色合同的提交包断言数量会随原随机卫星粒子变化；固定断言数量单独输出，不把动态总数差异解释为删掉测试。传入带 `source_color` 的 uniform 在边界进行编码；原实例 `COLOR` 和裸 HDR 向量保持线性数据，未做全局无区别色彩转换。

## 保留的策略与可见差距

墨滴轨迹和提交已通过，容量与碰撞预算仍保留原生适配策略。下表是在相同 FX quality 标量 `q` 下比较，不推断网页菜单档位与原生菜单档位完全同义。

| q | 原网页 droplet 容量 | 原生有效上限 | 原网页单次 update 碰撞预算 | 原生预算 |
| --- | ---: | ---: | ---: | ---: |
| 1.0 | 2,600 | 2,048 | 1,100 | 24 |
| 0.7 | 1,820 | 1,024 | 770 | 16 |
| 0.4 | 1,040 | 512 | 440 | 8 |

因此密集爆炸/墨雨同时发生时，粒子保留数量与首次可碰撞的水滴范围仍可能不同；不能将已通过的 eligible trajectory 合同扩大成容量策略一致。`InkDropPool.drop` 自身已实现原版溢出时每次前进 7 槽的覆盖策略，但生产 `InkFx._drop` 仍在有效上限处拒绝新粒子，尚未让该覆盖策略在所有配方入口生效。当前单次提交仍是 SoA/MultiMesh，未改权威玩法判定，也未无依据提高预算。

尚未修正的阴影差距：原 `Projectiles.blobs.castShadow = true` 与 `throwBomb` 的 `body.castShadow = true`，原生 `InkProjectilePool` 和池化 bomb mesh 目前为 `SHADOW_CASTING_SETTING_OFF`。原云弹 body 本就没有启用投影；原普通 FX 水滴/精灵也不投影，不能把所有 FX 一律开启。PC 墨雨云的投影已开启。后续需独立原画面对照和 GPU 成本验证，再决定具体几何的投影设置。

炸弹 FX polling 也有可见差距：原版具有飞行滴墨、反弹飞溅、首次上引信的缓存地面探测、每帧 danger mark 和 beep pulse；原生目前仍是随机扩散圈。原 Ring shader 的八种样式与 48 个即时 mark 尚未全部移植。这些差距未混入上述玩法、所有权或 LOS 修正。

最新墨滴版实际 GPU Boss 检查为 1,781 帧 / 24.77185 秒实战，正确均值 **71.90 FPS**，p95 **33.33ms**，见 `shots/pc-boss-drops-profile.json`。旧引擎监控均值 103.49 使用不同且有偏的采样口径，不能当实际平均 FPS；此短场景也不足以证明整游戏性能达标。
