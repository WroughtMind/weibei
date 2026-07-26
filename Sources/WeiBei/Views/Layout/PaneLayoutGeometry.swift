import CoreGraphics

/**
 * 以纯值方式计算工作区 pane 宽度、frame 与 divider frame。
 */
enum PaneLayoutGeometry {
    static let dividerWidth: CGFloat = 10

    /**
     * 根据累计分割比例和最小宽度计算可见 pane 的宽度。
     *
     * @param containerWidth - 工作区总宽度
     * @param dividerWidth - 相邻 pane 之间的分隔条宽度
     * @param cumulativeSplits - 从左侧起累计的分割比例；两栏一个值、三栏两个值
     * @param minimumWidths - 各 pane 的最小宽度
     * @returns 与 minimumWidths 数量一致的 pane 宽度
     */
    static func paneWidths(
        containerWidth: CGFloat,
        dividerWidth: CGFloat,
        cumulativeSplits: [CGFloat],
        minimumWidths: [CGFloat]
    ) -> [CGFloat] {
        let count = minimumWidths.count
        guard count > 0 else { return [] }
        let usable = max(containerWidth - CGFloat(count - 1) * dividerWidth, 1)
        guard count > 1 else { return [usable] }

        let effectiveMinimums = minimumWidths.map { min(max(0, $0), usable / CGFloat(count)) }
        if count == 2 {
            let firstMinimum = effectiveMinimums[0]
            let secondMinimum = effectiveMinimums[1]
            let split = cumulativeSplits.first ?? 0.5
            let first = clamped(split * usable, min: firstMinimum, max: usable - secondMinimum)
            return [first, usable - first]
        }

        let firstMinimum = effectiveMinimums[0]
        let secondMinimum = effectiveMinimums[1]
        let trailingMinimum = effectiveMinimums.dropFirst(2).reduce(0, +)
        let firstSplit = cumulativeSplits.first ?? (1 / CGFloat(count))
        let secondSplit = cumulativeSplits.dropFirst().first ?? (2 / CGFloat(count))
        let first = clamped(firstSplit * usable, min: firstMinimum, max: usable - secondMinimum - trailingMinimum)
        let second = clamped(
            (secondSplit - firstSplit) * usable,
            min: secondMinimum,
            max: usable - first - trailingMinimum
        )
        var widths = [first, second]
        if count > 3 {
            widths.append(contentsOf: effectiveMinimums.dropFirst(2).dropLast())
        }
        widths.append(max(effectiveMinimums.last ?? 0, usable - widths.reduce(0, +)))
        return widths
    }

    /**
     * 将 pane 宽度转换为从左到右的 frame。
     */
    static func paneFrames(
        size: CGSize,
        dividerWidth: CGFloat,
        paneWidths: [CGFloat]
    ) -> [CGRect] {
        var x: CGFloat = 0
        let height = max(size.height, 1)
        return paneWidths.enumerated().map { index, width in
            defer {
                x += width
                if index < paneWidths.count - 1 {
                    x += dividerWidth
                }
            }
            return CGRect(x: x, y: 0, width: max(0, width), height: height)
        }
    }

    /**
     * 根据 pane frame 生成相邻 pane 之间的 divider frame。
     */
    static func dividerFrames(
        paneFrames: [CGRect],
        dividerWidth: CGFloat,
        height: CGFloat
    ) -> [CGRect] {
        paneFrames.dropLast().map { frame in
            CGRect(x: frame.maxX, y: 0, width: dividerWidth, height: max(height, 1))
        }
    }

    /**
     * 将数值限制在可用区间；当上界低于下界时以下界为准。
     */
    private static func clamped(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, minimum), Swift.max(minimum, maximum))
    }
}
