---
name: weibei-course-wayfinding
description: 在当前课程的多份材料与笔记中查找知识关联、前置与复习路径，并给出可点击的来源跳转。
compatibility: 需要 PI 0.80.2 与魏碑扩展提供的课程地图、课程搜索和学习记忆工具。
allowed-tools: weibei_context weibei_course_map weibei_course_search weibei_learning_memory weibei_learning_update weibei_rich_answer
---

# 魏碑课程寻路

## 工作流

1. 先调用 `weibei_context`，确认当前材料、选区、笔记和用户问题。
2. 调用 `weibei_course_map`，分页了解课程里有哪些材料、笔记和已确认的笔记-材料关联；目录标题本身不是内容证据。
3. 把用户的问题、当前选区或核心概念组成简短查询，调用 `weibei_course_search`。如果用户问“下一步学什么”，再调用 `weibei_learning_memory`。
4. 对每个候选项分别说明关联类型：同一概念、前置、解释、例子、对比、笔记归纳或待补证据。
5. 只推荐工具真实返回的文件；索引片段被截断时，不声称已检查整本书。
6. 多份材料之间的时间、空间、前置或证据关系用图式更清楚时，可调用 `weibei_rich_answer`；用户明确要求富回答或关系图且搜索证据足够时必须调用；只有文件清单时不要生成关系图。

## 输出

不强制固定篇幅。有多个有效去处时，使用简短的“关联”段落：

```markdown
## 关联
- **关联原因**：这份材料如何帮助当前问题。[材料：精确标题]
  来源：精确标题
```

工具返回的 `evidenceLabel` 用于证据；单独的来源行用于魏碑点击跳转。必须原样复制 `evidenceLabel` 以及工具返回的 `jumpReference`、`sectionJumpReferences` 或 `pageJumpReferences`，不得删掉重复文件所需的 `条目`、HTML 定位所需的 `章节标识` / `章节序号` 或 PDF 页码，也不得自行改写章节名。
工具返回页或章节级跳转时，优先给最精确的位置，不退回只打开整份文件。
