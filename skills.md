# ATA 项目速览（给 AI 读取用）

游戏 **ATA**，EOF (End Of Future) 精神续作。Godot 4.7 + GDScript。俯视角撤离射击原型。

## 顶层结构

```
ATA/
├── dev_gd/            # Godot 主开发目录（当前唯一活跃代码）
│   └── ata/           # Godot 项目根
├── dev_html/          # 早期 HTML 原型（不作介绍）
└── README.md
```

## Godot 项目配置（`dev_gd/ata/project.godot`）

- name: `ATA`，main scene: `res://scenes/lobby/Lobby.tscn`
- features: `4.7` / `Forward Plus`
- autoload:
  - `GameData` → `res://scripts/GameData.gd`（跨场景数据）
  - `UITheme` → `res://scripts/UITheme.gd`（UI 绘制工具集）
- 渲染: `d3d12`，HDR 2D 开启，clear color `#070710`
- 物理: `Jolt Physics`
- stretch: `canvas_items` + `expand`（适配手机横屏）

## 场景流

`Lobby.tscn` → `Raid.tscn` → `Result.tscn` → 回 Lobby

- Lobby: 大厅漫游，按 EntryBtn 进入 Raid
- Raid: 局内战斗 + 收集 + 撤离
- Result: 展示战利品，任意点击返回大厅

## 脚本清单（`dev_gd/ata/scripts/`）

| 文件 | 类型 | 职责 |
|---|---|---|
| `GameData.gd` | autoload Node | 跨场景持久数据：`result_success: bool`、`result_inventory: Inventory` |
| `UITheme.gd` | autoload Node | 极简线框 UI 工具集：调色板、`draw_panel/draw_bar/draw_cell/draw_circle_btn/draw_square_btn/draw_label`，L 形四角装饰 |
| `Lobby.gd` | Node2D | 大厅：1600×1200 网格世界，中心圆形基地半径 220，"ATA" logo 三字母根据玩家距离做漂移动画（`_update_letters` lerp），WASD/方向键 + 触屏摇杆，Shift/摇杆越界=冲刺 ×2.2 |
| `MapGen.gd` | `class_name MapGen` static | 程序化地图：60×60 tile（TILE=48），噪声 45% + 5 次元胞自动机 + 生成点清空 + flood-fill 保最大连通域 + 边缘撤离点 + 走廊补连 + 20 个随机战利品；提供 `resolve_collision(pos, r, tiles)` 圆-AABB 推挤 |
| `Raid.gd` | Node2D | 战斗核心。TILE 网格 + `MapGen.generate()` 结果。玩家 15r/120spd，敌人 12–18 个 3 状态 FSM（0 巡逻/1 追击/2 射击），DDA 光线扫描 60° 视野锥 + 90px 近感圈 → `_fog_polygon`，子弹/敌弹匀速直线飞行、命中墙/敌/己方消散，武器有后坐力散布（`SPREAD_HALF`→`RECOIL_MAX` 累积、`RECOIL_RECOVERY` 恢复），撤离进度 1.5s 触发即结算 |
| `RaidHUD.gd` | Node2D | 局内 HUD：底部动作条（护盾条 + HP 条 + 修理/背包圆按钮 + 6 方块按钮）、方向箭头指向撤离点、撤离进度条、双摇杆可视化、背包 overlay（5×5 主背包 + 4×2 安全背包）、拖拽移动物品到最近合法格 |
| `LobbyHUD.gd` | Node2D | 大厅摇杆可视化（冲刺光晕、旋钮） |
| `TouchInput.gd` | `class_name TouchInput` Node | 双摇杆输入抽象。左摇杆（半径 90）出圈=冲刺，右摇杆双模式：内圈起手→连续开火（`is_shooting`）、外圈起手→点射（松手瞬间置 `shoot_tap`）。桌面无触屏时鼠标模拟触点 0 |
| `Inventory.gd` | `class_name Inventory` | 网格背包（默认 5×5）：`try_add` 从左上扫描空位、`try_place_at` 曼哈顿距离外扩找最近合法位、`drop_at` 移除、`total_value` 求和 |
| `ItemDef.gd` | `class_name ItemDef` static | 4 稀有度占位物品（草药 1×1/¥50 绿、医疗包 1×2/¥200 蓝、电路板 2×1/¥450 紫、晶核 2×2/¥950 金） |
| `FogMask.gd` | Node2D | 在 SubViewport 中渲染视野遮罩：黑底 + 白色视野多边形 + 白色近感圆，供 `fog.gdshader` 采样 |
| `Result.gd` | Node2D | 结算画面：绘制标题、物品清单、总价值；任意点击 → 回 Lobby |

## Shader（`dev_gd/ata/shaders/`）

- `fog.gdshader`：全屏，采样 `fog_mask` 红通道，未可见区域黑色 α=0.82
- `screen_blur.gdshader`：`textureLod(SCREEN_TEXTURE, UV, blur_lod=4.0)`，用于背包 overlay 背景模糊
- `glow_element.gdshader`：`blend_add`，7-tap 分离高斯双向模糊 + 亮度阈值 mask，模拟 Canvas `shadowBlur` 泛光

## 关键常量参考

- 地图：`MAP_W/H=60`, `TILE=48`, `FILL_DENSITY=0.45`, `CA_ITERS=5`
- 玩家：Lobby `PLAYER_R=18, SPEED=300`；Raid `PLAYER_R=15, SPD=120, ZOOM=1.5`
- 视野：`CONE_HALF=30°`, `PERCEPTION_R=90`, `RAY_STEPS=120`
- 武器：`BULLET_SPEED=700, RANGE=950, FIRE_RATE=0.22s`；散布 ±10°→30° 上限
- 敌人：`COUNT 12–18, HP=60, DMG=8, SENSE=200, CHASE=350, SHOOT=260`
- 撤离：`REVEAL=600, TIME=1.5s`
- 玩家生命：`HP=100, SHIELD=100`（护盾先扣）

## 视觉风格

- 深蓝黑底 (`#070710`) + HDR 高亮（颜色 >1.0 触发 Godot 内建辉光）
- 极简线框 UI：白色半透边框 + L 形四角 + 极小字号（11/13/15）
- 中文标签："撤离中…" / "撤离成功" / "任务失败" / "背包 (拖拽移动)" / "点击任意处返回大厅"

## 输入映射

- 键盘：WASD/方向键移动，Shift 冲刺，鼠标左键射击（无触屏时）
- 触屏：左下摇杆移动+冲刺，右下摇杆瞄准+射击（双模式）

## 当前进度（2026.6.30）

大厅 + 随机地图 + 局内收集 + 撤离 + 摇杆 + 简策划案已完成，处于原型阶段。
