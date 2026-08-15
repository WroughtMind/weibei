# 魏碑课程侧边栏性能根因与最佳实现

## 判定

魏碑不应回退到某个旧版本，也不应把整个工作区改成会挤压 DOC / CHAT / NOTES 的系统导航分栏。

当前最合适的单一实现是：**保留覆盖式 AppKit 抽屉；内部改成 SwiftUI `List` 和一份轻量、纯值的课程目录投影；打开时才挂载，关闭动画完成后彻底卸载。**

现在没有证据支持直接重写成 `NSOutlineView`。在与真实工作区同规模的 540 行无窗口探针里，现结构创建 540 行，而 SwiftUI `List` 只创建 19 行，连续五次一致；原生 `NSOutlineView` 样本为 16 个单元格，二者已经处于同一量级。Apple 也明确说明 `List` 会按需加载行，适合大型集合：[Displaying data in lists](https://developer.apple.com/documentation/swiftui/displaying-data-in-lists)。

## 三个症状的确定根因

| 症状 | 已证实根因 | 证据 |
|---|---|---|
| 点击后很久才开始滑出 | 打开路径先创建/重设整棵 SwiftUI 树，再强制两次布局，最后才启动 120ms 动画 | 源码调用链；Apple 说明 `layoutSubtreeIfNeeded` 本来会由系统在显示前自动调用，手工调用会立即更新整棵约束和布局：[layoutSubtreeIfNeeded](https://developer.apple.com/documentation/appkit/nsview/layoutsubtreeifneeded%28%29) |
| 列表滚动沉重 | 外层 `LazyVStack` 只有三个大分组，组内仍是普通 `VStack + ForEach`，所以 540 行全量创建；行内还反复解析 Markdown 标签 | 无窗口探针：现结构 540 行，`List` 19 行；真实工作区 26 个未缓存外部笔记，两次标签解析 p50 约 51ms、p95 多数 52–59ms，读文件本身仅约 0.4ms |
| 打开一次后，收起仍拖慢全 App | 关闭只把面板移到屏外；`NSHostingView`、整个 `WorkspaceStore` 和 `paneState` 订阅永不销毁 | 无窗口生命周期探针连续五次得到：屏外视图在无关状态发布后 body 计数从 1 变 2；先清空 root 再卸载后保持 1，不再更新 |

最新删除改动为每门课程和每个非样例文件增加了常驻 `Menu`，会放大行创建成本，但不是历史根因；删除动作本身只在确认后执行，不参与空闲卡顿。

## 为什么“曾经很顺，后来又坏”并不矛盾

历史无法证明某一个精确日期，但能证明两个阶段：

- Build 413–459 是结构最轻的阶段：用户包改为 Release，侧栏还没有课程层级和关系扫描。
- Build 486–609 最像“点一下立刻弹、点一下立刻回”的记忆：此前连续合并了笔记输入缓冲、保存合并、侧栏开关隔离和 120ms AppKit 位移动画。

然而 Build 486 的 `841939c` 同时首次引入永久保留屏外 `NSHostingView`。因此它既让当时的开关更快，也埋下了“打开一次后关闭仍卡”的生命周期缺陷。后来真实课程根、周期刷新、更多数据和常驻菜单逐步把这项潜伏成本放大。这个首坏点的源码归属置信度为 10/10。

## 最佳实现

### 1. 保留覆盖式壳，不动三个主窗格

保留现有 `StableDocumentWorkspace` 和覆盖式抽屉。DOC、CHAT、NOTES 的宿主身份、草稿、滚动位置、PDF/WebKit 和编辑器不因侧栏开关改变。

成熟 macOS 项目普遍使用系统分栏与可复用列表/树：例如 [CodeEdit 的三栏控制器和项目树](https://github.com/CodeEditApp/CodeEdit/blob/cec6287a49a0a460cd7cab17f254eebc3ada828e/CodeEdit/Features/NavigatorArea/ProjectNavigator/OutlineView/ProjectNavigatorViewController.swift#L73-L117)、[CotEditor 的目录侧栏](https://github.com/coteditor/CotEditor/blob/e5ac0081731bce1b90349f2d0698d9404ef1bc05/CotEditor/Sources/Document%20Window/WindowContentViewController.swift#L91-L170)、[NetNewsWire 只刷新现有行](https://github.com/Ranchero-Software/NetNewsWire/blob/ab2f35f33fa688a41fe4984bf9499934cde7d63b/Mac/MainWindow/Sidebar/SidebarViewController.swift#L881-L903)。魏碑借用的是稳定身份、按需行和局部状态，不复制它们会挤压内容的分栏外形。

### 2. SwiftUI `List`，但只吃纯值行

将课程、分组、资料和笔记整理成一个带稳定业务 ID 的扁平可见行数组，由 `List(selection:)` + `.listStyle(.sidebar)` 显示。稳定 ID 能减少 SwiftUI 依赖图和视图存储抖动，见 Apple 的 [Demystify SwiftUI](https://developer.apple.com/videos/play/wwdc2021/10022/)。

每个行值只包含标题、副标题、图标、计数、标签、选中和展开状态。行不得观察 `WorkspaceStore`，不得在 `body` 里：

- 扫描课程关系；
- 读取文件；
- 解析 Markdown；
- 排序或重新分组；
- 创建所有未显示行的菜单。

标签、计数和关系在相关数据真正变化时预计算。右键菜单按点击行动态生成；省略号只在悬停或选中行出现。

### 3. 独立投影，不观察整个工作区

抽屉只观察一个小型课程目录投影，而不是含 67 个直接发布属性、另有手工发布入口的 `WorkspaceStore`。投影只接收课程、成员关系、项目元数据、搜索、展开和选择这些确实影响侧栏的输入。

Apple 的性能原则正是缩小依赖面，让只有真正依赖变化的视图更新；`ObservableObject` 的统一 `objectWillChange` 会让所有观察者失效，而细粒度依赖与稳定身份能减少无意义更新：[WWDC23 SwiftUI performance](https://developer.apple.com/videos/play/wwdc2023/10160/)、[WWDC23 Observation](https://developer.apple.com/videos/play/wwdc2023/10149/)。

### 4. 关闭动画完成后彻底卸载

常驻的只应是轻量 AppKit 容器和 `LibraryDrawerState`：

1. 打开时挂载 `NSHostingView<List>`，开始定向订阅；
2. 使用上一份不可变快照立即开始位移，不等待刷新；
3. 关闭动画完成后取消订阅与任务，先把 hosting view 的 root 换成 `EmptyView` 立即切断 SwiftUI 观察树，再 `removeFromSuperview()` 并置空；
4. 可以保留纯值快照缓存，但不得保留活的 `WorkspaceStore`、`paneState` 或行观察器。

这让“关闭后零更新”成为结构事实，而不是依赖一条实际上无效的“关闭时不重设 rootView”注释。

### 5. 动画只移动固定尺寸视图

面板宽高先固定，只通过 AppKit `animator()` 改变 x 原点，遮罩只改透明度。打开路径删除 `rootView` 重设和两次强制布局；容器的 `layout()` 也不得在动画中重写 x。

不直接操作 layer transform。Apple 对 macOS layer-backed `NSView` 的建议是优先使用 AppKit 视图动画接口，避免视图几何、命中和无障碍与图层脱节：[Animating Layer Content](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreAnimation_guide/CreatingBasicAnimations/CreatingBasicAnimations.html)。Core Animation 会负责动画逐帧合成，但布局和初始内容仍必须在动画关键路径外完成：[Core Animation Basics](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreAnimation_guide/CoreAnimationBasics/CoreAnimationBasics.html)。

## 自动验收契约

以 Release 构建、真实 540 项数据和 2,000 行压力数据各跑 100 次：

| 场景 | 必须满足 |
|---|---|
| 打开 / 关闭 | 指令到开始移动 p95 不超过一个显示刷新周期；动画完成不超过 150ms；同步磁盘 I/O 和强制布局均为 0 |
| 滚动 | 帧时 p95 不超过当前刷新周期；超过两帧的卡顿少于 1%；活跃行 body 数不超过可见行的 2 倍 |
| 关闭后 | 100 次无关工作区和窗格状态更新，侧栏投影、body、文件读取计数全部为 0；host、订阅和任务数为 0 |
| 全 App 连续性 | 打开再关闭后，三个顶部窗格动画 p95 相比“从未打开侧栏”基线劣化不超过 5%；三个主窗格宿主身份不变 |

Apple 建议用 SwiftUI Instruments 同时检查长 `body`、频繁更新和平台视图更新，而不是只看平均 CPU：[Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/Xcode/understanding-and-improving-swiftui-performance)。

## 升级到 NSOutlineView 的唯一条件

先做以上较小、原生的 `List` 方案。只有在清除渲染 I/O、宽订阅和生命周期问题之后，2,000 行 Release 压测仍满足以下全部条件，才升级到 `NSOutlineView`：

1. 滚动 p95 超过一帧或掉帧率超过 1%；
2. Instruments 证明至少 50% 的主线程时间确实消耗在 SwiftUI `List` 的差量更新、布局或 hosting，而不是业务计算；
3. 真实课程层级已超过当前两层，确实需要更细的节点级 reload。

目前不满足这些条件，因此直接重写 AppKit 树属于没有证据支持的过度工程。
