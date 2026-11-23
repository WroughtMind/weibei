# 动效

曲线与时长定义在 [设计变量](../08-implementation/tokens.json) 的 `motion`。修改后运行 `node script/build_motion_tokens.mjs`，同步原生界面、应用内网页和官网。SwiftUI 使用 `WeiBeiMotion` 的角色，网页使用同源 CSS 变量。

| 用途 | 曲线 | 时长 |
| --- | --- | --- |
| 入场 | `--ease-out` | 小型 `--duration-sm` 200ms，中型 `--duration-md` 320ms，大型 `--duration-lg` 420ms |
| 退场 | `--ease-in` | 小型 150ms，中型 250ms，大型 350ms |
| 屏幕内位移、缩放和滚动 | `--ease-in-out` | 原位和短距离滚动 250ms，大型场景 420ms |
| 点击后图标、文字或选中态 | `--ease-out-strong` | 150ms |
| 悬停和按压 | `--ease-out` | `--duration-control` 120ms |
| 小件的弹跳回馈 | `--ease-overshoot` | 约为同规模普通动效的 1.5 倍 |
| 手势松手后的吸附 | 平台弹簧，网页用 `--ease-spring` | 约为同规模普通动效的 1.5 倍 |
| 加载、扫光和环绕进度 | `linear` | 沿用既有周期 |

拖动中由指针直接决定位置。平台弹簧支持初速度时，使用松手瞬间的速度。网页不支持 `linear()` 时，弹簧变量使用 `--ease-out-strong`。滚动驱动的官网场景沿用原来的分段和帧位置，曲线作用于各段的滚动进度。

减少动态效果沿用魏碑的系统偏好。跳转即时定位，循环走动与缩放停下，已有透明度变化使用简短淡入淡出。主题更换沿用一次统一过渡，保留正文可读性和焦点。
