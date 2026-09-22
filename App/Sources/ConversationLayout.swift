import UIKit

/// Vertical list layout for the conversation: one section per message, items stacked
/// at the shared body width. Invalidation only rewrites frames on retained attribute
/// objects, so a width change costs one linear pass over the items instead of the
/// flow layout's per-item sizing dictionary and row computation.
final class ConversationLayout: UICollectionViewLayout {
    var sectionInset = UIEdgeInsets(top: 14, left: 0, bottom: 10, right: 0)
    /// 第一个 section 之前的顶距。窗格容器的渐淡带就是工具栏高度（0-40pt），
    /// 首条消息的行必须落进带里，静止在顶时才能看到和文稿/笔记一样的洗白；
    /// 若跟其他 section 一样留 14pt，首行停在带下沿 y=40，带内只剩纸色。
    var firstSectionInset: CGFloat = 0
    /// 布局整体顶距。工作区里是 0：第一个 section 之前由 firstSectionInset
    /// 决定，其余 section 之间由 sectionInset.top 决定。
    var topInset: CGFloat = 0
    var itemWidth: CGFloat = 0
    var itemHeight: ((IndexPath) -> CGFloat)?
    var replyStartSection: (() -> Int?)?

    private struct Section {
        var minY: CGFloat
        var maxY: CGFloat
        var items: [UICollectionViewLayoutAttributes]
    }
    private var sections: [Section] = []
    private var contentHeight: CGFloat = 0
    private var needsRebuild = true

    override func invalidateLayout(with context: UICollectionViewLayoutInvalidationContext) {
        needsRebuild = true
        super.invalidateLayout(with: context)
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        abs(newBounds.width - (collectionView?.bounds.width ?? 0)) > 0.5
            || abs(newBounds.height - (collectionView?.bounds.height ?? 0)) > 0.5
    }

    override func prepare() {
        super.prepare()
        guard needsRebuild, let collectionView else { return }
        needsRebuild = false
        var y: CGFloat = topInset
        let x = sectionInset.left
        let sectionCount = collectionView.numberOfSections
        if sections.count > sectionCount { sections.removeLast(sections.count - sectionCount) }
        for section in 0..<sectionCount {
            let count = collectionView.numberOfItems(inSection: section)
            if section >= sections.count { sections.append(Section(minY: 0, maxY: 0, items: [])) }
            // Fresh attribute objects each pass: UIKit compares what it applied to a
            // cell against what the layout returns, so retained objects must not change.
            var items: [UICollectionViewLayoutAttributes] = []
            items.reserveCapacity(count)
            sections[section].minY = y
            y += section == 0 ? firstSectionInset : sectionInset.top
            for item in 0..<count {
                let path = IndexPath(item: item, section: section)
                let height = itemHeight?(path) ?? 0
                let attributes = UICollectionViewLayoutAttributes(forCellWith: path)
                attributes.frame = CGRect(x: x, y: y, width: itemWidth, height: height)
                items.append(attributes)
                y += height
            }
            sections[section].items = items
            y += sectionInset.bottom
            sections[section].maxY = y
        }
        // Leave room below the latest question; a short reply grows in place.
        contentHeight = y
        if let section = replyStartSection?(), sections.indices.contains(section) {
            contentHeight = max(y, sections[section].minY - topInset + collectionView.bounds.height)
        }
    }

    override var collectionViewContentSize: CGSize {
        CGSize(width: collectionView?.bounds.width ?? 0, height: contentHeight)
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard !sections.isEmpty else { return [] }
        // First section whose bottom reaches the rect, then walk until the rect ends.
        var low = 0, high = sections.count - 1
        while low < high {
            let mid = (low + high) / 2
            if sections[mid].maxY < rect.minY { low = mid + 1 } else { high = mid }
        }
        var result: [UICollectionViewLayoutAttributes] = []
        var index = low
        while index < sections.count, sections[index].minY <= rect.maxY {
            for attributes in sections[index].items where attributes.frame.intersects(rect) {
                result.append(attributes)
            }
            index += 1
        }
        return result
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard indexPath.section < sections.count, indexPath.item < sections[indexPath.section].items.count else { return nil }
        return sections[indexPath.section].items[indexPath.item]
    }
}
