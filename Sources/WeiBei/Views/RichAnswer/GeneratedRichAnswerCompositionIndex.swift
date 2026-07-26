import WeiBeiCore

/**
 * 为生成式富回答组合建立只读索引，避免渲染和命中测试反复线性扫描节点、数据集与绑定。
 */
struct GeneratedRichAnswerCompositionIndex {
    let nodes: [RichAnswerUINode]
    let datasets: [RichAnswerUIDataset]
    let bindings: [RichAnswerUIBinding]

    private let nodesByID: [String: RichAnswerUINode]
    private let datasetsByID: [String: RichAnswerUIDataset]
    private let bindingsByID: [String: RichAnswerUIBinding]

    /**
     * 从经过校验的组合创建稳定索引。
     *
     * @param composition - 当前富回答 UI 组合
     */
    init(composition: RichAnswerUIComposition) {
        nodes = composition.nodes
        datasets = composition.datasets
        bindings = composition.bindings
        nodesByID = Dictionary(uniqueKeysWithValues: composition.nodes.map { ($0.id, $0) })
        datasetsByID = Dictionary(uniqueKeysWithValues: composition.datasets.map { ($0.id, $0) })
        bindingsByID = Dictionary(uniqueKeysWithValues: composition.bindings.map { ($0.id, $0) })
    }

    /**
     * 按节点 ID 返回节点。
     */
    func node(id: String) -> RichAnswerUINode? {
        nodesByID[id]
    }

    /**
     * 按数据集 ID 返回数据集。
     */
    func dataset(id: String) -> RichAnswerUIDataset? {
        datasetsByID[id]
    }

    /**
     * 按绑定 ID 返回绑定。
     */
    func binding(id: String) -> RichAnswerUIBinding? {
        bindingsByID[id]
    }
}
