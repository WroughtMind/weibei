import Foundation
import WeiBeiCore

func runRichAnswerProtocolSelfCheck() throws {
    try RichAnswerPythonArtifactSelfCheck.runStaticChecks()
    try checkRichAnswerInlineMathDisplayNormalization()
    try checkOpenUIProgramRenders()
    try checkNarrativeAndScenesFormOneInlineFlow()
    try checkOpenUIProgramRejectsUnsafeVariants()
    try checkGeneratedUITreeRenders()
    try checkGeneratedUISequencePrimitiveRenders()
    try checkGeneratedUITreeRejectsUnboundEvidenceAndFalseFamily()
    try checkGeneratedUITreeRejectsMalformedProtocol()
    try checkGeneratedUITreeRejectsPseudoInteractionAndMissingObligations()
    try checkProfessionalJudgmentContractsRejectReverseClaims()
    try checkTitrationProfessionalJudgmentRegressions()
    try checkArtColorContrastObligationsDoNotRequireHash()
    try checkProfessionalJudgmentObservedLanguageVariants()
    try checkProfessionalJudgmentIgnoresEvidenceCitations()
    try checkGeneratedUITreeIntentQualityContracts()
    try checkComposablePendulumRendersWithoutSpecializedComponent()
    try checkGeneratedUITreeRejectsCycles()
    try checkGeneratedUITreeAllowsCoordinatedControls()
    try checkAcceptedInteractiveScene()
    try checkFamilySpecificContracts()
    try checkStaleEvidenceFallsBackToNarrative()
    try checkBrokenReferencesDropOnlyTheirScene()
    try checkRawWebPayloadIsRejected()
    try checkDirectManipulationPlanMatchesOperations()
    try checkImageRegionsStayInsideTheirFrame()
    try checkTruncatedEvidenceStaysVisibleAsPartial()
    try checkDefaultSceneBudgetIsBounded()
    try checkAssetAliasesResolveBeforePersistence()
    try richAnswerRequire(
        RichAnswerCapabilityFamily.allCases.count == 8,
        "the first protocol covers all eight rich-answer capability families"
    )
    try richAnswerRequire(
        RichAnswerPressureCases.learningQuestions.count == 40
            && RichAnswerPressureCases.faultInjectionCases.count == 10,
        "the pressure matrix keeps forty learning cases and ten controlled failures"
    )
}

private func checkRichAnswerInlineMathDisplayNormalization() throws {
    let source = #"小角度近似：\(T=2\pi\sqrt{L/g}\)，摆长加倍时周期乘以 \(\sqrt2\)，且 \(a\le b\)。回归：\(y_i=\hat y_i+\hat u_i\)，\(\sum \hat u_i=0\)。"#
    let display = RichAnswerDisplayText.normalizedInlineMath(source)
    try richAnswerRequire(
        display.contains("T=2π√(L/g)")
            && display.contains("√2")
            && display.contains("a≤b")
            && display.contains("∑")
            && display.contains("\u{0302}")
            && !display.contains(#"\sqrt"#)
            && !display.contains(#"\("#)
            && !display.contains(#"\hat"#)
            && !display.contains(#"\sum"#),
        "inline rich-answer math displays as readable text without leaking LaTeX delimiters: \(display)"
    )

    let olsSource = #"OLS 核对：\hat y=1.44+0.8x，Cov_n(x,\hat u)=0，(\bar x,\bar y) 在回归线上，且 \bar{\hat u}=0、\sum_i \hat u_i=0。"#
    let olsDisplay = RichAnswerDisplayText.normalizedInlineMath(olsSource)
    try richAnswerRequire(
        olsDisplay.contains("ŷ=1.44+0.8x")
            && olsDisplay.contains("Covₙ(x,û)=0")
            && olsDisplay.contains("(x̄,ȳ)")
            && olsDisplay.contains("û̄=0")
            && olsDisplay.contains("Σᵢ ûᵢ=0")
            && !olsDisplay.contains(#"\hat"#)
            && !olsDisplay.contains(#"\bar"#),
        "OLS rich-answer math displays hats, bars, sums, and subscripts without raw LaTeX: \(olsDisplay)"
    )

    let markdownSource = """
    正文：\\hat y 与 \\bar x。

    行内代码 `\\hat y` 不改。

    ```latex
    \\hat y = \\bar x
    ```
    """
    let markdownDisplay = RichAnswerDisplayText.normalizedMarkdownInlineMath(markdownSource)
    try richAnswerRequire(
        markdownDisplay.contains("正文：ŷ 与 x̄。")
            && markdownDisplay.contains("行内代码 `\\hat y` 不改。")
            && markdownDisplay.contains("```latex\n\\hat y = \\bar x\n```"),
        "assistant markdown normalizes visible formulas without altering inline or fenced code: \(markdownDisplay)"
    )
}

private func checkProfessionalJudgmentContractsRejectReverseClaims() throws {
    try RichAnswerLiveCases.assertMatrixMatchesPressureCases()
    let casesWithoutReverseContracts = RichAnswerLiveCases.successes.filter {
        $0.professionalJudgmentContract.forbiddenMisconceptions.isEmpty
    }.map(\.id)
    try richAnswerRequire(
        casesWithoutReverseContracts.isEmpty,
        "all forty success cases declare reverse-misconception contracts"
    )
    let casesWithoutRequiredClaims = RichAnswerLiveCases.successes.filter {
        $0.professionalJudgmentContract.requiredClaims.isEmpty
            && $0.professionalFactObligations.isEmpty
    }.map(\.id)
    try richAnswerRequire(
        casesWithoutRequiredClaims.isEmpty,
        "all forty success cases declare positive professional obligations"
    )

    let economicsCase = try liveSuccessCase("learning-economics-price-ceiling-shortage")
    let reversedEconomicsText = """
    均衡 P=20，价格上限、短缺、20 这些关键词都出现。价格上限15会形成短缺20。价格上限25会产生短缺，上限越高短缺越严重。结论只适用于给定曲线和有效执行。
    """
    let reversedEconomicsValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: reversedEconomicsText,
        contract: economicsCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        !reversedEconomicsValidation.passedDeterministicGates
            && reversedEconomicsValidation.triggeredForbiddenClaims.contains("ceiling-25-shortage"),
        "keyword-complete economics answer fails when the nonbinding ceiling conclusion is reversed"
    )
    let correctEconomicsText = """
    均衡价格为 P=20。价格上限15低于均衡，会形成短缺20。价格上限25高于均衡，不形成约束，也不会由该上限产生短缺。结论只适用于给定曲线和有效执行。
    """
    let correctEconomicsValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: correctEconomicsText,
        contract: economicsCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        correctEconomicsValidation.passedDeterministicGates,
        "correct economics claim passes the same professional judgment contract"
    )

    let medicineCase = try liveSuccessCase("learning-medicine-cardiac-cycle")
    let reversedMedicineText = """
    S1、S2、房室瓣、半月瓣、压力、学习、诊断这些关键词都出现。S1对应半月瓣关闭，S2对应房室瓣关闭；材料用于生理学习，不足以诊断个体。
    """
    let reversedMedicineValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: reversedMedicineText,
        contract: medicineCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        !reversedMedicineValidation.passedDeterministicGates
            && reversedMedicineValidation.triggeredForbiddenClaims.contains("s1-semilunar")
            && reversedMedicineValidation.triggeredForbiddenClaims.contains("s2-av"),
        "keyword-complete cardiac answer fails when S1 and S2 valve claims are swapped"
    )
    let correctMedicineText = """
    S1对应房室瓣关闭；S2对应半月瓣关闭；压力交叉触发瓣膜开闭。材料用于生理学习，不足以诊断个体心脏问题。
    """
    let correctMedicineValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: correctMedicineText,
        contract: medicineCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        correctMedicineValidation.passedDeterministicGates,
        "correct cardiac valve claims pass the same professional judgment contract"
    )

    let biologyCase = try liveSuccessCase("learning-biology-mutation-to-protein")
    let correctBiologyText = """
    TAA 转录后对应 mRNA UAA；GAA 编码谷氨酸，UAA 是终止密码子；功能影响取决于突变位置和蛋白结构。
    """
    let correctBiologyValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: correctBiologyText,
        contract: biologyCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        correctBiologyValidation.passedDeterministicGates,
        "correct codon contrast keeps GAA-glutamate separate from UAA-stop"
    )
    let wrongBiologyText = """
    TAA 转录后对应 mRNA UAA；UAA 是终止密码子，但也编码谷氨酸；功能影响取决于突变位置和蛋白结构。
    """
    let wrongBiologyValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: wrongBiologyText,
        contract: biologyCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        !wrongBiologyValidation.passedDeterministicGates
            && wrongBiologyValidation.triggeredForbiddenClaims.contains("uaa-glutamate"),
        "false UAA-glutamate claim still fails when attached to the UAA subject"
    )

    let safetyCase = try liveSuccessCase("learning-daily-skill-safe-troubleshooting")
    let correctSafetyText = """
    发热和绝缘裂口触发必须先断电停止使用；不要用胶带包好继续带电测试；适配器后续应更换或交由专业人员检查；只允许完全断电后的非侵入检查。
    """
    let correctSafetyValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: correctSafetyText,
        contract: safetyCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        correctSafetyValidation.passedDeterministicGates,
        "safety prohibition of live tape testing passes instead of triggering the forbidden action"
    )
    let wrongSafetyText = """
    发热和绝缘裂口触发必须先断电停止使用，但也可以用胶带包好继续带电测试；适配器后续应更换或交由专业人员检查；只允许完全断电后的非侵入检查。
    """
    let wrongSafetyValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: wrongSafetyText,
        contract: safetyCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        !wrongSafetyValidation.passedDeterministicGates
            && wrongSafetyValidation.triggeredForbiddenClaims.contains("tape-live-test"),
        "actual live tape testing advice still fails"
    )
    let coordinatedSafetyList = """
    发热加绝缘裂口必须先断电并停止使用；自己不要弯折裂口、拆开适配器或用胶带继续带电测试；后续应更换合规适配器或交由专业人员检查；只允许完全断电后的非侵入检查。
    """
    let coordinatedSafetyValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: coordinatedSafetyList,
        contract: safetyCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        coordinatedSafetyValidation.triggeredForbiddenClaims.isEmpty,
        "one prohibition must keep its scope across a coordinated unsafe-action list"
    )
    let compressedSafetyStepValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: "步骤 2：禁止继续试：不弯折、不拆开、不胶带带电测试。",
        contract: safetyCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        compressedSafetyStepValidation.triggeredForbiddenClaims.isEmpty,
        "a compact negated action label must not be reclassified as the unsafe positive action"
    )
    let coordinatedCannotSafetyValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: "材料进一步把可做与不可做分开：但不能弯折裂口、拆开适配器或用胶带继续带电测试。",
        contract: safetyCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        coordinatedCannotSafetyValidation.triggeredForbiddenClaims.isEmpty,
        "cannot must keep its prohibition scope across a coordinated unsafe-action list"
    )
    let observedSafetyClassificationValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: "拆开适配器、带电测试、用胶带继续使用都不属于安全排查；禁止：弯折裂口/拆开/胶带带电测试。",
        contract: safetyCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        observedSafetyClassificationValidation.triggeredForbiddenClaims.isEmpty,
        "an observed answer that classifies live tape testing outside safe troubleshooting must not be treated as advice to do it"
    )
    let stopIncludesSafetyValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: "必须停止的包括弯折裂口、拆开适配器、用胶带包住后继续带电测试；后续更换合规适配器或交由专业人员检查。",
        contract: safetyCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        stopIncludesSafetyValidation.triggeredForbiddenClaims.isEmpty,
        "must-stop language must keep its prohibition scope across the following coordinated unsafe actions"
    )

    let pendulumCase = try liveSuccessCase("learning-physics-pendulum-length-period")
    let wrongPendulumWithUnrelatedNegation = """
    材料未说明空气阻力；周期与摆长本身成正比。摆长加倍时周期乘以 √2，小角度近似只适用于较小初始角。
    """
    let wrongPendulumValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: wrongPendulumWithUnrelatedNegation,
        contract: pendulumCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        wrongPendulumValidation.triggeredForbiddenClaims.contains("period-proportional-length"),
        "an unrelated earlier negation must not hide a later false pendulum proposition"
    )
    let correctPendulumWithInlineBoundary = """
    T 与 √L 成正比；摆长加倍时周期乘以 √2。适用范围：小角度近似；初始角超过约 10° 后误差会增大。
    """
    let correctPendulumValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: correctPendulumWithInlineBoundary,
        contract: pendulumCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        correctPendulumValidation.passedDeterministicGates,
        "a square-root relation must not be misread as direct proportionality, and an explicit applicability range satisfies the boundary contract: forbidden=\(correctPendulumValidation.triggeredForbiddenClaims.joined(separator: ",")) boundary=\(correctPendulumValidation.missingBoundaryClaims.joined(separator: ","))"
    )
    let latexPendulumValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: #"小角度近似下，T 随 \(\sqrt{L}\) 增大，按平方根增长；摆长加倍时周期乘以 \(\sqrt2\)，而不是加倍。"#,
        contract: pendulumCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        latexPendulumValidation.missingRequiredClaims.isEmpty
            && latexPendulumValidation.triggeredForbiddenClaims.isEmpty,
        "correct LaTeX square-root notation and equivalent growth wording satisfy the same pendulum claims: missing=\(latexPendulumValidation.missingRequiredClaims.joined(separator: ",")) forbidden=\(latexPendulumValidation.triggeredForbiddenClaims.joined(separator: ","))"
    )
    let negatedRootRelationValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: "周期 T 与 √L 并非成正比；摆长加倍时周期乘以 √2。适用范围是小角度近似。",
        contract: pendulumCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        negatedRootRelationValidation.missingRequiredClaims.contains("period-square-root-length"),
        "a negation scoped inside the square-root claim must still reject that required professional relation"
    )

    let rcCase = try liveSuccessCase("learning-physics-rc-circuit-transient")
    let correctRCText = """
    RC 充电时 Vc 上升、电流 I 下降。时间常数 τ=1.0 s，t=τ 时 Vc≈3.16 V；5τ 只是接近稳态，并非精确到达。
    """
    let correctRCValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: correctRCText,
        contract: rcCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        correctRCValidation.triggeredForbiddenClaims.isEmpty,
        "correct RC charge directions do not satisfy the reverse-direction contract"
    )
    let liveRCValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: "结论：RC 充电时，电容电压 Vc 上升、电流 I 下降，不是两个互相独立的过程，而是同一个时间常数。",
        contract: rcCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        !liveRCValidation.triggeredForbiddenClaims.contains("current-up-during-charge"),
        "a relation bound to Vc must not drift across a comma onto the later current subject"
    )
    let fullLiveRCValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: """
        结论：RC 充电时，电容电压 Vc 上升、电流 I 下降，不是两个互相独立的过程，而是同一个时间常数 τ=RC=1.0 s 在控制：Vc(t)=5(1-e^{-t/τ}) 逐渐补上“还没充到 5V 的差额”，I(t)=(5/R)e^{-t/τ} 则按同一个指数项衰减。[材料：RC 充电过程材料][选区：电压上升与电流下降]
        拖动下面的 t/τ，会看到 Vc 的点沿上升曲线走、I 的点沿下降曲线走；在 t=τ 处，材料给出的标志读数是 Vc≈3.16 V，电流约为初值的 36.8%。
        所以“一个上升一个下降”的根本原因是：随着电容电压升高，电阻两端可用来推动电流的电压差变小；公式上就表现为 I 保留 e^{-t/τ} 这一项，而 Vc 是 5V 乘以 1 减去同一项。到 5τ 时只是接近稳态，并不是数学上精确到达。
        """,
        contract: rcCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        !fullLiveRCValidation.triggeredForbiddenClaims.contains("current-up-during-charge"),
        "the full live RC explanation must preserve predicate ownership across all clauses"
    )

    let compositionCase = try liveSuccessCase("learning-art-design-composition-overlay")
    let nominalCompositionValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: "阅读顺序先落到白色大星体与橙色小星体的双焦点，再进入下方宇航员。",
        contract: compositionCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        !nominalCompositionValidation.missingRequiredClaims.contains("two-star-focus"),
        "a valid nominal attribution can express the two-star focus without a fixed copular verb"
    )
    let negatedCompositionValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: "白色大星体与橙色小星体并非双焦点。",
        contract: compositionCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        negatedCompositionValidation.missingRequiredClaims.contains("two-star-focus"),
        "removing the fixed verb must not let a negated nominal attribution pass"
    )
    let liveCompositionValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: "叠图提示：三分线看比例，箭头看观看顺序；切换后只改变路径假设，不改变原图。白色大星体与橙色小星体形成双焦点。",
        contract: compositionCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        !liveCompositionValidation.missingRequiredClaims.contains("two-star-focus"),
        "the live image-overlay wording must satisfy the semantic focus obligation without fixed prose"
    )
    let qualifiedRCContrastValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: "充电时 Vc 上升，放电时 Vc 下降。",
        contract: rcCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        !qualifiedRCContrastValidation.triggeredForbiddenClaims.contains("vc-down-during-charge"),
        "a new explicit qualifier must stop the previous qualifier from drifting into the next clause"
    )
    let negatedRCMisconceptionValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: "充电时 Vc 不下降而是上升，电流 I 下降；5τ 只是接近稳态，并非精确到达。",
        contract: rcCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        !negatedRCMisconceptionValidation.triggeredForbiddenClaims.contains("vc-down-during-charge"),
        "a negation scoped to the reverse Vc predicate must refute that forbidden claim"
    )
    let observedRCNotEqualValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: "5τ：接近稳态，未精确到达；5τ：接近稳态≠精确到达。",
        contract: rcCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        !observedRCNotEqualValidation.triggeredForbiddenClaims.contains("five-tau-exact"),
        "a visible not-equal symbol must retain negative polarity in an observed RC scene label"
    )
    let rcWrongAfterReminderValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: "不要只看读数，充电时电流 I 会上升。",
        contract: rcCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        rcWrongAfterReminderValidation.triggeredForbiddenClaims.contains("current-up-during-charge"),
        "a reminder separated by a comma must not negate a later independent false proposition"
    )
    let rcDoubleNegationValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: "5 tau 不是不能完全到达稳态，而是完全到达稳态。",
        contract: rcCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        rcDoubleNegationValidation.triggeredForbiddenClaims.contains("five-tau-exact"),
        "double negation plus an adversative restatement must not hide exact steady-state arrival"
    )
    let rcSymbolBoundaryValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: "充电时 Pi 的估计会上升。",
        contract: rcCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        !rcSymbolBoundaryValidation.triggeredForbiddenClaims.contains("current-up-during-charge"),
        "a single-letter current symbol must not match inside another identifier"
    )
    let wrongRCText = """
    RC 充电时 Vc 下降、电流 I 上升。时间常数 τ=1.0 s，t=τ 时 Vc≈3.16 V；5τ 只是接近稳态，并非精确到达。
    """
    let wrongRCValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: wrongRCText,
        contract: rcCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        wrongRCValidation.triggeredForbiddenClaims.contains("vc-down-during-charge")
            && wrongRCValidation.triggeredForbiddenClaims.contains("current-up-during-charge"),
        "actual RC reverse directions still fail as two bound propositions"
    )

    let doubleSlitCase = try liveSuccessCase("learning-physics-double-slit-interference")
    let doubleSlitWrongAfterUnrelatedNegation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: "材料未标出修正项，但缝距 d 增大时条纹变疏。",
        contract: doubleSlitCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        doubleSlitWrongAfterUnrelatedNegation.triggeredForbiddenClaims.contains("d-larger-sparser"),
        "an unrelated negation before an adversative clause must not hide a later false proposition"
    )
    let relationFirstDiffractionValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: "不能忽略边界，但这里仍可精确画出衍射包络。",
        contract: doubleSlitCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        relationFirstDiffractionValidation.triggeredForbiddenClaims.contains("precise-diffraction-envelope"),
        "relation-first wording and overlapping envelope anchors must still trigger the diffraction boundary error"
    )
    let correctDoubleSlitValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: "λ 或 L 增大时 Δx 增大，亮纹更疏；d 增大时 Δx 减小，亮纹更密。当前参数下 Δx≈3.0 mm；只在小角度近似下使用，且材料没有给单缝宽度，不能精确画衍射包络。",
        contract: doubleSlitCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        correctDoubleSlitValidation.passedDeterministicGates,
        "symbolic double-slit directions and the envelope boundary must pass without requiring prose-only synonyms"
    )
    let commaScopedDoubleSlitValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: "由于 λ、L 在分子、d 在分母，λ 或 L 增大时条纹变疏，d 增大时条纹变密。",
        contract: doubleSlitCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        !commaScopedDoubleSlitValidation.triggeredForbiddenClaims.contains("lambda-larger-denser"),
        "a new single-letter variable subject after a comma must not inherit the previous variable claim"
    )

    let polyrhythmCase = try liveSuccessCase("learning-music-polyrhythm-cycle")
    let correctPolyrhythmValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: "把同一拍号落实为 2 拍共同周期来看：二连音在 0、1 拍，三连音在 0、2/3、4/3 拍；两组只在周期起点重合。BPM 增大只缩短实际时间，相对拍位不变。",
        contract: polyrhythmCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        correctPolyrhythmValidation.passedDeterministicGates,
        "a correct 3:2 explanation must not reinterpret the duple 1-beat hit as a one-beat common cycle"
    )

    let colorContrastCase = try liveSuccessCase("learning-art-color-contrast-overlay")
    let correctColorContrastValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: "13.94:1 对普通正文与大号文字均通过；4.03:1 普通正文未通过但大号标题通过；1.81:1 的占位文字未通过。细字的 11×11 样本可能被输入框底色稀释，因此要额外查看 glyph interior。",
        contract: colorContrastCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        correctColorContrastValidation.passedDeterministicGates,
        "correct threshold judgments and the 11×11 versus glyph-interior boundary must pass"
    )

    let feedbackCase = try liveSuccessCase("learning-engineering-feedback-overshoot")
    let unrelatedTopicAfterGain = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: "增益 K 在图例中，外部缓存越大，稳定越快且无代价。",
        contract: feedbackCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        !unrelatedTopicAfterGain.triggeredForbiddenClaims.contains("larger-k-always-faster-stable"),
        "a subject mentioned in an earlier complete proposition must not drift into an unrelated later topic"
    )

    let meiosisCase = try liveSuccessCase("learning-biology-meiosis-separation")
    let correctMeiosisText = """
    后期 I 分离同源染色体、姐妹染色单体仍相连；后期 II 才分离姐妹染色单体；两次分裂之间不再复制 DNA。
    """
    let correctMeiosisValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: correctMeiosisText,
        contract: meiosisCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        correctMeiosisValidation.triggeredForbiddenClaims.isEmpty,
        "connected sister chromatids and no replication refute the meiosis reverse claims: \(correctMeiosisValidation.triggeredForbiddenClaims.joined(separator: ","))"
    )
    let negatedMeiosisReplicationValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: "两次分裂之间不会再次复制 DNA；后期 I 分离同源染色体，后期 II 分离姐妹染色单体。",
        contract: meiosisCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        !negatedMeiosisReplicationValidation.triggeredForbiddenClaims.contains("dna-replicates-between-divisions"),
        "a negation scoped before the replication predicate must refute that forbidden claim"
    )
    let doubleNegatedMeiosisReplicationValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: "分裂之间并非不会复制 DNA，而是再次复制 DNA。",
        contract: meiosisCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        doubleNegatedMeiosisReplicationValidation.triggeredForbiddenClaims.contains("dna-replicates-between-divisions"),
        "double negation must not turn repeated DNA replication into a safe statement"
    )
    let wrongMeiosisText = """
    后期 I 分离姐妹染色单体；后期 II 分离同源染色体；两次分裂之间再次复制 DNA。
    """
    let wrongMeiosisValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: wrongMeiosisText,
        contract: meiosisCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        wrongMeiosisValidation.triggeredForbiddenClaims.contains("anaphase-one-sisters")
            && wrongMeiosisValidation.triggeredForbiddenClaims.contains("dna-replicates-between-divisions"),
        "actual meiosis separation and replication reversals still fail"
    )

    let similarityCase = try liveSuccessCase("learning-math-geometric-similarity-proof")
    let correctSimilarityText = """
    DE ∥ BC 给出对应角相等，因此△ADE∽△ABC，对应边比为 1/2；坐标不能替代平行条件和角相等证明。
    """
    let correctSimilarityValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: correctSimilarityText,
        contract: similarityCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        !correctSimilarityValidation.triggeredForbiddenClaims.contains("wrong-ratio"),
        "numeric token 2 must not be extracted from the correct fraction 1/2"
    )
    let negatedNoParallelValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: "DE 不平行时不能推出对应角相等；只有 DE ∥ BC 才给出对应角相等，且对应边比等于 1/2；坐标不能替代平行条件和角相等证明。",
        contract: similarityCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        !negatedNoParallelValidation.triggeredForbiddenClaims.contains("no-parallel-still-angle-equal"),
        "a negation scoped after the no-parallel subject must refute that forbidden claim"
    )
    let noParallelDoesNotPreventValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: "DE 不平行并不妨碍推出对应角相等。",
        contract: similarityCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        noParallelDoesNotPreventValidation.triggeredForbiddenClaims.contains("no-parallel-still-angle-equal"),
        "does-not-prevent language affirms rather than negates the forbidden angle claim"
    )
    let wrongSimilarityText = """
    DE ∥ BC 给出对应角相等，但对应边比等于 2；坐标不能替代平行条件和角相等证明。
    """
    let wrongSimilarityValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: wrongSimilarityText,
        contract: similarityCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        wrongSimilarityValidation.triggeredForbiddenClaims.contains("wrong-ratio"),
        "standalone wrong ratio 2 remains a high-confidence contradiction"
    )

    let lawCase = try liveSuccessCase("learning-law-clause-exception-hierarchy")
    let correctLawText = """
    供应方应在 24 小时内通知，但实际 36 小时后才通知，因此晚于期限。8.3 将 8.2 例外拉回 8.1 主规则。
    """
    let correctLawValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: correctLawText,
        contract: lawCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        !correctLawValidation.triggeredForbiddenClaims.contains("thirty-six-within-twenty-four"),
        "the correct deadline sentence cannot borrow the earlier preposition to invent compliance"
    )
    let wrongLawText = """
    36 小时仍在 24 小时内，所以通知没有超期。8.3 将 8.2 例外拉回 8.1 主规则。
    """
    let wrongLawValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: wrongLawText,
        contract: lawCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        wrongLawValidation.triggeredForbiddenClaims.contains("thirty-six-within-twenty-four"),
        "actual deadline reversal still fails with ordered numeric binding"
    )

    let climateCase = try liveSuccessCase("learning-geography-climate-diagram-compare")
    let correctClimateText = """
    城市甲冬冷夏热且夏季多雨；城市乙全年高温，年末到年初更湿；仅凭两地数据不能代表区域气候。
    """
    let correctClimateValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: correctClimateText,
        contract: climateCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        correctClimateValidation.passedDeterministicGates,
        "climate comparison binds summer-rain to city A and year-end wetness to city B"
    )
    let wrongClimateText = """
    城市甲全年高温，年末到年初多雨；城市乙冬冷夏热且夏季多雨；仅凭两地数据不能代表区域气候。
    """
    let wrongClimateValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: wrongClimateText,
        contract: climateCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        !wrongClimateValidation.passedDeterministicGates
            && wrongClimateValidation.triggeredForbiddenClaims.contains("a-hot-wet-year-end")
            && wrongClimateValidation.triggeredForbiddenClaims.contains("b-cold-hot-summer-rain"),
        "actual city-role climate reversals still fail"
    )
    let adversativeClimateValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: "城市甲不是夏季多雨，而是全年高温、年末到年初多雨。",
        contract: climateCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        adversativeClimateValidation.triggeredForbiddenClaims.contains("a-hot-wet-year-end"),
        "an adversative list must keep the city subject without carrying unrelated negation into the false predicate"
    )

    let reviewMarkedCases = Set(
        RichAnswerLiveCases.successes
            .filter { !$0.professionalJudgmentContract.modelOrHumanReviewNotes.isEmpty }
            .map(\.id)
    )
    try richAnswerRequire(
        reviewMarkedCases.contains("learning-literature-imagery-theme")
            && reviewMarkedCases.contains("learning-philosophy-argument-boundary")
            && reviewMarkedCases.contains("learning-earth-science-subduction-cross-section"),
        "non-deterministic literature, philosophy, and image localization judgments are explicitly marked for model or human review"
    )
}

private func checkTitrationProfessionalJudgmentRegressions() throws {
    let titrationCase = try liveSuccessCase("learning-chemistry-titration-buffer-region")
    let correctTitrationText = """
    12.5 mL 是半当量点，pH=pKa≈4.74；25.0 mL 是当量点且 pH 大于 7。起始、缓冲区、25.0 mL 当量点和过量碱区分别标出近似方法：起始弱酸近似、缓冲近似、乙酸根水解近似、过量强碱余量近似。
    """
    let correctTitrationValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: correctTitrationText,
        contract: titrationCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        correctTitrationValidation.passedDeterministicGates,
        "correct titration half-equivalence and segmented approximations must pass: missing=\(correctTitrationValidation.missingRequiredClaims.joined(separator: ",")) forbidden=\(correctTitrationValidation.triggeredForbiddenClaims.joined(separator: ",")) boundary=\(correctTitrationValidation.missingBoundaryClaims.joined(separator: ","))"
    )

    let wrongHalfEquivalenceValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: "12.5 mL 是当量点；25.0 mL 是当量点且 pH 大于 7。起始、缓冲区、25.0 mL 当量点和过量碱区分别标出近似方法。",
        contract: titrationCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        wrongHalfEquivalenceValidation.triggeredForbiddenClaims.contains("half-as-equivalence"),
        "12.5 mL as equivalence point must still trigger half-as-equivalence"
    )

    let splitVisibleSceneValidation = RichAnswerProfessionalJudgmentValidator.validate(
        units: [
            "起始：需用起始近似",
            "缓冲区：需用缓冲近似",
            "25.0 mL 当量点：乙酸根水解近似",
            "过量碱区：强碱余量近似",
        ],
        contract: titrationCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        !splitVisibleSceneValidation.missingBoundaryClaims.contains("different-region-approximations"),
        "same-scene staged approximation labels must satisfy different-region-approximations"
    )

    let singleApproximationValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: "起始阶段使用近似。12.5 mL 是半当量点；25.0 mL 是当量点且 pH 大于 7。",
        contract: titrationCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        singleApproximationValidation.missingBoundaryClaims.contains("different-region-approximations"),
        "one isolated approximation label must not satisfy the multi-region titration boundary"
    )
}

private func checkArtColorContrastObligationsDoNotRequireHash() throws {
    let artCase = try liveSuccessCase("learning-art-color-contrast-overlay")
    let requiredClaimIDs = Set(artCase.professionalJudgmentContract.requiredClaims.map(\.id))
    try richAnswerRequire(
        !requiredClaimIDs.contains("real-png-source"),
        "color contrast professional judgment no longer requires model text to repeat PNG hash/source"
    )
    let obligationIDs = Set(artCase.professionalFactObligations.map(\.id))
    try richAnswerRequire(
        !obligationIDs.contains("source-png-hash-and-origin"),
        "color contrast fact obligations no longer require model text to repeat PNG hash/source"
    )
    let expectedNarrativeText = artCase.expectedNarrativeKeywordGroups.flatMap { $0 }.joined(separator: " ")
    try richAnswerRequire(
        !expectedNarrativeText.contains("SHA-256")
            && !expectedNarrativeText.contains("c1c79970691385ff614f7c5a9eacedc21a094ba409bf242bb7c62d0716f06e1e")
            && !(expectedNarrativeText.contains("真实") && expectedNarrativeText.contains("PNG")),
        "color contrast narrative targets no longer pressure the model to repeat asset provenance"
    )
    try richAnswerRequire(
        artCase.requiresMaterialAsset,
        "color contrast still requires the trusted material asset binding"
    )

    let hashFreeContrastText = """
    三组采样结论是：2.22 s 的黑色读数对比度 13.94:1，普通正文和大号文字都通过；“适用范围”的橙色小标题为 4.03:1，普通正文未通过但大号/加粗标题通过；输入框占位文字为 1.81:1，普通正文与大号文字均未通过。11×11 样本会被抗锯齿和背景稀释吞掉时，应说明 glyph interior 小窗。
    """
    let hashFreeValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: hashFreeContrastText,
        contract: artCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        hashFreeValidation.passedDeterministicGates,
        "hash-free color contrast answer still passes real semantic obligations: missing=\(hashFreeValidation.missingRequiredClaims.joined(separator: ",")) forbidden=\(hashFreeValidation.triggeredForbiddenClaims.joined(separator: ",")) boundary=\(hashFreeValidation.missingBoundaryClaims.joined(separator: ","))"
    )
}

private func checkProfessionalJudgmentObservedLanguageVariants() throws {
    try requireProfessionalLanguage(
        caseID: "learning-math-quadratic-vertex",
        corpus: "当前材料用 y=2x²-8x+5 演示同一配方逻辑，并读出顶点 (2,-3)。这是同一个二次函数的等价表达和合法变形链，最后改写成顶点式 2(x-2)²-3。",
        required: ["vertex-is-2-minus-3", "equivalent-vertex-form"]
    )
    try requireProfessionalLanguage(
        caseID: "learning-computer-loop-trace",
        corpus: "这段循环一共走 4 轮：i=1,2,3,4；最终输出 4。",
        required: ["range-four-iterations"]
    )
    try requireProfessionalLanguage(
        caseID: "learning-computer-loop-trace",
        corpus: "最终输出是 4：代码从 total = 0 开始，i 依次取 1、2、3、4；四轮 total 依次为 -1、1、0、4。",
        required: ["range-four-iterations", "final-total-four"]
    )
    let loopCase = try liveSuccessCase("learning-computer-loop-trace")
    let correctLoopFrameValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: "初始化帧：total=0，输出=未执行；四轮 i 依次取 1、2、3、4；最终输出为 4。",
        contract: loopCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        !correctLoopFrameValidation.triggeredForbiddenClaims.contains("wrong-final-total"),
        "an intermediate total of zero must not be misread as the final output"
    )
    let wrongLoopFinalValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: "四轮 i 依次取 1、2、3、4；最终输出为 0。",
        contract: loopCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        wrongLoopFinalValidation.triggeredForbiddenClaims.contains("wrong-final-total"),
        "an explicitly wrong final total must still be rejected"
    )
    try requireProfessionalLanguage(
        caseID: "learning-literature-imagery-theme",
        corpus: "最后一班车驶远提供不可逆的离开感，因此支持错过。",
        required: ["bus-leaving-image"]
    )
    try requireProfessionalLanguage(
        caseID: "learning-history-multi-source-timeline",
        corpus: "动员和最后通牒这一升级机制推动危机升级，被材料归为直接升级机制。",
        required: ["mobilization-escalation"]
    )
    try requireProfessionalLanguage(
        caseID: "learning-art-design-composition-overlay",
        corpus: "下面的内联叠图把构图区域和标注直接压到当前海报底图上。",
        boundary: ["image-grounding-boundary"]
    )
    try requireProfessionalLanguage(
        caseID: "learning-geography-contour-river-slope",
        corpus: "等高线越密集，坡度越陡。材料未给出可读的河道沿程高程数字，所以不能确认绝对流向。",
        required: ["dense-contours-steeper"],
        boundary: ["observable-density-only"]
    )
    try requireProfessionalLanguage(
        caseID: "learning-economics-price-ceiling-shortage",
        corpus: "均衡价是 20。上限 15 会让需求量 70 大于供给量 50，因此短缺 20。若给定曲线或有效执行变化，结论不能直接套用。",
        required: ["equilibrium-price-20", "binding-ceiling-shortage-20"],
        boundary: ["given-curves-enforcement-boundary"]
    )
    try requireProfessionalLanguage(
        caseID: "learning-law-policy-notice-duty",
        corpus: "当前上下文只支持依据给定条文作合规风险判断；事实不足处需另证。",
        boundary: ["given-clause-boundary"]
    )
    try requireProfessionalLanguage(
        caseID: "learning-chemistry-vsepr-molecular-shape",
        corpus: "不要把电子域构型和分子构型混在一起。",
        boundary: ["domain-vs-molecular-shape-boundary"]
    )
    try requireProfessionalLanguage(
        caseID: "learning-biology-food-web-perturbation",
        corpus: "箭头方向是食物→消费者。狗鱼减少后，小鱼受到的直接捕食压力下降。材料没有长期种群数据，所以间接效应只能作为方向性推断，不能说成已证实结果。",
        required: ["arrow-food-to-consumer", "pike-reduction-direct-effect"],
        boundary: ["directional-inference-boundary"]
    )
    try requireProfessionalLanguage(
        caseID: "learning-computer-recursion-call-stack",
        corpus: "factorial(4) 不是一次算出 24，而是先沿 4→3→2→1 创建栈帧。要区分两个方向：向下调用与向上回传。",
        required: ["four-stack-frames"],
        boundary: ["call-return-phase-boundary"]
    )
    try requireProfessionalLanguage(
        caseID: "learning-math-geometric-similarity-proof",
        corpus: "平行条件先推出对应角相等；不能只靠坐标示意替代证明。",
        boundary: ["coordinate-not-proof-boundary"]
    )
    try requireProfessionalLanguage(
        caseID: "learning-physics-double-slit-interference",
        corpus: "相邻亮纹间距 Δx≈3.0 mm。",
        required: ["fringe-spacing-three-mm"]
    )
    try requireProfessionalLanguage(
        caseID: "learning-law-clause-exception-hierarchy",
        corpus: "把条款层级和事实触发点放在一起，再逐项核对当前事实落在 8.1、8.2、8.3 的哪一层。",
        boundary: ["given-clause-not-advice-boundary"]
    )
    try requireProfessionalLanguage(
        caseID: "learning-medicine-cardiac-cycle",
        corpus: "拖动阶段时看压力触发条件，不要把它当作个体诊断。",
        boundary: ["learning-not-diagnosis-boundary"]
    )
    try requireProfessionalLanguage(
        caseID: "learning-philosophy-modal-counterexample",
        corpus: "材料中的前提只支持可能存在，并且在存在的世界中具有 F，不支持必然具有 F；失效点正是从可能跨到必然。",
        required: ["weak-not-necessary"],
        boundary: ["modal-strength-boundary"]
    )
    try requireProfessionalLanguage(
        caseID: "learning-psychology-experiment-confound",
        corpus: "结果是咖啡因组平均 310 ms、对照组 345 ms，差值为 35 ms。",
        required: ["mean-difference-35"]
    )

    let acidCase = try liveSuccessCase("learning-chemistry-redox-balance")
    let equationOnlyAcidValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: "酸性条件下配平得到 MnO₄⁻ + 5Fe²⁺ + 8H⁺ → Mn²⁺ + 5Fe³⁺ + 4H₂O。",
        contract: acidCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        equationOnlyAcidValidation.missingBoundaryClaims.contains("acidic-condition-boundary"),
        "an equation that merely contains H⁺ and H₂O cannot replace explaining why the acidic condition requires them"
    )

    let foodWebCase = try liveSuccessCase("learning-biology-food-web-perturbation")
    let reversedFoodArrowValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: "箭头画成消费者→食物。狗鱼减少后，小鱼直接捕食压力上升。",
        contract: foodWebCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        reversedFoodArrowValidation.triggeredForbiddenClaims.contains("arrow-consumer-to-food")
            && reversedFoodArrowValidation.missingRequiredClaims.contains("arrow-food-to-consumer")
            && reversedFoodArrowValidation.missingRequiredClaims.contains("pike-reduction-direct-effect"),
        "reversed food-web direction and pressure remain rejected"
    )

    let recursionCase = try liveSuccessCase("learning-computer-recursion-call-stack")
    let negatedStackValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: "factorial(4) 没有沿 4→3→2→1 创建栈帧。",
        contract: recursionCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        negatedStackValidation.missingRequiredClaims.contains("four-stack-frames"),
        "a negated stack-frame claim cannot pass through the observed arrow-sequence synonym"
    )

    let doubleSlitCase = try liveSuccessCase("learning-physics-double-slit-interference")
    let wrongSpacingValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: "相邻亮纹间距 Δx≈30 mm。",
        contract: doubleSlitCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        wrongSpacingValidation.missingRequiredClaims.contains("fringe-spacing-three-mm"),
        "approximation normalization cannot turn 30 mm into the required 3.0 mm"
    )

    let psychologyCase = try liveSuccessCase("learning-psychology-experiment-confound")
    let wrongPsychologyValidation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: "结果是咖啡因组平均 310 ms、对照组 340 ms，差值为 30 ms。非随机分组可能造成混淆；当前设计只支持相关差异，不能确认因果。",
        contract: psychologyCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        wrongPsychologyValidation.missingRequiredClaims.contains("mean-difference-35"),
        "different reaction-time values cannot satisfy the observed 310/345/35 ms claim"
    )
}

private func requireProfessionalLanguage(
    caseID: String,
    corpus: String,
    required: [String] = [],
    boundary: [String] = []
) throws {
    let checkCase = try liveSuccessCase(caseID)
    let validation = RichAnswerProfessionalJudgmentValidator.validate(
        corpus: corpus,
        contract: checkCase.professionalJudgmentContract
    )
    let missingRequired = required.filter(validation.missingRequiredClaims.contains)
    let missingBoundary = boundary.filter(validation.missingBoundaryClaims.contains)
    try richAnswerRequire(
        missingRequired.isEmpty && missingBoundary.isEmpty,
        "observed professional language must be recognized for \(caseID): required=\(missingRequired.joined(separator: ",")) boundary=\(missingBoundary.joined(separator: ","))"
    )
}

private func liveSuccessCase(_ id: String) throws -> RichAnswerLiveSuccessCase {
    guard let checkCase = RichAnswerLiveCases.successes.first(where: { $0.id == id }) else {
        throw RichAnswerProtocolCheckError.failed("missing live success case \(id)")
    }
    return checkCase
}

private func checkProfessionalJudgmentIgnoresEvidenceCitations() throws {
    let economicsCase = try liveSuccessCase("learning-economics-price-ceiling-shortage")
    let correctSourceExcerpt = "均衡价格为 P=20。价格上限15形成短缺20。价格上限25高于均衡，不形成约束。结论只适用于给定曲线和有效执行。"
    let missingClaimPresentation = RichAnswerPresentation(
        mode: .rich,
        narrative: "我把供需材料整理成了一个交互体验。",
        expressionPlan: RichAnswerExpressionPlan(
            action: .observe,
            summary: "观察供需材料中的参数变化",
            families: [.quantityAndCoordinates],
            preferredSurface: .inline,
            directManipulation: true
        ),
        scenes: [
            RichAnswerScene(
                id: "source-only-correct-fact",
                title: "供需交互",
                family: .quantityAndCoordinates,
                objects: [],
                evidenceIDs: ["source-correct"],
                program: RichAnswerUIProgram(
                    source: """
                    root = RichAnswerRoot("经济学", "查看供需材料", "拖动参数", "workbench", [sources])
                    sources = LearningStage("evidence", "来源", [evidence])
                    evidence = EvidenceSnippet("source-correct", "材料", "\(correctSourceExcerpt)", "回到原文")
                    """,
                    capabilities: ["evidence-jump"],
                    directManipulation: true,
                    graphics: .dom
                )
            ),
        ],
        evidenceLedger: [
            RichAnswerEvidence(
                id: "source-correct",
                sourceLabel: "[材料：价格上限供需材料]",
                excerpt: correctSourceExcerpt
            ),
        ],
        evidenceState: .complete
    )
    let missingClaimReply = StudyAgentReply(
        text: missingClaimPresentation.narrative,
        backend: .pi,
        richAnswer: missingClaimPresentation
    )
    let missingClaimValidation = RichAnswerProfessionalJudgmentValidator.validate(
        units: WeiBeiPiCheckMain.professionalJudgmentUnits(
            reply: missingClaimReply,
            presentation: missingClaimPresentation
        ),
        contract: economicsCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        !missingClaimValidation.passedDeterministicGates
            && !missingClaimValidation.missingRequiredClaims.isEmpty,
        "source ledger and EvidenceSnippet cannot supply a professional claim missing from model output"
    )

    let t2EvidenceOnlyDataPresentation = RichAnswerPresentation(
        mode: .rich,
        narrative: "我把供需来源放进了证据区。",
        expressionPlan: RichAnswerExpressionPlan(
            action: .observe,
            summary: "查看供需来源",
            families: [.relationAndEvidence],
            preferredSurface: .inline,
            directManipulation: false
        ),
        scenes: [
            RichAnswerScene(
                id: "t2-evidence-only-data",
                title: "来源定位",
                family: .relationAndEvidence,
                objects: [],
                evidenceIDs: ["source-correct"],
                ui: RichAnswerUIComposition(
                    rootID: "root",
                    nodes: [
                        RichAnswerUINode(
                            id: "root",
                            role: .panel,
                            children: ["source"]
                        ),
                        RichAnswerUINode(
                            id: "source",
                            role: .evidence,
                            label: "材料原文",
                            datasetID: "source-only-dataset",
                            bindingID: "source-only-binding",
                            evidenceIDs: ["source-correct"]
                        ),
                    ],
                    datasets: [
                        RichAnswerUIDataset(
                            id: "source-only-dataset",
                            rows: [
                                RichAnswerUIDataRow(
                                    id: "source-only-row",
                                    x: 0,
                                    y: 0,
                                    label: correctSourceExcerpt,
                                    evidenceIDs: ["source-correct"]
                                ),
                            ]
                        ),
                    ],
                    bindings: [
                        RichAnswerUIBinding(
                            id: "source-only-binding",
                            label: correctSourceExcerpt,
                            minimum: 0,
                            maximum: 1,
                            step: 1,
                            initialValue: 0
                        ),
                    ]
                )
            ),
        ],
        evidenceLedger: [
            RichAnswerEvidence(
                id: "source-correct",
                sourceLabel: "[材料：价格上限供需材料]",
                excerpt: correctSourceExcerpt
            ),
        ],
        evidenceState: .complete
    )
    let t2EvidenceOnlyDataReply = StudyAgentReply(
        text: t2EvidenceOnlyDataPresentation.narrative,
        backend: .pi,
        richAnswer: t2EvidenceOnlyDataPresentation
    )
    let t2EvidenceOnlyDataValidation = RichAnswerProfessionalJudgmentValidator.validate(
        units: WeiBeiPiCheckMain.professionalJudgmentUnits(
            reply: t2EvidenceOnlyDataReply,
            presentation: t2EvidenceOnlyDataPresentation
        ),
        contract: economicsCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        !t2EvidenceOnlyDataValidation.passedDeterministicGates
            && !t2EvidenceOnlyDataValidation.missingRequiredClaims.isEmpty,
        "T2 data and bindings referenced only by evidence nodes cannot supply professional claims"
    )

    let correctModelText = "均衡价格为 P=20。价格上限15形成短缺20。价格上限25高于均衡，不形成约束，也不会由该上限产生短缺。结论只适用于给定曲线和有效执行。"
    let misleadingSourceExcerpt = "待反驳误解：价格上限25会产生短缺，上限越高短缺越严重。"
    let explicitRefutationPresentation = RichAnswerPresentation(
        mode: .rich,
        narrative: correctModelText,
        expressionPlan: RichAnswerExpressionPlan(
            action: .explain,
            summary: "解释有效与无约束价格上限的区别",
            families: [.quantityAndCoordinates],
            preferredSurface: .inline,
            directManipulation: false
        ),
        scenes: [
            RichAnswerScene(
                id: "refuted-source-misconception",
                title: "价格上限判断",
                family: .quantityAndCoordinates,
                objects: [],
                evidenceIDs: ["source-misconception"],
                ui: RichAnswerUIComposition(
                    rootID: "root",
                    nodes: [
                        RichAnswerUINode(
                            id: "root",
                            role: .panel,
                            children: ["explanation", "source"]
                        ),
                        RichAnswerUINode(
                            id: "explanation",
                            role: .text,
                            text: "正文已经明确区分有效上限与无约束上限。"
                        ),
                        RichAnswerUINode(
                            id: "source",
                            role: .evidence,
                            label: "材料中的待反驳说法",
                            text: misleadingSourceExcerpt,
                            evidenceIDs: ["source-misconception"]
                        ),
                    ]
                )
            ),
        ],
        evidenceLedger: [
            RichAnswerEvidence(
                id: "source-misconception",
                sourceLabel: "[材料：价格上限误解辨析]",
                excerpt: misleadingSourceExcerpt
            ),
        ],
        evidenceState: .complete
    )
    let explicitRefutationReply = StudyAgentReply(
        text: correctModelText,
        backend: .pi,
        richAnswer: explicitRefutationPresentation
    )
    let explicitRefutationValidation = RichAnswerProfessionalJudgmentValidator.validate(
        units: WeiBeiPiCheckMain.professionalJudgmentUnits(
            reply: explicitRefutationReply,
            presentation: explicitRefutationPresentation
        ),
        contract: economicsCase.professionalJudgmentContract
    )
    try richAnswerRequire(
        explicitRefutationValidation.passedDeterministicGates
            && explicitRefutationValidation.triggeredForbiddenClaims.isEmpty,
        "a misconception quoted only as evidence cannot override the model's explicit refutation"
    )
}

private func checkNarrativeAndScenesFormOneInlineFlow() throws {
    var envelope = openUIProgramEnvelope()
    envelope.narrative = """
    先判断参数正负，它只决定开口方向。

    <!-- weibei-scene:openui-function -->

    再观察绝对值，它决定曲线宽窄。
    """
    let presentation = RichAnswerEngine.prepare(
        envelope: envelope,
        environment: RichAnswerEnvironment(
            contextRevision: "revision-openui",
            allowedSourceLabels: ["[材料：函数样例]"]
        )
    )

    try richAnswerRequire(
        presentation.resolvedParts == [
            .narrative("先判断参数正负，它只决定开口方向。"),
            .scene("openui-function"),
            .narrative("再观察绝对值，它决定曲线宽窄。"),
        ],
        "rich answers interleave narrative and generated UI instead of appending a mini-site"
    )
    try richAnswerRequire(
        presentation.narrative == "先判断参数正负，它只决定开口方向。\n\n再观察绝对值，它决定曲线宽窄。",
        "scene markers never leak into the readable narrative"
    )

    let encoded = try JSONEncoder().encode(presentation)
    let decoded = try JSONDecoder().decode(RichAnswerPresentation.self, from: encoded)
    try richAnswerRequire(decoded.resolvedParts == presentation.resolvedParts, "inline flow survives message persistence")

    var unmarkedEnvelope = openUIProgramEnvelope()
    unmarkedEnvelope.contextRevision = "revision-openui-unmarked"
    unmarkedEnvelope.narrative = "先用正文解释判断依据，再查看随后的可视化。"
    let unmarkedPresentation = RichAnswerEngine.prepare(
        envelope: unmarkedEnvelope,
        environment: RichAnswerEnvironment(
            contextRevision: "revision-openui-unmarked",
            allowedSourceLabels: ["[材料：函数样例]"]
        )
    )
    try richAnswerRequire(
        unmarkedPresentation.resolvedParts == [
            .narrative("先用正文解释判断依据，再查看随后的可视化。"),
            .scene("openui-function"),
        ],
        "unmarked scenes remain compatible by appending after readable narrative"
    )

    var legacyObject = try richAnswerJSONObject(from: encoded)
    legacyObject.removeValue(forKey: "parts")
    let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
    let legacyPresentation = try JSONDecoder().decode(RichAnswerPresentation.self, from: legacyData)
    try richAnswerRequire(
        legacyPresentation.resolvedParts == [
            .narrative(presentation.narrative),
            .scene("openui-function"),
        ],
        "messages saved before inline flow support remain readable"
    )
}

private func richAnswerJSONObject(from data: Data) throws -> [String: Any] {
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw RichAnswerProtocolCheckError.failed("rich answer presentation encodes as a JSON object")
    }
    return object
}

private func checkOpenUIProgramRenders() throws {
    let envelope = openUIProgramEnvelope()
    let environment = RichAnswerEnvironment(
        contextRevision: "revision-openui",
        allowedSourceLabels: ["[材料：函数样例]"]
    )
    let presentation = RichAnswerEngine.prepare(envelope: envelope, environment: environment)

    try richAnswerRequire(presentation.mode == .rich, "a valid OpenUI program stays rich")
    try richAnswerRequire(
        presentation.scenes.first?.program?.graphics == .canvas
            && presentation.scenes.first?.program?.source.contains("FunctionPlot(") == true,
        "the OpenUI program and its Canvas graphics contract survive validation"
    )
    let encoded = try JSONEncoder().encode(envelope)
    let decoded = RichAnswerEngine.prepare(data: encoded, fallbackText: "fallback", environment: environment)
    try richAnswerRequire(decoded == presentation, "the OpenUI program JSON boundary round-trips")
}

private func checkOpenUIProgramRejectsUnsafeVariants() throws {
    var unknownComponent = openUIProgramEnvelope()
    unknownComponent.scenes[0].program?.source += "\nrogue = UnknownWidget(\"x\")"
    try assertOpenUIProgramRejected(
        unknownComponent,
        expectedCode: .unsupportedField,
        "OpenUI rejects components outside WeiBei's catalog"
    )

    var missingRoot = openUIProgramEnvelope()
    var rootProgram = missingRoot.scenes[0].program!
    rootProgram.source = rootProgram.source
        .replacingOccurrences(of: "root = RichAnswerRoot", with: "layout = RichAnswerRoot")
    missingRoot.scenes[0].program = rootProgram
    try assertOpenUIProgramRejected(
        missingRoot,
        expectedCode: .brokenReference,
        "OpenUI requires a RichAnswerRoot statement"
    )

    var rawSVG = openUIProgramEnvelope()
    rawSVG.scenes[0].program?.source += "\n<svg><path /></svg>"
    try assertOpenUIProgramRejected(
        rawSVG,
        expectedCode: .unauthorizedAsset,
        "OpenUI rejects model-authored SVG markup"
    )

    var wrongGraphicsKernel = openUIProgramEnvelope()
    wrongGraphicsKernel.scenes[0].program?.graphics = .dom
    try assertOpenUIProgramRejected(
        wrongGraphicsKernel,
        expectedCode: .invalidValue,
        "function plots require the Canvas graphics kernel"
    )

    var missingEvidenceBinding = openUIProgramEnvelope()
    var evidenceProgram = missingEvidenceBinding.scenes[0].program!
    evidenceProgram.source = evidenceProgram.source
        .replacingOccurrences(of: "\"program-source\"", with: "\"other-source\"")
    missingEvidenceBinding.scenes[0].program = evidenceProgram
    try assertOpenUIProgramRejected(
        missingEvidenceBinding,
        expectedCode: .missingEvidence,
        "every scene evidence item must be bound inside the OpenUI program"
    )

    var quotedOnlyEvidence = openUIProgramEnvelope()
    var quotedOnlyProgram = quotedOnlyEvidence.scenes[0].program!
    quotedOnlyProgram.source = quotedOnlyProgram.source
        .replacingOccurrences(
            of: "evidence = EvidenceSnippet(\"program-source\", \"材料\", \"y = x²\", \"支撑函数关系\")",
            with: "evidence = NarrativeBlock(\"来源\", \"program-source\", \"hint\")"
        )
    quotedOnlyEvidence.scenes[0].program = quotedOnlyProgram
    try assertOpenUIProgramRejected(
        quotedOnlyEvidence,
        expectedCode: .missingEvidence,
        "T1 cannot satisfy evidence binding by merely quoting an evidence id in a non-evidence component"
    )

    var mixedLegacyOperations = openUIProgramEnvelope()
    mixedLegacyOperations.scenes[0].operations = [
        RichAnswerOperation(id: "legacy-step", kind: .step, label: "旧操作", targetIDs: []),
    ]
    try assertOpenUIProgramRejected(
        mixedLegacyOperations,
        expectedCode: .unsupportedField,
        "OpenUI scenes cannot mix in legacy native operations"
    )

    var repeatedConclusion = openUIProgramEnvelope()
    repeatedConclusion.scenes[0].program?.source += "\nclosing = NarrativeBlock(\"结论\", \"把正文再讲一遍\", \"conclusion\")"
    let repeatedConclusionPresentation = RichAnswerEngine.prepare(
        envelope: repeatedConclusion,
        environment: RichAnswerEnvironment(
            contextRevision: "revision-openui",
            allowedSourceLabels: ["[材料：函数样例]"]
        )
    )
    try richAnswerRequire(
        repeatedConclusionPresentation.mode == .rich,
        "inline OpenUI allows a conclusion narrative block when structure, source binding, and safety remain valid"
    )
}

private func checkGeneratedUITreeRejectsMalformedProtocol() throws {
    let unknownField = Data(
        #"{"schemaVersion":2,"contextRevision":"revision-ui","narrative":"文本回答。","expressionPlan":{"action":"explain","summary":"说明","families":["textAndAlignment"],"preferredSurface":"inline","directManipulation":false},"scenes":[],"evidenceLedger":[],"fallback":{"text":"安全文本","reason":"坏协议"},"extraField":"bad"}"#.utf8
    )
    let unknownFieldPresentation = RichAnswerEngine.prepare(
        data: unknownField,
        fallbackText: "安全文本",
        environment: RichAnswerEnvironment(contextRevision: "revision-ui", allowedSourceLabels: [])
    )
    try richAnswerRequire(unknownFieldPresentation.mode == .narrativeOnly, "unknown rich-answer fields never render")
    try richAnswerRequire(
        unknownFieldPresentation.diagnostics.contains(where: { $0.code == .unsupportedField }),
        "unknown fields expose unsupportedField"
    )

    let unknownRole = Data(
        #"{"schemaVersion":2,"contextRevision":"revision-ui","narrative":"说明 [材料：函数样例]\n\n<!-- weibei-scene:bad-role -->","expressionPlan":{"action":"explain","summary":"说明","families":["quantityAndCoordinates"],"preferredSurface":"inline","directManipulation":false},"scenes":[{"id":"bad-role","title":"坏节点","family":"quantityAndCoordinates","evidenceIDs":["ui-source"],"ui":{"rootID":"root","nodes":[{"id":"root","role":"card","children":[]}],"datasets":[],"bindings":[]}}],"evidenceLedger":[{"id":"ui-source","sourceLabel":"[材料：函数样例]","excerpt":"y = x²"}],"fallback":{"text":"安全文本","reason":"未知 role"}} "#.utf8
    )
    let unknownRolePresentation = RichAnswerEngine.prepare(
        data: unknownRole,
        fallbackText: "安全文本",
        environment: RichAnswerEnvironment(contextRevision: "revision-ui", allowedSourceLabels: ["[材料：函数样例]"])
    )
    try richAnswerRequire(unknownRolePresentation.mode == .narrativeOnly, "unknown T2 roles never render")
    try richAnswerRequire(
        unknownRolePresentation.diagnostics.contains(where: { $0.code == .decodeFailed }),
        "unknown roles expose a decode failure instead of rendering a bad tree"
    )
}

private func checkGeneratedUITreeRejectsPseudoInteractionAndMissingObligations() throws {
    var invalidBinding = generatedUIEnvelope()
    invalidBinding.scenes[0].ui?.bindings[0].initialValue = 3
    let invalidBindingPresentation = RichAnswerEngine.prepare(
        envelope: invalidBinding,
        environment: RichAnswerEnvironment(
            contextRevision: "revision-ui",
            allowedSourceLabels: ["[材料：函数样例]"]
        )
    )
    try richAnswerRequire(invalidBindingPresentation.mode == .narrativeOnly, "invalid T2 bindings never render")
    try richAnswerRequire(
        invalidBindingPresentation.diagnostics.contains(where: { $0.code == .invalidParameter }),
        "invalid bindings expose invalidParameter"
    )

    var pseudoInteraction = generatedUIEnvelope()
    for rowIndex in pseudoInteraction.scenes[0].ui!.datasets[0].rows.indices {
        pseudoInteraction.scenes[0].ui!.datasets[0].rows[rowIndex].x = 0.5
        pseudoInteraction.scenes[0].ui!.datasets[0].rows[rowIndex].y = 0.5
        pseudoInteraction.scenes[0].ui!.datasets[0].rows[rowIndex].value = 0
        pseudoInteraction.scenes[0].ui!.datasets[0].rows[rowIndex].result = 0
        pseudoInteraction.scenes[0].ui!.datasets[0].rows[rowIndex].label = nil
    }
    let pseudoPresentation = RichAnswerEngine.prepare(
        envelope: pseudoInteraction,
        environment: RichAnswerEnvironment(
            contextRevision: "revision-ui",
            allowedSourceLabels: ["[材料：函数样例]"]
        )
    )
    try richAnswerRequire(pseudoPresentation.mode == .narrativeOnly, "controls that do not change a derived quantity or mark never render")
    try richAnswerRequire(
        pseudoPresentation.diagnostics.contains(where: { $0.code == .invalidValue }),
        "pseudo interaction exposes invalidValue"
    )

    var missingObligation = composableFrictionEnvelope()
    missingObligation.expressionPlan.knowledgeObjects = ["没有展示的关键对象"]
    let missingObligationPresentation = RichAnswerEngine.prepare(
        envelope: missingObligation,
        environment: RichAnswerEnvironment(
            contextRevision: "revision-friction-composable",
            allowedSourceLabels: ["[材料：斜面摩擦]"]
        )
    )
    try richAnswerRequire(
        missingObligationPresentation.mode == .rich,
        "semantic coverage is judged by Agent planning and real-window review rather than a runtime phrase-matching gate"
    )

    let repaired = RichAnswerEngine.prepare(
        envelope: generatedUIEnvelope(),
        environment: RichAnswerEnvironment(
            contextRevision: "revision-ui",
            allowedSourceLabels: ["[材料：函数样例]"]
        )
    )
    try richAnswerRequire(repaired.mode == .rich, "after a rejected bad tree, a complete repaired rich-answer payload can pass")
}

private func assertOpenUIProgramRejected(
    _ envelope: RichAnswerEnvelope,
    expectedCode: RichAnswerDiagnosticCode,
    _ message: String
) throws {
    let presentation = RichAnswerEngine.prepare(
        envelope: envelope,
        environment: RichAnswerEnvironment(
            contextRevision: "revision-openui",
            allowedSourceLabels: ["[材料：函数样例]"]
        )
    )
    try richAnswerRequire(presentation.mode == .narrativeOnly, message)
    try richAnswerRequire(
        presentation.diagnostics.contains(where: { $0.code == expectedCode }),
        "\(message) exposes \(expectedCode.rawValue)"
    )
}

private func openUIProgramEnvelope() -> RichAnswerEnvelope {
    RichAnswerEnvelope(
        schemaVersion: 2,
        contextRevision: "revision-openui",
        narrative: "拖动 a，观察二次函数开口和宽窄同步变化。",
        expressionPlan: RichAnswerExpressionPlan(
            action: .manipulate,
            summary: "用参数实验连接符号、读数与函数图",
            families: [.quantityAndCoordinates],
            preferredSurface: .expanded,
            directManipulation: true
        ),
        scenes: [
            RichAnswerScene(
                id: "openui-function",
                title: "参数实验",
                family: .quantityAndCoordinates,
                objects: [],
                evidenceIDs: ["program-source"],
                placement: .expanded,
                program: RichAnswerUIProgram(
                    source: """
                    $a = 1
                    root = RichAnswerRoot("数学", "拖动 a", "观察开口和宽窄", "workbench", [controls, graph, sources])
                    controls = LearningStage("controls", "改变参数", [slider, readout])
                    graph = LearningStage("visual", "图像回应", [plot])
                    sources = LearningStage("evidence", "", [evidence])
                    slider = ParameterSlider("a", "参数 a", $a, -3, 3, 0.1, "跨过 0 观察翻转")
                    readout = ParameterReadout("a", $a, "参数和图像共用状态")
                    plot = FunctionPlot("y = ax²", "quadratic", "a", $a, [], -3, 3, 280)
                    evidence = EvidenceSnippet("program-source", "材料", "y = x²", "支撑函数关系")
                    """,
                    capabilities: ["parameter-control", "function-plot", "evidence-jump"],
                    directManipulation: true,
                    maxHeight: 620,
                    graphics: .canvas
                )
            ),
        ],
        evidenceLedger: [
            RichAnswerEvidence(
                id: "program-source",
                sourceLabel: "[材料：函数样例]",
                excerpt: "y = x²"
            ),
        ],
        fallback: RichAnswerFallback(text: "保留函数文字解释。", reason: "OpenUI 不可用")
    )
}

private func checkGeneratedUITreeRenders() throws {
    let presentation = RichAnswerEngine.prepare(
        envelope: generatedUIEnvelope(),
        environment: RichAnswerEnvironment(
            contextRevision: "revision-ui",
            allowedSourceLabels: ["[材料：函数样例]"]
        )
    )

    try richAnswerRequire(presentation.mode == .rich, "a valid generated UI tree stays rich")
    try richAnswerRequire(
        presentation.scenes.first?.ui?.nodes.count == 7,
        "the generated UI node tree survives validation"
    )
    let encoded = try JSONEncoder().encode(generatedUIEnvelope())
    let decoded = RichAnswerEngine.prepare(
        data: encoded,
        fallbackText: "fallback",
        environment: RichAnswerEnvironment(
            contextRevision: "revision-ui",
            allowedSourceLabels: ["[材料：函数样例]"]
        )
    )
    try richAnswerRequire(decoded == presentation, "the generated UI JSON boundary round-trips")
}

private func checkGeneratedUITreeRejectsUnboundEvidenceAndFalseFamily() throws {
    var unboundEvidence = generatedUIEnvelope()
    for nodeIndex in unboundEvidence.scenes[0].ui!.nodes.indices {
        unboundEvidence.scenes[0].ui!.nodes[nodeIndex].evidenceIDs = []
        if unboundEvidence.scenes[0].ui!.nodes[nodeIndex].role == .evidence {
            unboundEvidence.scenes[0].ui!.nodes[nodeIndex].role = .text
            unboundEvidence.scenes[0].ui!.nodes[nodeIndex].text = "来源位置"
        }
    }
    for datasetIndex in unboundEvidence.scenes[0].ui!.datasets.indices {
        for rowIndex in unboundEvidence.scenes[0].ui!.datasets[datasetIndex].rows.indices {
            unboundEvidence.scenes[0].ui!.datasets[datasetIndex].rows[rowIndex].evidenceIDs = []
        }
    }
    let unboundPresentation = RichAnswerEngine.prepare(
        envelope: unboundEvidence,
        environment: RichAnswerEnvironment(
            contextRevision: "revision-ui",
            allowedSourceLabels: ["[材料：函数样例]"]
        )
    )
    try richAnswerRequire(
        unboundPresentation.mode == .narrativeOnly
            && unboundPresentation.diagnostics.contains(where: { $0.code == .missingEvidence }),
        "T2 evidence must reach an actual UI node or data row instead of living on the scene shell"
    )

    var unreachableEvidence = generatedUIEnvelope()
    for nodeIndex in unreachableEvidence.scenes[0].ui!.nodes.indices {
        unreachableEvidence.scenes[0].ui!.nodes[nodeIndex].evidenceIDs = []
        if unreachableEvidence.scenes[0].ui!.nodes[nodeIndex].role == .evidence {
            unreachableEvidence.scenes[0].ui!.nodes[nodeIndex].role = .text
            unreachableEvidence.scenes[0].ui!.nodes[nodeIndex].text = "来源位置"
        }
    }
    for datasetIndex in unreachableEvidence.scenes[0].ui!.datasets.indices {
        for rowIndex in unreachableEvidence.scenes[0].ui!.datasets[datasetIndex].rows.indices {
            unreachableEvidence.scenes[0].ui!.datasets[datasetIndex].rows[rowIndex].evidenceIDs = []
        }
    }
    unreachableEvidence.scenes[0].ui!.datasets.append(
        RichAnswerUIDataset(id: "unused-evidence", rows: [
            RichAnswerUIDataRow(id: "unused-evidence-row", x: 0, y: 0, value: 0, evidenceIDs: ["ui-source"]),
        ])
    )
    let unreachableEvidencePresentation = RichAnswerEngine.prepare(
        envelope: unreachableEvidence,
        environment: RichAnswerEnvironment(
            contextRevision: "revision-ui",
            allowedSourceLabels: ["[材料：函数样例]"]
        )
    )
    try richAnswerRequire(
        unreachableEvidencePresentation.mode == .narrativeOnly
            && unreachableEvidencePresentation.diagnostics.contains(where: { $0.code == .missingEvidence }),
        "T2 evidence in an unused dataset cannot satisfy reachable UI binding"
    )

    var idleBinding = generatedUIEnvelope()
    if let pathIndex = idleBinding.scenes[0].ui!.nodes.firstIndex(where: { $0.id == "ui-path" }) {
        idleBinding.scenes[0].ui!.nodes[pathIndex].bindingID = nil
    }
    let idleBindingPresentation = RichAnswerEngine.prepare(
        envelope: idleBinding,
        environment: RichAnswerEnvironment(
            contextRevision: "revision-ui",
            allowedSourceLabels: ["[材料：函数样例]"]
        )
    )
    try richAnswerRequire(
        idleBindingPresentation.mode == .narrativeOnly
            && idleBindingPresentation.diagnostics.contains(where: { $0.code == .invalidValue }),
        "T2 controls must drive a reachable mark or metric instead of sitting beside the graphic"
    )

    var falseFamily = generatedUIEnvelope()
    falseFamily.expressionPlan.families = [.imageAndOverlay]
    falseFamily.scenes[0].family = .imageAndOverlay
    let falseFamilyPresentation = RichAnswerEngine.prepare(
        envelope: falseFamily,
        environment: RichAnswerEnvironment(
            contextRevision: "revision-ui",
            allowedSourceLabels: ["[材料：函数样例]"]
        )
    )
    try richAnswerRequire(
        falseFamilyPresentation.mode == .rich,
        "runtime accepts a structurally valid generated UI without enforcing an aesthetic family judgment"
    )

    var falseRelationFamily = generatedUIEnvelope()
    falseRelationFamily.expressionPlan.families = [.relationAndEvidence]
    falseRelationFamily.scenes[0].family = .relationAndEvidence
    let falseRelationPresentation = RichAnswerEngine.prepare(
        envelope: falseRelationFamily,
        environment: RichAnswerEnvironment(
            contextRevision: "revision-ui",
            allowedSourceLabels: ["[材料：函数样例]"]
        )
    )
    try richAnswerRequire(
        falseRelationPresentation.mode == .rich,
        "runtime leaves semantic family selection to Agent planning and real-window review"
    )
}

private func checkGeneratedUITreeIntentQualityContracts() throws {
    var legalCurve = generatedUIEnvelope()
    legalCurve.expressionPlan.knowledgeNatures = [.functionOrDataCurve]
    legalCurve.expressionPlan.knowledgeObjects = ["x", "y = x²"]
    legalCurve.expressionPlan.knowledgeRelations = ["x 改变时函数值 y 同步变化"]
    legalCurve.expressionPlan.visualPrimitives = ["canvas", "path", "slider"]
    legalCurve.expressionPlan.visualRationale = ["函数和数据关系适合用曲线、坐标和探针表达"]
    if let titleIndex = legalCurve.scenes[0].ui?.nodes.firstIndex(where: { $0.id == "ui-title" }) {
        legalCurve.scenes[0].ui?.nodes[titleIndex].text = "拖动 x，函数值 y 同步变化"
    }
    let legalCurvePresentation = RichAnswerEngine.prepare(
        envelope: legalCurve,
        environment: RichAnswerEnvironment(
            contextRevision: "revision-ui",
            allowedSourceLabels: ["[材料：函数样例]"]
        )
    )
    try richAnswerRequire(
        legalCurvePresentation.mode == .rich,
        "function and data relationships can still use a curve, coordinate canvas, and probe"
    )

    var relationWithoutAnchors = generatedUISequenceEnvelope()
    relationWithoutAnchors.expressionPlan.knowledgeNatures = [.argumentOrEvidence]
    relationWithoutAnchors.expressionPlan.knowledgeObjects = []
    relationWithoutAnchors.expressionPlan.knowledgeRelations = ["港口拥堵通过交付延迟推高安全库存"]
    let relationWithoutAnchorsPresentation = RichAnswerEngine.prepare(
        envelope: relationWithoutAnchors,
        environment: RichAnswerEnvironment(
            contextRevision: "revision-sequence-t2",
            allowedSourceLabels: ["[材料：论证片段]"]
        )
    )
    try richAnswerRequire(
        relationWithoutAnchorsPresentation.mode == .rich,
        "runtime does not turn visible semantic-anchor quality into a content rejection gate"
    )

    var formulaAnchoredLongRelation = composablePendulumEnvelope()
    formulaAnchoredLongRelation.expressionPlan.knowledgeNatures = [.functionOrDataCurve]
    formulaAnchoredLongRelation.expressionPlan.knowledgeObjects = ["摆长 L", "周期 T", "T = 2π√(L/g)"]
    formulaAnchoredLongRelation.expressionPlan.knowledgeRelations = [
        "T = 2π√(L/g)：摆长 L 从 0.25 m 到 2.0 m 时周期 T 增长",
    ]
    formulaAnchoredLongRelation.expressionPlan.visualPrimitives = ["canvas", "path", "point", "metric", "probe"]
    let formulaAnchoredLongRelationPresentation = RichAnswerEngine.prepare(
        envelope: formulaAnchoredLongRelation,
        environment: RichAnswerEnvironment(
            contextRevision: "revision-pendulum-t2",
            allowedSourceLabels: ["[材料：单摆周期]"]
        )
    )
    try richAnswerRequire(
        formulaAnchoredLongRelationPresentation.mode == .rich,
        "long relationship paraphrases pass when formula and numeric anchors are visible"
    )

    var meaninglessWeakUI = generatedUIEnvelope()
    meaninglessWeakUI.scenes[0].title = "变化面板"
    if let titleIndex = meaninglessWeakUI.scenes[0].ui?.nodes.firstIndex(where: { $0.id == "ui-title" }) {
        meaninglessWeakUI.scenes[0].ui?.nodes[titleIndex].label = "数值"
        meaninglessWeakUI.scenes[0].ui?.nodes[titleIndex].text = "调一调，看变化"
    }
    if let sliderIndex = meaninglessWeakUI.scenes[0].ui?.nodes.firstIndex(where: { $0.id == "ui-slider" }) {
        meaninglessWeakUI.scenes[0].ui?.nodes[sliderIndex].label = "参数"
    }
    meaninglessWeakUI.scenes[0].ui?.bindings[0].label = "参数"
    meaninglessWeakUI.expressionPlan.knowledgeNatures = [.functionOrDataCurve]
    meaninglessWeakUI.expressionPlan.knowledgeObjects = ["边际成本", "供给曲线"]
    meaninglessWeakUI.expressionPlan.knowledgeRelations = ["边际成本递增导致供给曲线向上倾斜"]
    meaninglessWeakUI.expressionPlan.visualPrimitives = ["canvas", "path", "slider"]
    let meaninglessWeakUIPresentation = RichAnswerEngine.prepare(
        envelope: meaninglessWeakUI,
        environment: RichAnswerEnvironment(
            contextRevision: "revision-ui",
            allowedSourceLabels: ["[材料：函数样例]"]
        )
    )
    try richAnswerRequire(
        meaninglessWeakUIPresentation.mode == .rich,
        "generic labels and weak_ui are not runtime invalidValue hard failures when the structure is legal; real-window visual review judges usefulness"
    )

    let weakPhysics = weakPhysicsLineOnlyEnvelope()
    let weakPhysicsPresentation = RichAnswerEngine.prepare(
        envelope: weakPhysics,
        environment: RichAnswerEnvironment(
            contextRevision: "revision-weak-physics-line-only",
            allowedSourceLabels: ["[材料：斜面摩擦]"]
        )
    )
    let weakPhysicsDiagnostics = weakPhysicsPresentation.diagnostics.map {
        "\($0.code.rawValue):\($0.message)"
    }.joined(separator: " | ")
    try richAnswerRequire(
        weakPhysicsPresentation.mode == .rich,
        "a semantically labeled line, changing readout, and real control may express a process without a forced shape component; diagnostics=\(weakPhysicsDiagnostics)"
    )

    let compositePhysics = composableFrictionEnvelope()
    let compositePhysicsPresentation = RichAnswerEngine.prepare(
        envelope: compositePhysics,
        environment: RichAnswerEnvironment(
            contextRevision: "revision-friction-composable",
            allowedSourceLabels: ["[材料：斜面摩擦]"]
        )
    )
    let roles = Set(compositePhysicsPresentation.scenes.first?.ui?.nodes.map(\.role) ?? [])
    let diagnostics = compositePhysicsPresentation.diagnostics.map {
        "\($0.code.rawValue):\($0.message)"
    }.joined(separator: " | ")
    let expectedCompositeRoles: Set<RichAnswerUIRole> = [.canvas, .shape, .vector, .sequence, .toggle]
    try richAnswerRequire(
        compositePhysicsPresentation.mode == .rich
            && expectedCompositeRoles.isSubset(of: roles),
        "object and process questions pass when generic shape, vector, sequence, and controls express the mechanism; diagnostics=\(diagnostics); roles=\(roles.map(\.rawValue).sorted().joined(separator: ","))"
    )

    var sliderBoundCurveReadout = generatedUIEnvelope()
    sliderBoundCurveReadout.expressionPlan.knowledgeNatures = [.functionOrDataCurve]
    sliderBoundCurveReadout.expressionPlan.knowledgeObjects = ["x", "y = x²"]
    sliderBoundCurveReadout.expressionPlan.knowledgeRelations = ["x 改变时 y 按曲线同步变化"]
    sliderBoundCurveReadout.expressionPlan.knowledgeProcesses = ["拖动观察联动"]
    sliderBoundCurveReadout.expressionPlan.visualPrimitives = ["canvas", "path", "slider", "metric"]
    sliderBoundCurveReadout.expressionPlan.visualRationale = ["滑杆共享绑定，曲线和读数同时响应"]
    if let titleIndex = sliderBoundCurveReadout.scenes[0].ui?.nodes.firstIndex(where: { $0.id == "ui-title" }) {
        sliderBoundCurveReadout.scenes[0].ui?.nodes[titleIndex].text = "x 与函数值 y 共享同一状态"
    }
    sliderBoundCurveReadout.scenes[0].ui?.nodes.append(
        RichAnswerUINode(
            id: "ui-readout",
            role: .metric,
            label: "函数值 y",
            datasetID: "ui-curve",
            bindingID: "ui-x",
            evidenceIDs: ["ui-source"],
            tone: .accent
        )
    )
    sliderBoundCurveReadout.scenes[0].ui?.nodes[0].children.insert("ui-readout", at: 2)
    let sliderBoundRoles = Set(sliderBoundCurveReadout.scenes[0].ui?.nodes.map(\.role) ?? [])
    let sliderBoundIDs = Set(
        sliderBoundCurveReadout.scenes[0].ui?.nodes.compactMap(\.bindingID) ?? []
    )
    try richAnswerRequire(
        [.path, .slider, .metric].allSatisfy(sliderBoundRoles.contains)
            && sliderBoundIDs.contains("ui-x")
            && sliderBoundCurveReadout.scenes[0].ui?.bindings.first?.id == "ui-x",
        "regression fixture binds one slider to both curve and readout"
    )
    let sliderBoundCurveReadoutPresentation = RichAnswerEngine.prepare(
        envelope: sliderBoundCurveReadout,
        environment: RichAnswerEnvironment(
            contextRevision: "revision-ui",
            allowedSourceLabels: ["[材料：函数样例]"]
        )
    )
    let sliderBoundDiagnostics = sliderBoundCurveReadoutPresentation.diagnostics.map {
        "\($0.code.rawValue):\($0.message)"
    }.joined(separator: " | ")
    try richAnswerRequire(
        sliderBoundCurveReadoutPresentation.mode == .rich,
        "slider-bound curve and readout satisfy drag-observe linkage without copying the exact phrase; diagnostics=\(sliderBoundDiagnostics)"
    )
}

private func checkGeneratedUISequencePrimitiveRenders() throws {
    let envelope = generatedUISequenceEnvelope()
    let presentation = RichAnswerEngine.prepare(
        envelope: envelope,
        environment: RichAnswerEnvironment(
            contextRevision: "revision-sequence-t2",
            allowedSourceLabels: ["[材料：论证片段]"]
        )
    )

    guard let scene = presentation.scenes.first,
          let ui = scene.ui else {
        throw RichAnswerProtocolCheckError.failed("the T2 sequence scene survives validation")
    }
    let sequence = ui.nodes.first(where: { $0.role == .sequence })
    let scrubber = ui.nodes.first(where: { $0.role == .scrubber })
    try richAnswerRequire(presentation.mode == .rich, "a generic sequence primitive stays rich")
    try richAnswerRequire(scene.program == nil && sequence?.datasetID == "sequence-rows", "sequence is a T2 primitive backed by a dataset")
    try richAnswerRequire(sequence?.bindingID == "sequence-step" && scrubber?.bindingID == "sequence-step", "sequence and scrubber share one binding")
    try richAnswerRequire(
        ui.datasets.first(where: { $0.id == "sequence-rows" })?.rows.allSatisfy { $0.label?.isEmpty == false } == true,
        "sequence rows expose visible semantic labels"
    )

    var invalid = envelope
    invalid.scenes[0].ui?.datasets[0].rows[1].label = nil
    let rejected = RichAnswerEngine.prepare(
        envelope: invalid,
        environment: RichAnswerEnvironment(
            contextRevision: "revision-sequence-t2",
            allowedSourceLabels: ["[材料：论证片段]"]
        )
    )
    try richAnswerRequire(rejected.mode == .narrativeOnly, "sequence without visible row labels cannot render")
    try richAnswerRequire(
        rejected.diagnostics.contains(where: { $0.code == .invalidValue }),
        "sequence label rejection exposes an invalid-value diagnostic"
    )
}

private func checkComposablePendulumRendersWithoutSpecializedComponent() throws {
    let envelope = composablePendulumEnvelope()
    let presentation = RichAnswerEngine.prepare(
        envelope: envelope,
        environment: RichAnswerEnvironment(
            contextRevision: "revision-pendulum-t2",
            allowedSourceLabels: ["[材料：单摆周期]"]
        )
    )

    guard let scene = presentation.scenes.first else {
        throw RichAnswerProtocolCheckError.failed("the T2 pendulum scene survives validation")
    }
    let roles = Set(scene.ui?.nodes.map(\.role) ?? [])
    try richAnswerRequire(presentation.mode == .rich, "a problem without a specialized component stays rich through T2 primitives")
    try richAnswerRequire(scene.program == nil && scene.ui != nil, "the pendulum acceptance case does not hide a specialized OpenUI component")
    try richAnswerRequire(
        [.canvas, .path, .point, .metric, .probe].allSatisfy(roles.contains),
        "the pendulum acceptance case is composed from generic visual and interaction primitives"
    )
    try richAnswerRequire(presentation.diagnostics.isEmpty, "the generic pendulum composition needs no repair or text fallback")

    let data = try JSONEncoder().encode(envelope)
    let decoded = RichAnswerEngine.prepare(
        data: data,
        fallbackText: "fallback",
        environment: RichAnswerEnvironment(
            contextRevision: "revision-pendulum-t2",
            allowedSourceLabels: ["[材料：单摆周期]"]
        )
    )
    try richAnswerRequire(decoded == presentation, "the generic pendulum program round-trips through the Agent JSON boundary")
}

private func generatedUISequenceEnvelope() -> RichAnswerEnvelope {
    RichAnswerEnvelope(
        schemaVersion: 2,
        contextRevision: "revision-sequence-t2",
        narrative: "这条论证要按顺序读：先看前提，再看桥接关系，最后回到结论。",
        expressionPlan: RichAnswerExpressionPlan(
            action: .trace,
            summary: "用通用 sequence 表达步骤和证据链",
            families: [.relationAndEvidence],
            preferredSurface: .inline,
            directManipulation: true
        ),
        scenes: [
            RichAnswerScene(
                id: "sequence-primitive",
                title: "证据链",
                family: .relationAndEvidence,
                objects: [],
                evidenceIDs: ["sequence-source"],
                placement: .inline,
                ui: RichAnswerUIComposition(
                    rootID: "sequence-root",
                    nodes: [
                        RichAnswerUINode(id: "sequence-root", role: .vstack, children: ["sequence-node", "sequence-scrubber", "sequence-evidence"]),
                        RichAnswerUINode(id: "sequence-node", role: .sequence, label: "读法顺序", datasetID: "sequence-rows", bindingID: "sequence-step", evidenceIDs: ["sequence-source"]),
                        RichAnswerUINode(id: "sequence-scrubber", role: .scrubber, label: "当前节点", bindingID: "sequence-step"),
                        RichAnswerUINode(id: "sequence-evidence", role: .evidence, evidenceIDs: ["sequence-source"]),
                    ],
                    datasets: [
                        RichAnswerUIDataset(id: "sequence-rows", rows: [
                            RichAnswerUIDataRow(id: "sequence-row-a", x: 0, y: 0.5, value: 0, label: "前提：公共空间有价值", evidenceIDs: ["sequence-source"]),
                            RichAnswerUIDataRow(id: "sequence-row-b", x: 0.5, y: 0.5, value: 1, label: "桥接：留停产生联系", evidenceIDs: ["sequence-source"]),
                            RichAnswerUIDataRow(id: "sequence-row-c", x: 1, y: 0.5, value: 2, label: "结论：作者仍需证明因果", evidenceIDs: ["sequence-source"]),
                        ]),
                    ],
                    bindings: [
                        RichAnswerUIBinding(id: "sequence-step", label: "步骤", minimum: 0, maximum: 2, step: 1, initialValue: 0),
                    ]
                )
            ),
        ],
        evidenceLedger: [
            RichAnswerEvidence(id: "sequence-source", sourceLabel: "[材料：论证片段]", excerpt: "作者先提出公共空间价值，再讨论留停与联系。"),
        ],
        fallback: RichAnswerFallback(text: "按前提、桥接、结论读。", reason: "sequence 原语不可用")
    )
}

private func checkGeneratedUITreeRejectsCycles() throws {
    var envelope = generatedUIEnvelope()
    envelope.scenes[0].ui?.nodes = [
        RichAnswerUINode(id: "ui-root", role: .vstack, children: ["ui-panel"]),
        RichAnswerUINode(id: "ui-panel", role: .panel, children: ["ui-root"]),
    ]
    envelope.scenes[0].ui?.rootID = "ui-root"
    let presentation = RichAnswerEngine.prepare(
        envelope: envelope,
        environment: RichAnswerEnvironment(
            contextRevision: "revision-ui",
            allowedSourceLabels: ["[材料：函数样例]"]
        )
    )

    try richAnswerRequire(presentation.mode == .narrativeOnly, "a cyclic generated UI tree cannot render")
    try richAnswerRequire(
        presentation.diagnostics.contains(where: { $0.code == .invalidValue }),
        "a cyclic generated UI tree exposes an invalid-value diagnostic"
    )
}

private func checkGeneratedUITreeAllowsCoordinatedControls() throws {
    var envelope = generatedUIEnvelope()
    envelope.scenes[0].ui?.nodes.append(contentsOf: [
        RichAnswerUINode(id: "ui-slider-two", role: .slider, bindingID: "ui-x"),
        RichAnswerUINode(id: "ui-slider-three", role: .probe, bindingID: "ui-x"),
    ])
    envelope.scenes[0].ui?.nodes[0].children.append(contentsOf: ["ui-slider-two", "ui-slider-three"])
    let presentation = RichAnswerEngine.prepare(
        envelope: envelope,
        environment: RichAnswerEnvironment(
            contextRevision: "revision-ui",
            allowedSourceLabels: ["[材料：函数样例]"]
        )
    )

    try richAnswerRequire(
        presentation.mode == .rich,
        "multiple coordinated controls remain available when they share one learning goal"
    )
}

private func generatedUIEnvelope() -> RichAnswerEnvelope {
    RichAnswerEnvelope(
        schemaVersion: 2,
        contextRevision: "revision-ui",
        narrative: "拖动 x，观察 y = x² 的曲线与读数。",
        expressionPlan: RichAnswerExpressionPlan(
            action: .manipulate,
            summary: "模型组合函数图、探针和来源",
            families: [.quantityAndCoordinates],
            preferredSurface: .expanded,
            directManipulation: true
        ),
        scenes: [
            RichAnswerScene(
                id: "generated-function",
                title: "函数探针",
                family: .quantityAndCoordinates,
                objects: [],
                evidenceIDs: ["ui-source"],
                placement: .expanded,
                ui: RichAnswerUIComposition(
                    rootID: "ui-root",
                    nodes: [
                        RichAnswerUINode(id: "ui-root", role: .vstack, children: ["ui-title", "ui-canvas", "ui-slider", "ui-evidence"]),
                        RichAnswerUINode(id: "ui-title", role: .text, label: "y = x²", text: "拖动 x 查看函数值", evidenceIDs: ["ui-source"], emphasis: .strong),
                        RichAnswerUINode(id: "ui-canvas", role: .canvas, children: ["ui-axis", "ui-path"], xAxis: RichAnswerAxis(label: "x", minimum: -1, maximum: 1), yAxis: RichAnswerAxis(label: "y", minimum: 0, maximum: 1)),
                        RichAnswerUINode(id: "ui-axis", role: .axis),
                        RichAnswerUINode(id: "ui-path", role: .path, datasetID: "ui-curve", bindingID: "ui-x", evidenceIDs: ["ui-source"]),
                        RichAnswerUINode(id: "ui-slider", role: .slider, label: "x", bindingID: "ui-x"),
                        RichAnswerUINode(id: "ui-evidence", role: .evidence, evidenceIDs: ["ui-source"]),
                    ],
                    datasets: [
                        RichAnswerUIDataset(id: "ui-curve", rows: [
                            RichAnswerUIDataRow(id: "ui-row-a", x: 0, y: 1, value: -1, result: 1, evidenceIDs: ["ui-source"]),
                            RichAnswerUIDataRow(id: "ui-row-b", x: 0.5, y: 0, value: 0, result: 0, evidenceIDs: ["ui-source"]),
                            RichAnswerUIDataRow(id: "ui-row-c", x: 1, y: 1, value: 1, result: 1, evidenceIDs: ["ui-source"]),
                        ]),
                    ],
                    bindings: [
                        RichAnswerUIBinding(id: "ui-x", label: "x", minimum: -1, maximum: 1, step: 0.25, initialValue: 0),
                    ]
                )
            ),
        ],
        evidenceLedger: [
            RichAnswerEvidence(id: "ui-source", sourceLabel: "[材料：函数样例]", excerpt: "y = x²"),
        ],
        fallback: RichAnswerFallback(text: "y = x²", reason: "生成式 UI 不可用")
    )
}

private func composablePendulumEnvelope() -> RichAnswerEnvelope {
    let lengths = [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2.0]
    let rows = lengths.enumerated().map { index, length in
        let period = 2 * Double.pi * sqrt(length / 9.81)
        return RichAnswerUIDataRow(
            id: "pendulum-row-\(index)",
            x: (length - 0.25) / 1.75,
            y: period / 3.2,
            value: length,
            result: period,
            label: "L=\(String(format: "%.2f", length)) m",
            evidenceIDs: ["pendulum-source"]
        )
    }
    return RichAnswerEnvelope(
        schemaVersion: 2,
        contextRevision: "revision-pendulum-t2",
        narrative: "小角度近似下，周期随摆长的平方根增长。",
        expressionPlan: RichAnswerExpressionPlan(
            action: .manipulate,
            summary: "用通用路径、探针和读数解释单摆关系",
            families: [.quantityAndCoordinates],
            preferredSurface: .inline,
            directManipulation: true
        ),
        scenes: [
            RichAnswerScene(
                id: "pendulum-primitives",
                title: "单摆关系",
                family: .quantityAndCoordinates,
                objects: [],
                evidenceIDs: ["pendulum-source"],
                placement: .inline,
                ui: RichAnswerUIComposition(
                    rootID: "pendulum-root",
                    nodes: [
                        RichAnswerUINode(id: "pendulum-root", role: .vstack, children: ["pendulum-formula", "pendulum-metric", "pendulum-canvas", "pendulum-probe", "pendulum-evidence"]),
                        RichAnswerUINode(id: "pendulum-formula", role: .text, text: "T = 2π√(L/g)", evidenceIDs: ["pendulum-source"], emphasis: .strong),
                        RichAnswerUINode(id: "pendulum-metric", role: .metric, label: "当前周期", unit: "s", datasetID: "pendulum-curve", bindingID: "pendulum-length", evidenceIDs: ["pendulum-source"], tone: .accent, emphasis: .strong),
                        RichAnswerUINode(id: "pendulum-canvas", role: .canvas, children: ["pendulum-axis", "pendulum-path", "pendulum-points"], xAxis: RichAnswerAxis(label: "摆长 L", minimum: 0.25, maximum: 2, unit: "m"), yAxis: RichAnswerAxis(label: "周期 T", minimum: 0, maximum: 3.2, unit: "s")),
                        RichAnswerUINode(id: "pendulum-axis", role: .axis),
                        RichAnswerUINode(id: "pendulum-path", role: .path, datasetID: "pendulum-curve", evidenceIDs: ["pendulum-source"], emphasis: .strong),
                        RichAnswerUINode(id: "pendulum-points", role: .point, datasetID: "pendulum-curve", bindingID: "pendulum-length", evidenceIDs: ["pendulum-source"]),
                        RichAnswerUINode(id: "pendulum-probe", role: .probe, label: "摆长 L", bindingID: "pendulum-length"),
                        RichAnswerUINode(id: "pendulum-evidence", role: .evidence, evidenceIDs: ["pendulum-source"]),
                    ],
                    datasets: [RichAnswerUIDataset(id: "pendulum-curve", rows: rows)],
                    bindings: [RichAnswerUIBinding(id: "pendulum-length", label: "摆长 L", minimum: 0.25, maximum: 2, step: 0.05, initialValue: 1, unit: "m")]
                )
            ),
        ],
        evidenceLedger: [
            RichAnswerEvidence(
                id: "pendulum-source",
                sourceLabel: "[材料：单摆周期]",
                excerpt: "在小角度近似下，单摆周期 T = 2π√(L/g)。"
            ),
        ],
        fallback: RichAnswerFallback(text: "周期随摆长的平方根增长。", reason: "T2 原语不可用")
    )
}

private func weakPhysicsLineOnlyEnvelope() -> RichAnswerEnvelope {
    RichAnswerEnvelope(
        schemaVersion: 2,
        contextRevision: "revision-weak-physics-line-only",
        narrative: "摩擦方向取决于潜在相对运动趋势。",
        expressionPlan: RichAnswerExpressionPlan(
            action: .manipulate,
            summary: "声明要解释斜面物块和摩擦反转，却只给读数曲线",
            families: [.processAndState],
            preferredSurface: .inline,
            directManipulation: true,
            knowledgeNatures: [.objectMechanism, .processOrState],
            knowledgeObjects: ["斜面物块", "静摩擦力"],
            knowledgeRelations: ["摩擦力阻碍潜在相对运动"],
            knowledgeProcesses: ["外力向上足够大时摩擦方向反转"],
            visualPrimitives: ["canvas", "line", "metric", "slider"],
            visualRationale: ["这个反例故意只给线图和读数，用于验证结构合法时仍可进入 rich，视觉质量交给真实窗口审查"]
        ),
        scenes: [
            RichAnswerScene(
                id: "weak-friction-line",
                title: "斜面摩擦弱反例",
                family: .processAndState,
                objects: [],
                evidenceIDs: ["friction-source"],
                placement: .inline,
                ui: RichAnswerUIComposition(
                    rootID: "weak-friction-root",
                    nodes: [
                        RichAnswerUINode(id: "weak-friction-root", role: .vstack, children: ["weak-friction-text", "weak-friction-metric", "weak-friction-canvas", "weak-friction-slider", "weak-friction-evidence"]),
                        RichAnswerUINode(id: "weak-friction-text", role: .text, text: "斜面物块的静摩擦力会随潜在运动趋势反转。", evidenceIDs: ["friction-source"]),
                        RichAnswerUINode(id: "weak-friction-metric", role: .metric, label: "摩擦方向读数", datasetID: "weak-friction-data", bindingID: "applied-force", evidenceIDs: ["friction-source"]),
                        RichAnswerUINode(id: "weak-friction-canvas", role: .canvas, children: ["weak-friction-line"], xAxis: RichAnswerAxis(label: "外力", minimum: 0, maximum: 2), yAxis: RichAnswerAxis(label: "摩擦方向", minimum: -1, maximum: 1)),
                        RichAnswerUINode(id: "weak-friction-line", role: .line, datasetID: "weak-friction-data", bindingID: "applied-force", evidenceIDs: ["friction-source"]),
                        RichAnswerUINode(id: "weak-friction-slider", role: .slider, label: "外力", bindingID: "applied-force"),
                        RichAnswerUINode(id: "weak-friction-evidence", role: .evidence, evidenceIDs: ["friction-source"]),
                    ],
                    datasets: [
                        RichAnswerUIDataset(id: "weak-friction-data", rows: [
                            RichAnswerUIDataRow(id: "weak-friction-a", x: 0, y: 0.2, value: 0, result: 1, evidenceIDs: ["friction-source"]),
                            RichAnswerUIDataRow(id: "weak-friction-b", x: 1, y: 0.8, value: 1, result: -1, evidenceIDs: ["friction-source"]),
                        ]),
                    ],
                    bindings: [
                        RichAnswerUIBinding(id: "applied-force", label: "外力", minimum: 0, maximum: 2, step: 1, initialValue: 0),
                    ]
                )
            ),
        ],
        evidenceLedger: [
            RichAnswerEvidence(
                id: "friction-source",
                sourceLabel: "[材料：斜面摩擦]",
                excerpt: "摩擦力阻碍潜在相对运动，方向取决于物块相对斜面的运动趋势。"
            ),
        ],
        fallback: RichAnswerFallback(text: "摩擦方向取决于潜在运动趋势。", reason: "T2 弱反例不可用")
    )
}

private func composableFrictionEnvelope() -> RichAnswerEnvelope {
    RichAnswerEnvelope(
        schemaVersion: 2,
        contextRevision: "revision-friction-composable",
        narrative: "摩擦力不是固定向左或向右，而是阻碍潜在相对运动。",
        expressionPlan: RichAnswerExpressionPlan(
            action: .manipulate,
            summary: "用斜面形状、力向量、状态序列和开关表达摩擦方向反转",
            families: [.processAndState, .timeAndSpace],
            preferredSurface: .inline,
            directManipulation: true,
            knowledgeNatures: [.objectMechanism, .spatialStructure, .processOrState],
            knowledgeObjects: ["斜面物块", "重力分量", "支持力", "静摩擦力"],
            knowledgeRelations: ["摩擦力阻碍潜在相对运动"],
            knowledgeProcesses: ["外力改变潜在运动趋势时摩擦方向反转"],
            visualPrimitives: ["canvas", "shape", "vector", "sequence", "toggle"],
            visualRationale: ["物体、空间和过程题需要用形状、方向向量和状态序列表达机制"]
        ),
        scenes: [
            RichAnswerScene(
                id: "friction-primitives",
                title: "斜面摩擦机制",
                family: .processAndState,
                objects: [],
                evidenceIDs: ["friction-source"],
                placement: .inline,
                ui: RichAnswerUIComposition(
                    rootID: "friction-root",
                    nodes: [
                        RichAnswerUINode(id: "friction-root", role: .vstack, children: ["friction-canvas", "friction-toggle", "friction-sequence", "friction-evidence"]),
                        RichAnswerUINode(id: "friction-canvas", role: .canvas, children: ["incline-shape", "block-shape", "gravity-vector", "normal-vector", "friction-vector"]),
                        RichAnswerUINode(id: "incline-shape", role: .shape, label: "粗糙斜面", evidenceIDs: ["friction-source"], region: RichAnswerRegion(x: 0.08, y: 0.48, width: 0.74, height: 0.36), shape: .triangle, fill: .soft),
                        RichAnswerUINode(id: "block-shape", role: .shape, label: "物块", evidenceIDs: ["friction-source"], region: RichAnswerRegion(x: 0.42, y: 0.36, width: 0.14, height: 0.11), shape: .rectangle, fill: .solid),
                        RichAnswerUINode(id: "gravity-vector", role: .vector, label: "重力沿斜面分量向下", datasetID: "gravity-vector-data", evidenceIDs: ["friction-source"]),
                        RichAnswerUINode(id: "normal-vector", role: .vector, label: "支持力垂直斜面", datasetID: "normal-vector-data", evidenceIDs: ["friction-source"]),
                        RichAnswerUINode(id: "friction-vector", role: .vector, label: "静摩擦方向随趋势反转", datasetID: "friction-vector-data", bindingID: "force-state", evidenceIDs: ["friction-source"], tone: .accent),
                        RichAnswerUINode(id: "friction-toggle", role: .toggle, label: "施加向上外力", bindingID: "force-state"),
                        RichAnswerUINode(id: "friction-sequence", role: .sequence, label: "潜在相对运动 → 阻碍 → 方向", datasetID: "friction-states", bindingID: "force-state", evidenceIDs: ["friction-source"]),
                        RichAnswerUINode(id: "friction-evidence", role: .evidence, evidenceIDs: ["friction-source"]),
                    ],
                    datasets: [
                        RichAnswerUIDataset(id: "gravity-vector-data", rows: [
                            RichAnswerUIDataRow(id: "gravity-vector-row", x: 0.50, y: 0.42, x2: 0.35, y2: 0.58, label: "沿斜面向下", evidenceIDs: ["friction-source"]),
                        ]),
                        RichAnswerUIDataset(id: "normal-vector-data", rows: [
                            RichAnswerUIDataRow(id: "normal-vector-row", x: 0.50, y: 0.42, x2: 0.56, y2: 0.26, label: "垂直斜面", evidenceIDs: ["friction-source"]),
                        ]),
                        RichAnswerUIDataset(id: "friction-vector-data", rows: [
                            RichAnswerUIDataRow(id: "friction-vector-up", x: 0.50, y: 0.42, x2: 0.64, y2: 0.34, value: 0, label: "无外力：摩擦沿斜面向上", evidenceIDs: ["friction-source"]),
                            RichAnswerUIDataRow(id: "friction-vector-down", x: 0.50, y: 0.42, x2: 0.35, y2: 0.58, value: 1, label: "外力足够大：摩擦沿斜面向下", evidenceIDs: ["friction-source"]),
                        ]),
                        RichAnswerUIDataset(id: "friction-states", rows: [
                            RichAnswerUIDataRow(id: "friction-state-a", x: 0, y: 0, value: 0, label: "无外力：潜在下滑，摩擦向上", evidenceIDs: ["friction-source"]),
                            RichAnswerUIDataRow(id: "friction-state-b", x: 1, y: 1, value: 1, label: "向上外力足够大：潜在上滑，摩擦向下", evidenceIDs: ["friction-source"]),
                        ]),
                    ],
                    bindings: [
                        RichAnswerUIBinding(id: "force-state", label: "外力状态", minimum: 0, maximum: 1, step: 1, initialValue: 0),
                    ]
                )
            ),
        ],
        evidenceLedger: [
            RichAnswerEvidence(
                id: "friction-source",
                sourceLabel: "[材料：斜面摩擦]",
                excerpt: "静摩擦力阻碍潜在相对运动；若再施加足够大的沿斜面向上外力，静摩擦方向会反转。"
            ),
        ],
        fallback: RichAnswerFallback(text: "摩擦方向取决于潜在运动趋势。", reason: "T2 原语不可用")
    )
}

private func checkAssetAliasesResolveBeforePersistence() throws {
    var envelope = minimalEnvelope(contextRevision: "revision-7")
    envelope.expressionPlan.families = [.imageAndOverlay]
    envelope.expressionPlan.directManipulation = false
    envelope.scenes = [
        RichAnswerScene(
            id: "image-scene",
            title: "图像定位",
            family: .imageAndOverlay,
            objects: [
                RichAnswerObject(
                    id: "image",
                    kind: .image,
                    label: "材料原图",
                    evidenceIDs: ["source-1"],
                    assetID: "course-item-1",
                    frameID: "image-frame"
                ),
                RichAnswerObject(
                    id: "region",
                    kind: .region,
                    label: "关键段落",
                    evidenceIDs: ["source-1"],
                    frameID: "image-frame",
                    bounds: RichAnswerRegion(x: 0.12, y: 0.16, width: 0.42, height: 0.18)
                ),
            ],
            frames: [
                RichAnswerFrame(
                    id: "image-frame",
                    kind: .image,
                    title: "材料原图",
                    objectIDs: ["image", "region"],
                    assetID: "course-item-1",
                    evidenceIDs: ["source-1"]
                ),
            ],
            evidenceIDs: ["source-1"],
            renderPlan: RichAnswerRenderPlan(
                renderer: RichAnswerRendererRegistry.imageOverlayRenderer,
                specVersion: "weibei.image-overlay.v1",
                spec: RichAnswerRenderSpec(fields: [
                    "image": .object([
                        "kind": .string("assetRef"),
                        "source": .string("course-item-1"),
                    ]),
                    "layers": .array([
                        .object([
                            "id": .string("observation"),
                            "features": .array([]),
                        ]),
                    ]),
                ]),
                sourceBindings: [
                    RichAnswerRenderSourceBinding(
                        id: "source-image",
                        evidenceID: "source-1",
                        target: "image.source",
                        role: "artifact"
                    ),
                ],
                fallback: RichAnswerRenderFallback(
                    mode: .narrativeOnly,
                    reason: "图像叠层不可用",
                    text: "保留来源绑定的文字说明。"
                )
            )
        ),
    ]
    envelope.evidenceLedger[0].assetIDs = ["course-item-1"]
    let presentation = RichAnswerEngine.prepare(
        envelope: envelope,
        environment: RichAnswerEnvironment(
            contextRevision: "revision-7",
            allowedSourceLabels: ["[材料：样例]"],
            allowedAssetIDs: ["course-item-1"]
        )
    ).resolvingAssetIDs(using: ["course-item-1": "persistent-material-id"])

    try richAnswerRequire(presentation.mode == .rich, "a grounded local image may render")
    try richAnswerRequire(
        presentation.scenes[0].objects[0].assetID == "persistent-material-id"
            && presentation.scenes[0].frames[0].assetID == "persistent-material-id"
            && presentation.scenes[0].renderPlan?.spec["image"] == .object([
                "kind": .string("assetRef"),
                "source": .string("persistent-material-id"),
            ])
            && presentation.evidenceLedger[0].assetIDs == ["persistent-material-id"],
        "request-local asset aliases resolve across legacy, UI, renderPlan, and evidence before persistence"
    )
}

private func checkDirectManipulationPlanMatchesOperations() throws {
    var envelope = minimalEnvelope(contextRevision: "revision-7")
    envelope.expressionPlan.directManipulation = false
    let presentation = RichAnswerEngine.prepare(
        envelope: envelope,
        environment: RichAnswerEnvironment(
            contextRevision: "revision-7",
            allowedSourceLabels: ["[材料：样例]"]
        )
    )

    try richAnswerRequire(presentation.mode == .narrativeOnly, "an understated interaction plan cannot render")
    try richAnswerRequire(
        presentation.diagnostics.contains(where: { $0.code == .invalidParameter }),
        "an interaction-plan mismatch exposes a protocol diagnostic"
    )
}

private func checkImageRegionsStayInsideTheirFrame() throws {
    var envelope = minimalEnvelope(contextRevision: "revision-7")
    envelope.expressionPlan.families = [.imageAndOverlay]
    envelope.scenes = [
        RichAnswerScene(
            id: "overlay",
            title: "图像叠层",
            family: .imageAndOverlay,
            objects: [
                RichAnswerObject(
                    id: "region",
                    kind: .region,
                    label: "越界区域",
                    frameID: "image-frame",
                    bounds: RichAnswerRegion(x: 0.8, y: 0.2, width: 0.4, height: 0.4)
                ),
            ],
            frames: [
                RichAnswerFrame(id: "image-frame", kind: .image, title: "原图", objectIDs: ["region"]),
            ],
            evidenceIDs: ["source-1"]
        ),
    ]
    let presentation = RichAnswerEngine.prepare(
        envelope: envelope,
        environment: RichAnswerEnvironment(
            contextRevision: "revision-7",
            allowedSourceLabels: ["[材料：样例]"]
        )
    )

    try richAnswerRequire(presentation.mode == .narrativeOnly, "an out-of-bounds overlay cannot render")
    try richAnswerRequire(
        presentation.diagnostics.contains(where: { $0.sceneID == "overlay" && $0.code == .invalidValue }),
        "an out-of-bounds overlay exposes a scene diagnostic"
    )
}

private func checkTruncatedEvidenceStaysVisibleAsPartial() throws {
    var envelope = minimalEnvelope(contextRevision: "revision-7")
    envelope.evidenceLedger[0].isTruncated = true
    let presentation = RichAnswerEngine.prepare(
        envelope: envelope,
        environment: RichAnswerEnvironment(
            contextRevision: "revision-7",
            allowedSourceLabels: ["[材料：样例]"]
        )
    )

    try richAnswerRequire(presentation.mode == .rich, "a grounded excerpt may render even when its source is truncated")
    try richAnswerRequire(presentation.evidenceState == .partial, "truncated source evidence is never reported as complete")
}

private func checkDefaultSceneBudgetIsBounded() throws {
    var envelope = minimalEnvelope(contextRevision: "revision-7")
    envelope.scenes = (0..<7).map { index in
        var scene = envelope.scenes[0]
        scene.id = "scene-\(index)"
        scene.objects[0].id = "claim-\(index)"
        scene.operations[0].targetIDs = ["claim-\(index)"]
        return scene
    }
    let presentation = RichAnswerEngine.prepare(
        envelope: envelope,
        environment: RichAnswerEnvironment(
            contextRevision: "revision-7",
            allowedSourceLabels: ["[材料：样例]"]
        )
    )

    try richAnswerRequire(presentation.scenes.count == 6, "the default host budget keeps at most six scenes")
    try richAnswerRequire(
        presentation.diagnostics.contains(where: { $0.code == .budgetExceeded }),
        "scene budget clipping remains inspectable"
    )
}

private func checkFamilySpecificContracts() throws {
    try assertFamilySceneRenders(validTextFamilyScene(), "text family accepts selectable text")
    var invalidText = validTextFamilyScene()
    invalidText.operations = []
    try assertFamilySceneRejected(invalidText, expectedCode: .invalidValue, "text family rejects unselectable text")

    try assertFamilySceneRenders(validQuantityFamilyScene(), "quantity family accepts coordinate samples")
    var invalidQuantity = validQuantityFamilyScene()
    invalidQuantity.objects.removeLast()
    invalidQuantity.frames[0].objectIDs = ["quantity-a"]
    invalidQuantity.operations[0].targetIDs = ["quantity-a"]
    try assertFamilySceneRejected(invalidQuantity, expectedCode: .invalidValue, "quantity family rejects single-point charts")

    try assertFamilySceneRenders(validProcessFamilyScene(), "process family accepts step and play controls")
    var invalidProcess = validProcessFamilyScene()
    invalidProcess.operations.removeAll { $0.kind == .playPause }
    try assertFamilySceneRejected(invalidProcess, expectedCode: .invalidValue, "process family rejects missing play controls")

    try assertFamilySceneRenders(validRelationFamilyScene(), "relation family accepts grounded relationships")
    var invalidRelation = validRelationFamilyScene()
    invalidRelation.relations = []
    invalidRelation.operations = []
    try assertFamilySceneRejected(invalidRelation, expectedCode: .invalidValue, "relation family rejects relation-free scenes")

    try assertFamilySceneRenders(validTimeSpaceFamilyScene(), "time-space family accepts scrubbed timeline")
    var invalidTimeSpace = validTimeSpaceFamilyScene()
    invalidTimeSpace.operations = []
    try assertFamilySceneRejected(invalidTimeSpace, expectedCode: .invalidValue, "time-space family rejects missing scrub controls")

    try assertFamilySceneRenders(validImageOverlayFamilyScene(), "image family accepts asset-backed regions")
    var invalidImage = validImageOverlayFamilyScene()
    invalidImage.objects.removeAll { $0.kind == .region }
    invalidImage.frames[0].objectIDs = ["image-object"]
    invalidImage.operations = [
        RichAnswerOperation(id: "image-zoom", kind: .zoom, label: "缩放原图", targetIDs: ["image-frame"], frameID: "image-frame"),
    ]
    try assertFamilySceneRejected(invalidImage, expectedCode: .invalidValue, "image family rejects overlays without regions")

    try assertFamilySceneRenders(validComparisonFamilyScene(), "comparison family accepts two compare targets")
    var invalidComparison = validComparisonFamilyScene()
    invalidComparison.operations[0].targetIDs = ["comparison-a"]
    try assertFamilySceneRejected(invalidComparison, expectedCode: .invalidValue, "comparison family rejects single-target compare")

    try assertFamilySceneRenders(validCalculationFamilyScene(), "calculation family accepts deterministic sampled adjust")
    var invalidCalculation = validCalculationFamilyScene()
    invalidCalculation.operations[0].targetIDs = ["calculation-zero"]
    try assertFamilySceneRejected(invalidCalculation, expectedCode: .invalidValue, "calculation family rejects under-sampled adjust")

    var unsupportedOperation = validQuantityFamilyScene()
    unsupportedOperation.operations.append(
        RichAnswerOperation(id: "quantity-sort", kind: .sort, label: "排序", targetIDs: ["quantity-a"])
    )
    try assertFamilySceneRejected(
        unsupportedOperation,
        expectedCode: .unsupportedField,
        "quantity family rejects operations that the renderer does not support"
    )
}

private func checkAcceptedInteractiveScene() throws {
    let envelope = RichAnswerEnvelope(
        contextRevision: "revision-7",
        narrative: "名义利率减去通胀率，可以近似理解为实际利率。",
        expressionPlan: RichAnswerExpressionPlan(
            action: .manipulate,
            summary: "让用户调节通胀率并观察实际利率变化",
            families: [.quantityAndCoordinates, .calculationAndConstraints],
            preferredSurface: .expanded,
            directManipulation: true
        ),
        scenes: [
            RichAnswerScene(
                id: "real-rate-lab",
                title: "名义利率与实际利率",
                family: .quantityAndCoordinates,
                objects: [
                    RichAnswerObject(
                        id: "nominal-rate",
                        kind: .quantity,
                        label: "名义利率",
                        number: 5,
                        unit: "%",
                        frameID: "rate-comparison",
                        coordinate: RichAnswerPoint(x: 0.20, y: 0.70)
                    ),
                    RichAnswerObject(
                        id: "inflation-rate",
                        kind: .quantity,
                        label: "通胀率",
                        number: 2,
                        unit: "%",
                        frameID: "rate-comparison",
                        coordinate: RichAnswerPoint(x: 0.50, y: 0.40)
                    ),
                    RichAnswerObject(
                        id: "real-rate",
                        kind: .formula,
                        label: "实际利率",
                        text: "名义利率 − 通胀率"
                    ),
                ],
                relations: [
                    RichAnswerRelation(
                        id: "inflation-reduces-real-rate",
                        kind: .transforms,
                        sourceID: "inflation-rate",
                        targetID: "real-rate",
                        label: "扣除"
                    ),
                ],
                operations: [
                    RichAnswerOperation(
                        id: "adjust-inflation",
                        kind: .adjust,
                        label: "调节通胀率",
                        targetIDs: ["inflation-rate", "real-rate"],
                        parameter: RichAnswerParameter(
                            id: "inflation",
                            label: "通胀率",
                            minimum: 0,
                            maximum: 10,
                            step: 0.5,
                            initialValue: 2,
                            unit: "%"
                        )
                    ),
                ],
                frames: [
                    RichAnswerFrame(
                        id: "rate-comparison",
                        kind: .cartesian,
                        title: "利率变化",
                        objectIDs: ["nominal-rate", "inflation-rate", "real-rate"],
                        xAxis: RichAnswerAxis(label: "通胀率", minimum: 0, maximum: 10, unit: "%"),
                        yAxis: RichAnswerAxis(label: "利率", minimum: -5, maximum: 10, unit: "%")
                    ),
                ],
                evidenceIDs: ["rates-definition"],
                placement: .expanded
            ),
        ],
        evidenceLedger: [
            RichAnswerEvidence(
                id: "rates-definition",
                sourceLabel: "[材料：利率课程]",
                excerpt: "实际利率扣除了通货膨胀后的购买力变化。"
            ),
        ],
        fallback: RichAnswerFallback(text: "实际利率需要扣除通胀影响。", reason: "富回答不可用时保留核心结论")
    )
    let environment = RichAnswerEnvironment(
        contextRevision: "revision-7",
        allowedSourceLabels: ["[材料：利率课程]"]
    )

    let presentation = RichAnswerEngine.prepare(envelope: envelope, environment: environment)

    try richAnswerRequire(presentation.mode == .rich, "a valid grounded scene stays rich")
    try richAnswerRequire(presentation.scenes.count == 1, "a valid scene survives validation")
    try richAnswerRequire(presentation.scenes[0].operations.count == 1, "direct manipulation survives validation")
    try richAnswerRequire(presentation.evidenceState == .complete, "complete evidence is reported as complete")

    let encoded = try JSONEncoder().encode(envelope)
    let decoded = RichAnswerEngine.prepare(data: encoded, fallbackText: "fallback", environment: environment)
    try richAnswerRequire(decoded == presentation, "the Pi JSON boundary preserves a valid presentation")
}

private func checkStaleEvidenceFallsBackToNarrative() throws {
    let envelope = minimalEnvelope(contextRevision: "old-revision")
    let presentation = RichAnswerEngine.prepare(
        envelope: envelope,
        environment: RichAnswerEnvironment(
            contextRevision: "current-revision",
            allowedSourceLabels: ["[材料：样例]"]
        )
    )

    try richAnswerRequire(presentation.mode == .narrativeOnly, "stale context cannot render a scene")
    try richAnswerRequire(presentation.scenes.isEmpty, "stale context removes all scenes")
    try richAnswerRequire(
        presentation.diagnostics.contains(where: { $0.code == .staleContext }),
        "stale context exposes a diagnostic"
    )
}

private func checkBrokenReferencesDropOnlyTheirScene() throws {
    var invalid = minimalEnvelope(contextRevision: "revision-7").scenes[0]
    invalid.id = "broken"
    invalid.relations = [
        RichAnswerRelation(
            id: "missing-target",
            kind: .supports,
            sourceID: "claim",
            targetID: "not-present"
        ),
    ]
    var envelope = minimalEnvelope(contextRevision: "revision-7")
    envelope.scenes.append(invalid)
    let presentation = RichAnswerEngine.prepare(
        envelope: envelope,
        environment: RichAnswerEnvironment(
            contextRevision: "revision-7",
            allowedSourceLabels: ["[材料：样例]"]
        )
    )

    try richAnswerRequire(presentation.mode == .rich, "one invalid scene does not erase a valid scene")
    try richAnswerRequire(presentation.scenes.map(\.id) == ["simple"], "only the broken scene is removed")
    try richAnswerRequire(
        presentation.diagnostics.contains(where: { $0.sceneID == "broken" && $0.code == .brokenReference }),
        "broken references expose a scene diagnostic"
    )
}

private func checkRawWebPayloadIsRejected() throws {
    let data = Data(
        #"{"schemaVersion":1,"contextRevision":"revision-7","narrative":"说明","expressionPlan":{"action":"explain","summary":"说明","families":["textAndAlignment"],"preferredSurface":"inline","directManipulation":false},"scenes":[],"evidenceLedger":[],"fallback":{"text":"安全回退","reason":"协议不支持网页"},"html":"<script>alert(1)</script>"}"#.utf8
    )
    let presentation = RichAnswerEngine.prepare(
        data: data,
        fallbackText: "文本回答",
        environment: RichAnswerEnvironment(contextRevision: "revision-7", allowedSourceLabels: [])
    )

    try richAnswerRequire(presentation.mode == .narrativeOnly, "raw web payloads never render")
    try richAnswerRequire(presentation.narrative == "文本回答", "decode failure uses the trusted text answer")
    try richAnswerRequire(
        presentation.diagnostics.contains(where: { $0.code == .unsupportedField }),
        "unsupported web fields expose a protocol diagnostic"
    )
}

private func minimalEnvelope(contextRevision: String) -> RichAnswerEnvelope {
    RichAnswerEnvelope(
        contextRevision: contextRevision,
        narrative: "这是一个有依据的简短说明。",
        expressionPlan: RichAnswerExpressionPlan(
            action: .explain,
            summary: "对齐原文和解释",
            families: [.textAndAlignment],
            preferredSurface: .inline,
            directManipulation: true
        ),
        scenes: [
            RichAnswerScene(
                id: "simple",
                title: "原文与解释",
                family: .textAndAlignment,
                objects: [
                    RichAnswerObject(id: "claim", kind: .text, label: "解释", text: "概念说明"),
                ],
                operations: [
                    RichAnswerOperation(id: "select-claim", kind: .select, label: "选择文本", targetIDs: ["claim"]),
                ],
                evidenceIDs: ["source-1"]
            ),
        ],
        evidenceLedger: [
            RichAnswerEvidence(id: "source-1", sourceLabel: "[材料：样例]", excerpt: "原文片段"),
        ],
        fallback: RichAnswerFallback(text: "概念说明", reason: "场景不可用")
    )
}

private func assertFamilySceneRenders(_ scene: RichAnswerScene, _ message: String) throws {
    let presentation = RichAnswerEngine.prepare(
        envelope: familyEnvelope(scene: scene),
        environment: familyEnvironment()
    )

    try richAnswerRequire(presentation.mode == .rich, message)
    try richAnswerRequire(presentation.scenes.map(\.id) == [scene.id], "\(message) and keeps the family scene")
}

private func assertFamilySceneRejected(
    _ scene: RichAnswerScene,
    expectedCode: RichAnswerDiagnosticCode,
    _ message: String
) throws {
    let presentation = RichAnswerEngine.prepare(
        envelope: familyEnvelope(scene: scene),
        environment: familyEnvironment()
    )

    try richAnswerRequire(presentation.mode == .narrativeOnly, message)
    try richAnswerRequire(
        presentation.diagnostics.contains(where: { $0.sceneID == scene.id && $0.code == expectedCode }),
        "\(message) with \(expectedCode.rawValue)"
    )
}

private func familyEnvelope(scene: RichAnswerScene) -> RichAnswerEnvelope {
    let hasOperations = !scene.operations.isEmpty
    return RichAnswerEnvelope(
        contextRevision: "revision-7",
        narrative: "这个场景有证据、对象和可降级文本。",
        expressionPlan: RichAnswerExpressionPlan(
            action: hasOperations ? .manipulate : .explain,
            summary: "校验 \(scene.family.rawValue) 的最小可渲染条件",
            families: [scene.family],
            preferredSurface: scene.placement,
            directManipulation: hasOperations
        ),
        scenes: [scene],
        evidenceLedger: [
            RichAnswerEvidence(
                id: "source-1",
                sourceLabel: "[材料：样例]",
                excerpt: "原文片段",
                assetIDs: ["asset-1"]
            ),
        ],
        fallback: RichAnswerFallback(text: "富回答不可用，保留文字解释。", reason: "协议样例被拒绝")
    )
}

private func familyEnvironment() -> RichAnswerEnvironment {
    RichAnswerEnvironment(
        contextRevision: "revision-7",
        allowedSourceLabels: ["[材料：样例]"],
        allowedAssetIDs: ["asset-1"]
    )
}

private func validTextFamilyScene() -> RichAnswerScene {
    RichAnswerScene(
        id: "family-text",
        title: "原文选择",
        family: .textAndAlignment,
        objects: [
            RichAnswerObject(id: "text-a", kind: .text, label: "关键原文", text: "实际利率扣除了通胀影响。", evidenceIDs: ["source-1"]),
        ],
        operations: [
            RichAnswerOperation(id: "text-select", kind: .select, label: "选择原文", targetIDs: ["text-a"]),
        ],
        evidenceIDs: ["source-1"]
    )
}

private func validQuantityFamilyScene() -> RichAnswerScene {
    RichAnswerScene(
        id: "family-quantity",
        title: "坐标样本",
        family: .quantityAndCoordinates,
        objects: [
            RichAnswerObject(
                id: "quantity-a",
                kind: .dataPoint,
                label: "低通胀样本",
                number: 3,
                unit: "%",
                evidenceIDs: ["source-1"],
                frameID: "quantity-frame",
                coordinate: RichAnswerPoint(x: 0.25, y: 0.70)
            ),
            RichAnswerObject(
                id: "quantity-b",
                kind: .dataPoint,
                label: "高通胀样本",
                number: 1,
                unit: "%",
                evidenceIDs: ["source-1"],
                frameID: "quantity-frame",
                coordinate: RichAnswerPoint(x: 0.75, y: 0.35)
            ),
        ],
        operations: [
            RichAnswerOperation(
                id: "quantity-adjust",
                kind: .adjust,
                label: "调节观察点",
                targetIDs: ["quantity-a", "quantity-b"],
                parameter: RichAnswerParameter(id: "quantity-probe", label: "观察位置", minimum: 0, maximum: 10, step: 1, initialValue: 5)
            ),
        ],
        frames: [
            RichAnswerFrame(
                id: "quantity-frame",
                kind: .cartesian,
                title: "通胀与实际利率",
                objectIDs: ["quantity-a", "quantity-b"],
                xAxis: RichAnswerAxis(label: "通胀率", minimum: 0, maximum: 10, unit: "%"),
                yAxis: RichAnswerAxis(label: "实际利率", minimum: -2, maximum: 6, unit: "%")
            ),
        ],
        evidenceIDs: ["source-1"]
    )
}

private func validProcessFamilyScene() -> RichAnswerScene {
    RichAnswerScene(
        id: "family-process",
        title: "推导过程",
        family: .processAndState,
        objects: [
            RichAnswerObject(id: "process-a", kind: .step, label: "读名义利率", text: "先确认合同报价。", evidenceIDs: ["source-1"]),
            RichAnswerObject(id: "process-b", kind: .state, label: "扣除通胀", text: "再切换到购买力口径。", evidenceIDs: ["source-1"]),
        ],
        relations: [
            RichAnswerRelation(id: "process-r", kind: .precedes, sourceID: "process-a", targetID: "process-b", evidenceIDs: ["source-1"]),
        ],
        operations: [
            RichAnswerOperation(id: "process-step", kind: .step, label: "逐步查看", targetIDs: ["process-a", "process-b"]),
            RichAnswerOperation(id: "process-play", kind: .playPause, label: "播放过程", targetIDs: ["process-a", "process-b"]),
        ],
        evidenceIDs: ["source-1"]
    )
}

private func validRelationFamilyScene() -> RichAnswerScene {
    RichAnswerScene(
        id: "family-relation",
        title: "依据关系",
        family: .relationAndEvidence,
        objects: [
            RichAnswerObject(id: "relation-a", kind: .claim, label: "名义利率", evidenceIDs: ["source-1"]),
            RichAnswerObject(id: "relation-b", kind: .claim, label: "实际利率", evidenceIDs: ["source-1"]),
        ],
        relations: [
            RichAnswerRelation(id: "relation-r", kind: .dependsOn, sourceID: "relation-b", targetID: "relation-a", label: "以名义利率为起点", evidenceIDs: ["source-1"]),
        ],
        operations: [
            RichAnswerOperation(id: "relation-reveal", kind: .reveal, label: "展开证据", targetIDs: ["relation-r"]),
        ],
        evidenceIDs: ["source-1"]
    )
}

private func validTimeSpaceFamilyScene() -> RichAnswerScene {
    RichAnswerScene(
        id: "family-time-space",
        title: "时间线观察",
        family: .timeAndSpace,
        objects: [
            RichAnswerObject(id: "time-a", kind: .event, label: "报价", text: "看到名义利率。", evidenceIDs: ["source-1"], frameID: "time-frame", coordinate: RichAnswerPoint(x: 0.15, y: 0.50)),
            RichAnswerObject(id: "time-b", kind: .event, label: "解释", text: "扣除通胀解释购买力。", evidenceIDs: ["source-1"], frameID: "time-frame", coordinate: RichAnswerPoint(x: 0.85, y: 0.50)),
        ],
        relations: [
            RichAnswerRelation(id: "time-r", kind: .precedes, sourceID: "time-a", targetID: "time-b", evidenceIDs: ["source-1"]),
        ],
        operations: [
            RichAnswerOperation(id: "time-scrub", kind: .scrub, label: "拖动时间尺", targetIDs: ["time-a", "time-b"]),
        ],
        frames: [
            RichAnswerFrame(id: "time-frame", kind: .timeline, title: "学习顺序", objectIDs: ["time-a", "time-b"], evidenceIDs: ["source-1"]),
        ],
        evidenceIDs: ["source-1"]
    )
}

private func validImageOverlayFamilyScene() -> RichAnswerScene {
    RichAnswerScene(
        id: "family-image",
        title: "图像叠层",
        family: .imageAndOverlay,
        objects: [
            RichAnswerObject(id: "image-object", kind: .image, label: "教材页面", evidenceIDs: ["source-1"], assetID: "asset-1", frameID: "image-frame"),
            RichAnswerObject(id: "image-region", kind: .region, label: "关键定义", text: "这块区域解释实际利率。", evidenceIDs: ["source-1"], frameID: "image-frame", bounds: RichAnswerRegion(x: 0.12, y: 0.20, width: 0.48, height: 0.18)),
        ],
        operations: [
            RichAnswerOperation(id: "image-select", kind: .select, label: "选择区域", targetIDs: ["image-region"], frameID: "image-frame"),
            RichAnswerOperation(id: "image-toggle", kind: .toggle, label: "开关叠层", targetIDs: ["image-region"], frameID: "image-frame"),
            RichAnswerOperation(id: "image-zoom", kind: .zoom, label: "缩放原图", targetIDs: ["image-frame"], frameID: "image-frame"),
        ],
        frames: [
            RichAnswerFrame(id: "image-frame", kind: .image, title: "教材页面", objectIDs: ["image-object", "image-region"], assetID: "asset-1", evidenceIDs: ["source-1"]),
        ],
        evidenceIDs: ["source-1"]
    )
}

private func validComparisonFamilyScene() -> RichAnswerScene {
    RichAnswerScene(
        id: "family-comparison",
        title: "概念比较",
        family: .comparisonAndEvaluation,
        objects: [
            RichAnswerObject(id: "comparison-a", kind: .option, label: "名义利率", text: "合同中先看到的报价。", evidenceIDs: ["source-1"]),
            RichAnswerObject(id: "comparison-b", kind: .option, label: "实际利率", text: "扣除通胀后的购买力口径。", evidenceIDs: ["source-1"]),
        ],
        relations: [
            RichAnswerRelation(id: "comparison-r", kind: .contrasts, sourceID: "comparison-a", targetID: "comparison-b", evidenceIDs: ["source-1"]),
        ],
        operations: [
            RichAnswerOperation(id: "comparison-compare", kind: .compare, label: "突出差异", targetIDs: ["comparison-a", "comparison-b"]),
        ],
        evidenceIDs: ["source-1"]
    )
}

private func validCalculationFamilyScene() -> RichAnswerScene {
    RichAnswerScene(
        id: "family-calculation",
        title: "确定性计算",
        family: .calculationAndConstraints,
        objects: [
            RichAnswerObject(id: "calculation-formula", kind: .formula, label: "公式", text: "实际利率 ≈ 名义利率 − 通胀率", evidenceIDs: ["source-1"]),
            RichAnswerObject(id: "calculation-constraint", kind: .constraint, label: "约束", text: "名义利率固定为 5%，通胀率可调。", evidenceIDs: ["source-1"]),
            RichAnswerObject(id: "calculation-zero", kind: .dataPoint, label: "通胀 0%", number: 5, unit: "%", evidenceIDs: ["source-1"], frameID: "calculation-frame", coordinate: RichAnswerPoint(x: 0, y: 0.90)),
            RichAnswerObject(id: "calculation-five", kind: .dataPoint, label: "通胀 5%", number: 0, unit: "%", evidenceIDs: ["source-1"], frameID: "calculation-frame", coordinate: RichAnswerPoint(x: 0.625, y: 0.35)),
        ],
        operations: [
            RichAnswerOperation(
                id: "calculation-adjust",
                kind: .adjust,
                label: "当前实际利率",
                targetIDs: ["calculation-zero", "calculation-five"],
                parameter: RichAnswerParameter(id: "inflation", label: "通胀率", minimum: 0, maximum: 8, step: 0.5, initialValue: 2, unit: "%"),
                frameID: "calculation-frame"
            ),
            RichAnswerOperation(id: "calculation-reset", kind: .reset, label: "恢复初值", targetIDs: ["calculation-formula", "calculation-constraint"]),
        ],
        frames: [
            RichAnswerFrame(
                id: "calculation-frame",
                kind: .cartesian,
                title: "实际利率样本",
                objectIDs: ["calculation-zero", "calculation-five"],
                xAxis: RichAnswerAxis(label: "通胀率", minimum: 0, maximum: 8, unit: "%"),
                yAxis: RichAnswerAxis(label: "实际利率", minimum: -2, maximum: 6, unit: "%")
            ),
        ],
        evidenceIDs: ["source-1"]
    )
}

private func richAnswerRequire(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw RichAnswerProtocolCheckError.failed(message) }
}

private enum RichAnswerProtocolCheckError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case let .failed(message):
            return message
        }
    }
}
