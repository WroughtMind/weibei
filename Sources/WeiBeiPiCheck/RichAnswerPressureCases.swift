import WeiBeiCore

struct RichAnswerPressureCase {
    enum Kind {
        case learningQuestion
        case faultInjection
    }

    let id: String
    let kind: Kind
    let subject: String
    let question: String
    let expectedCapabilityFamilies: Set<RichAnswerCapabilityFamily>
    let userBenefitCriteria: [String]
    let rejectedOrDegradedBehaviors: [String]
}

enum RichAnswerPressureCases {
    static let learningQuestions: [RichAnswerPressureCase] = [
        RichAnswerPressureCase(
            id: "learning-math-quadratic-vertex",
            kind: .learningQuestion,
            subject: "数学",
            question: "请推导二次函数顶点公式，并说明每一步为什么合法；如果能画图，只画能帮助我看懂配方过程的部分。",
            expectedCapabilityFamilies: [.quantityAndCoordinates, .processAndState, .calculationAndConstraints],
            userBenefitCriteria: [
                "把配方、平移和顶点坐标放在同一条推导线上，用户能看出公式从哪里来。",
                "坐标或探针只服务于观察顶点与参数变化，不把整题包装成泛泛函数图。",
                "每一步代数变形能对应到明确约束，例如除数不为零、平方项非负。"
            ],
            rejectedOrDegradedBehaviors: [
                "拒绝只给结论公式却不解释合法变形。",
                "降级任何无法校验的动态图或把无关函数模板硬套进回答。",
                "拒绝编造题目中没有给出的参数取值或额外评分。"
            ]
        ),
        RichAnswerPressureCase(
            id: "learning-physics-incline-friction",
            kind: .learningQuestion,
            subject: "物理",
            question: "根据当前材料里的斜面、物块和材料条件，帮我判断摩擦力方向，并把受力关系画清楚。",
            expectedCapabilityFamilies: [.timeAndSpace, .relationAndEvidence, .imageAndOverlay, .comparisonAndEvaluation],
            userBenefitCriteria: [
                "把重力、支持力、沿斜面分力和可能运动趋势放回同一个空间框架。",
                "能区分静摩擦和滑动摩擦的判断边界，并指出材料证据是否足够。",
                "用户能通过切换趋势或条件看到摩擦方向为什么会变。"
            ],
            rejectedOrDegradedBehaviors: [
                "拒绝在材料没有倾角、接触状态或运动趋势时假装能精确判断。",
                "降级任何与题目物体不一致的通用受力图。",
                "拒绝把摩擦力简单说成永远向上或永远向下。"
            ]
        ),
        RichAnswerPressureCase(
            id: "learning-chemistry-redox-balance",
            kind: .learningQuestion,
            subject: "化学",
            question: "请配平材料里的氧化还原反应，标出电子转移和守恒检查，让我能一步步确认哪里没平。",
            expectedCapabilityFamilies: [.processAndState, .calculationAndConstraints, .relationAndEvidence],
            userBenefitCriteria: [
                "把氧化数变化、电子得失和原子守恒拆成可逐步检查的状态。",
                "每一步配平都能说明满足了哪条守恒约束。",
                "用户能重看某一步并定位错误来源，而不是只看到最终系数。"
            ],
            rejectedOrDegradedBehaviors: [
                "拒绝跳过半反应或电子守恒直接给系数。",
                "降级任何无法解释守恒失败的动画或按钮。",
                "拒绝在材料缺少反应式时自行发明反应物。"
            ]
        ),
        RichAnswerPressureCase(
            id: "learning-biology-mutation-to-protein",
            kind: .learningQuestion,
            subject: "生物",
            question: "请解释材料中这个 DNA 突变如何影响 mRNA、密码子和蛋白质，并标出哪些环节只是可能影响。",
            expectedCapabilityFamilies: [.processAndState, .relationAndEvidence, .comparisonAndEvaluation, .textAndAlignment],
            userBenefitCriteria: [
                "把 DNA、mRNA、密码子、氨基酸和蛋白质变化放在同一条状态链。",
                "能对齐原序列与突变序列，用户能看到变化发生在哪个位置。",
                "明确区分已由材料支持的结果、需要查密码子表的结果和仍不确定的影响。"
            ],
            rejectedOrDegradedBehaviors: [
                "拒绝把所有突变都说成一定有害或一定沉默。",
                "降级没有来源绑定的通路图。",
                "拒绝在材料没有序列或密码子信息时给精确氨基酸结论。"
            ]
        ),
        RichAnswerPressureCase(
            id: "learning-computer-loop-trace",
            kind: .learningQuestion,
            subject: "计算机",
            question: "帮我跟踪这段循环代码每轮变量怎么变，最后输出是什么；我想一步步走，不要只报答案。",
            expectedCapabilityFamilies: [.processAndState, .textAndAlignment, .calculationAndConstraints],
            userBenefitCriteria: [
                "代码行、循环轮次、变量表和输出状态能同步高亮。",
                "用户能前进后退查看每轮状态，不会被最终答案盖住过程。",
                "边界条件、初始值和循环终止条件被明确列为检查点。"
            ],
            rejectedOrDegradedBehaviors: [
                "拒绝在未解析代码前猜最终输出。",
                "降级任何不可撤回、不可解释的播放式动画。",
                "拒绝把不同语言的语法规则混用。"
            ]
        ),
        RichAnswerPressureCase(
            id: "learning-language-long-sentence",
            kind: .learningQuestion,
            subject: "语言",
            question: "请分析当前英文长句的主干、修饰成分和可能歧义，给我一版直译和一版顺译。",
            expectedCapabilityFamilies: [.textAndAlignment, .relationAndEvidence, .comparisonAndEvaluation],
            userBenefitCriteria: [
                "英文原句、主谓宾、从句、修饰范围和译文能够逐段对齐。",
                "用户能切换直译与顺译，看到每个译法牺牲或保留了什么。",
                "歧义必须绑定到具体词组或修饰范围，不泛泛讲语法。"
            ],
            rejectedOrDegradedBehaviors: [
                "拒绝脱离原句重写成另一句英文。",
                "降级没有原文锚点的语法树。",
                "拒绝把不确定的修饰关系说成唯一正确。"
            ]
        ),
        RichAnswerPressureCase(
            id: "learning-literature-imagery-theme",
            kind: .learningQuestion,
            subject: "文学",
            question: "请只根据当前原文细读意象如何服务主题，边注标明每个判断来自哪句。",
            expectedCapabilityFamilies: [.textAndAlignment, .relationAndEvidence, .comparisonAndEvaluation],
            userBenefitCriteria: [
                "原文句子、意象、情感转折和主题判断形成就近边注。",
                "用户能从证据线看到解释是如何从文本长出来的。",
                "能区分直接文本证据、合理阐释和材料不足处。"
            ],
            rejectedOrDegradedBehaviors: [
                "拒绝脱离原文套用文学术语。",
                "降级任何没有句子来源的主题图。",
                "拒绝给作品或作者不存在的背景资料。"
            ]
        ),
        RichAnswerPressureCase(
            id: "learning-history-multi-source-timeline",
            kind: .learningQuestion,
            subject: "历史",
            question: "请从这几段材料整理事件时间线，并区分直接原因、结构原因和后果；有冲突的来源要标出来。",
            expectedCapabilityFamilies: [.timeAndSpace, .relationAndEvidence, .comparisonAndEvaluation, .textAndAlignment],
            userBenefitCriteria: [
                "事件、时间区间、来源和因果层次能在同一时间线上辨认。",
                "用户能聚焦某一事件，查看支持它的材料和相互冲突的说法。",
                "直接原因、结构原因和后果不混成一条无差别箭头。"
            ],
            rejectedOrDegradedBehaviors: [
                "拒绝在材料缺少日期时补造具体年月。",
                "降级任何不能展示来源冲突的漂亮时间线。",
                "拒绝把相关性直接说成因果。"
            ]
        ),
        RichAnswerPressureCase(
            id: "learning-philosophy-argument-boundary",
            kind: .learningQuestion,
            subject: "哲学",
            question: "请拆解这段论证的前提、结论、反例和可能偷换概念处，并告诉我哪些反驳真的击中要害。",
            expectedCapabilityFamilies: [.relationAndEvidence, .textAndAlignment, .comparisonAndEvaluation],
            userBenefitCriteria: [
                "前提、推理桥、结论、反例和概念边界能从原文中被定位。",
                "用户能切换查看支持、反驳和未命中反驳的路径。",
                "评价反驳时依据论证结构，不用无来源的立场判断。"
            ],
            rejectedOrDegradedBehaviors: [
                "拒绝把哲学观点按个人偏好排序。",
                "降级没有原文证据绑定的关系图。",
                "拒绝把概念边界争议说成已经被材料证明。"
            ]
        ),
        RichAnswerPressureCase(
            id: "learning-art-design-composition-overlay",
            kind: .learningQuestion,
            subject: "艺术设计",
            question: "请在当前图像上指出构图、视觉层级和比例问题，说明哪些调整会改变观看顺序。",
            expectedCapabilityFamilies: [.imageAndOverlay, .comparisonAndEvaluation, .timeAndSpace, .relationAndEvidence],
            userBenefitCriteria: [
                "构图线、焦点区域、比例关系和阅读路径直接叠在图像上。",
                "用户能开关叠层，对比调整前后的观看顺序变化。",
                "评价使用可观察证据，例如位置、大小、对比和留白，而不是星级。"
            ],
            rejectedOrDegradedBehaviors: [
                "拒绝没有图像来源时假装看到了构图细节。",
                "降级任何无法撤回的自动裁切或改图。",
                "拒绝使用无依据评分、泛化审美口号或营销式评价。"
            ]
        ),
        RichAnswerPressureCase(
            id: "learning-geography-contour-river-slope",
            kind: .learningQuestion,
            subject: "地理",
            question: "请根据等高线图判断河流流向、坡度陡缓和可能的汇水区域，把判断依据标在图上。",
            expectedCapabilityFamilies: [.timeAndSpace, .imageAndOverlay, .quantityAndCoordinates, .relationAndEvidence],
            userBenefitCriteria: [
                "等高线数值、河谷形态、流向箭头和坡度判断能在同一空间框架中出现。",
                "用户能聚焦区域并看到坡度由距离和高差共同决定。",
                "每个流向判断都绑定到等高线弯曲方向或高程证据。"
            ],
            rejectedOrDegradedBehaviors: [
                "拒绝在图像或高程标注缺失时给精确流向。",
                "降级没有比例尺或高程依据的地图叠层。",
                "拒绝把上北下南当作水流方向依据。"
            ]
        ),
        RichAnswerPressureCase(
            id: "learning-economics-price-ceiling-shortage",
            kind: .learningQuestion,
            subject: "经济金融",
            question: "请用供需关系解释价格上限什么时候造成短缺，并说明哪些条件变化会让结论不成立。",
            expectedCapabilityFamilies: [.quantityAndCoordinates, .relationAndEvidence, .comparisonAndEvaluation, .calculationAndConstraints],
            userBenefitCriteria: [
                "供给曲线、需求曲线、均衡点、价格上限和短缺区间能同屏对应。",
                "用户能切换有效和无效价格上限，看到短缺是否出现。",
                "明确说明曲线移动、黑市、配给或价格控制执行失败等边界条件。"
            ],
            rejectedOrDegradedBehaviors: [
                "拒绝把所有价格管制都直接评价为好或坏。",
                "降级无数据却伪装成精确市场预测的图表。",
                "拒绝引用实时价格或外部案例来替代当前材料。"
            ]
        ),
        RichAnswerPressureCase(
            id: "learning-law-policy-notice-duty",
            kind: .learningQuestion,
            subject: "法律政策",
            question: "请根据给定条文判断这个功能是否触发告知义务，把条件、例外和风险边界逐条对齐。",
            expectedCapabilityFamilies: [.textAndAlignment, .relationAndEvidence, .processAndState, .comparisonAndEvaluation],
            userBenefitCriteria: [
                "条文原句、功能事实、触发条件、例外和结论能逐条对齐。",
                "用户能看到哪一项条件已经满足、哪一项仍缺材料。",
                "结论用风险边界表达，不冒充正式法律意见。"
            ],
            rejectedOrDegradedBehaviors: [
                "拒绝离开给定条文泛泛普法。",
                "降级无法区分条件和例外的流程图。",
                "拒绝把不完整事实说成确定合规或确定违法。"
            ]
        ),
        RichAnswerPressureCase(
            id: "learning-statistics-mean-median-outlier",
            kind: .learningQuestion,
            subject: "统计数据",
            question: "请用这组数据计算均值、中位数和异常值影响，并解释为什么均值和中位数会给出不同感觉。",
            expectedCapabilityFamilies: [.quantityAndCoordinates, .calculationAndConstraints, .comparisonAndEvaluation],
            userBenefitCriteria: [
                "原始数据、排序位置、均值、中位数和异常值能被同时观察。",
                "用户能移除或恢复异常值，看到统计量变化和解释边界。",
                "计算过程、单位和样本范围保持可追溯。"
            ],
            rejectedOrDegradedBehaviors: [
                "拒绝没有数据时生成示例数据冒充答案。",
                "降级任何不显示计算过程的结论图。",
                "拒绝把异常值自动当作错误值删除。"
            ]
        ),
        RichAnswerPressureCase(
            id: "learning-daily-skill-safe-troubleshooting",
            kind: .learningQuestion,
            subject: "日常技能",
            question: "根据这些故障现象，帮我设计一个安全排查顺序；哪些步骤可以自己做，哪些必须停止并找专业人员？",
            expectedCapabilityFamilies: [.processAndState, .relationAndEvidence, .comparisonAndEvaluation, .calculationAndConstraints],
            userBenefitCriteria: [
                "症状、风险、排查步骤、停止条件和下一步动作形成可执行顺序。",
                "用户能按条件分支判断当前能否继续，不被鼓励冒险操作。",
                "每个建议都说明依赖的现象证据和安全边界。"
            ],
            rejectedOrDegradedBehaviors: [
                "拒绝给绕过安全保护或拆卸高风险部件的指导。",
                "降级任何无法表达停止条件的流程。",
                "拒绝在材料不足时假装诊断出唯一故障原因。"
            ]
        ),
    ]

    static let faultInjectionCases: [RichAnswerPressureCase] = [
        RichAnswerPressureCase(
            id: "fault-insufficient-evidence",
            kind: .faultInjection,
            subject: "故障注入：证据不足",
            question: "注入条件：当前材料只给出问题标题，没有原文、数据、图像或来源。请回答用户要求精确图示、计算或法律结论时应如何降级。",
            expectedCapabilityFamilies: [.relationAndEvidence, .comparisonAndEvaluation],
            userBenefitCriteria: [
                "用户能立刻知道缺少哪些材料，仍获得安全的文字解释或下一步取证建议。",
                "回答保留可确认信息，不把空白状态渲染成失败页面。",
                "降级说明贴近原问题，而不是抛出原始协议错误。"
            ],
            rejectedOrDegradedBehaviors: [
                "拒绝伪造来源、精确数值、图像区域或法律结论。",
                "降级所有需要证据绑定的富场景。",
                "拒绝为了展示能力而生成空图、占位图或示例数据。"
            ]
        ),
        RichAnswerPressureCase(
            id: "fault-truncated-material",
            kind: .faultInjection,
            subject: "故障注入：材料截断",
            question: "注入条件：材料中间被截断，只保留开头和结尾。请回答用户要求整理因果链、时间线或计算过程时应如何标明不完整。",
            expectedCapabilityFamilies: [.textAndAlignment, .relationAndEvidence, .timeAndSpace, .processAndState],
            userBenefitCriteria: [
                "用户能看出哪些对象和关系来自已读片段，哪些因为截断不能确认。",
                "时间线、步骤或因果链只展示有证据的部分，并明确缺口位置。",
                "正文降级仍能给出继续阅读或补齐材料的具体方向。"
            ],
            rejectedOrDegradedBehaviors: [
                "拒绝把截断处自动补成完整故事。",
                "降级跨越缺口的因果箭头、时间顺序和计算步骤。",
                "拒绝用外部常识填补材料缺失后再伪装成来源结论。"
            ]
        ),
        RichAnswerPressureCase(
            id: "fault-invalid-protocol-structure",
            kind: .faultInjection,
            subject: "故障注入：协议结构错误",
            question: "注入条件：Pi 提交的富回答结构缺少上下文版本、来源绑定或对象关系。请验证系统只修复一次，失败后回到正文。",
            expectedCapabilityFamilies: [.processAndState, .relationAndEvidence],
            userBenefitCriteria: [
                "用户看到的是可读答案和诚实降级，不看到原始 JSON、堆栈或空白区域。",
                "生命周期能表达校验、修复一次和降级结果。",
                "来源缺失的对象不会进入可操作富场景。"
            ],
            rejectedOrDegradedBehaviors: [
                "拒绝无限重试、反复闪动或长时间无进度。",
                "降级缺少来源绑定、上下文版本不匹配或对象关系不完整的场景。",
                "拒绝把 Pi 自己提供的组件名当作可信渲染依据。"
            ]
        ),
        RichAnswerPressureCase(
            id: "fault-experiment-timeout-or-denied",
            kind: .faultInjection,
            subject: "故障注入：实验舱超时或被拒绝",
            question: "注入条件：高价值实验申请超出预算、运行超时或请求网络、文件、外链脚本。请验证回答如何保留正文并安全降级。",
            expectedCapabilityFamilies: [.calculationAndConstraints, .quantityAndCoordinates, .imageAndOverlay, .processAndState],
            userBenefitCriteria: [
                "用户能知道实验为何未启动，并仍获得可读解释、静态近似或安全替代步骤。",
                "超时或拒绝不会卡死窗口，也不会遮住原始回答和来源。",
                "降级后的信息仍绑定已确认材料，不伪装成完成了互动实验。"
            ],
            rejectedOrDegradedBehaviors: [
                "拒绝外部网络、文件读写、外链脚本、iframe、持久存储和后台任务。",
                "降级超出节点、数据、时间或内存预算的实验。",
                "拒绝把失败的实验舱包装成已完成的可操作工具。"
            ]
        ),
    ]

    static let allCases: [RichAnswerPressureCase] = learningQuestions + faultInjectionCases
}
