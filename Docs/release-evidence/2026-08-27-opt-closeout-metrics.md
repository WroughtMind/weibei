# 优化计划收口指标（2026-08-27）

本轮没有 1.1 改前对照。下列是 17 项叠加后的收口基线，不是刀刀前后对比。

原始 `WEIBEI_PERF` 输出：`Docs/release-evidence/2026-08-27-opt-closeout-perf.log`。

## 启动（1.1 / 2.4 / 3.3 叠加）

空工作区、`WEIBEI_PERF=1`、`WEIBEI_WORKSPACE_DIR` 指向临时目录，直接跑 staged 包二进制（`fda2510c`，不 `open`、不 `pkill`）。

| 探针 | ms |
|---|---|
| `app.restore_to_next_main_queue_proxy`（beginLaunch→finishLaunch） | **834.396** |

## 保存（3.3 外置后，空工作区）

| 探针 | 观测 |
|---|---|
| `workspace.save_snapshot` | 0.06–0.90 ms |
| `workspace.save_encode` | 0.10–0.42 ms（主线程外） |
| `workspace.save_disk_commit_and_verify` | 0.43–0.91 ms（主线程外） |
| `workspace.save_transaction_to_ui_publish` | 0.89–2.91 ms |

历史对照：2026-07-19 `perf-p0` 在当时工作区密度下 `workspace.save` ≈ 9.3 ms。空库不能外推用户大库，但外置后空库保存已远低于 250 ms 预算。

## 空闲 CPU（3.4）

终验 staged 包进程 pid 7991（`fda2510c`，卸载 flag 仍关）。12 秒采样 6 次 `%CPU`：`0.0, 0.0, 0.0, 0.0, 0.0, 7.4`。RSS ≈ 41 MB。最后一次 7.4 出现在用户可能正在操作时，其余为 0，不再是每 3 秒全盘扫的持续占用。

## 长会话内存 / 滚动（3.2）

- 100+ 消息视口占位自动化已过。
- 用户终验滚动顺滑后，本收口把卸载 flag **缺省改为开**（显式 `false` 仍关）。
- 本机无独立 FPS 计数器；idle RSS 是 flag 关时的挂机值，不能当超长对话 footprint 对照。

## 未复测

- 输入探针 `input.agent_to_next_main_queue_proxy`：1.3 自动化已锁，本轮不重采。
- 侧栏重建次数：1.4 `testNoteBodyEditsDoNotRebuildSidebarUntilTitleLineChanges` 已锁。
