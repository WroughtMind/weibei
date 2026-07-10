---
name: weibei-course-wayfinding
description: 在当前课程的多份材料与笔记中查找知识关联、前置与复习路径，并给出可点击的来源跳转。
compatibility: 需要 PI 0.80.2 与魏碑扩展提供的课程地图、课程搜索和学习记忆工具。
allowed-tools: weibei_context weibei_course_map weibei_course_search weibei_learning_memory weibei_learning_update
---

# 魏碑课程寻路

## 工作流

1. 先调用 `weibei_context`，确认当前材料、选区、笔记和用户问题。
2. 调用 `weibei_course_map`，分页了解课程里有哪些材料、笔记和已确认的笔记-材料关联；目录标题本身不是内容证据。
3. 把用户的问题、当前选区或核心概念组成简短查询，调用 `weibei_course_search`。如果用户问“下一步学什么”，再调用 `weibei_learning_memory`。
4. 对每个候选项分别说明关联类型：同一概念、前置、解释、例子、对比、笔记归纳或待补证据。
5. 只推荐工具真实返回的文件；索引片段被截断时，不声称已检查整本书。

## 输出

不强制固定篇幅。有多个有效去处时，使用简短的“关联”段落：

```markdown
## 关联
- **关联原因**：这份材料如何帮助当前问题。[材料：精确标题]
  来源：精确标题
```

`\[材料：标题\]` 或 `\[笔记：标题\]` 用于证据；单独的 `来源：标题` 用于魏碑点击跳转。
