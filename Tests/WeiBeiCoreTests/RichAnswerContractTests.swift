import XCTest
@testable import WeiBeiCore

final class RichAnswerContractTests: XCTestCase {
    /**
     * Verifies the runtime registry publishes every stable renderer exactly once.
     */
    func testDefaultRegistryPublishesStableRendererSet() {
        let declarations = RichAnswerRendererRegistry.defaultRegistry().declarations

        XCTAssertEqual(
            Set(declarations.map(\.renderer)),
            [
                RichAnswerRendererRegistry.openUIProgramRenderer,
                RichAnswerRendererRegistry.openUICompositionRenderer,
                RichAnswerRendererRegistry.standardChartRenderer,
                RichAnswerRendererRegistry.mathFunctionRenderer,
                RichAnswerRendererRegistry.geometry2DRenderer,
                RichAnswerRendererRegistry.scene3DRenderer,
                RichAnswerRendererRegistry.spatialMapRenderer,
                RichAnswerRendererRegistry.imageOverlayRenderer,
            ]
        )
        XCTAssertEqual(declarations.count, Set(declarations.map(\.renderer)).count)
        XCTAssertTrue(
            declarations.allSatisfy {
                $0.specVersions.contains($0.preferredSpecVersion)
                    && !$0.fallbackModes.isEmpty
                    && !$0.limits.allowNetwork
            }
        )
    }

    /**
     * Verifies registration rejects empty, inconsistent, and duplicate renderer declarations.
     */
    func testRegistryRejectsInvalidRegistrations() throws {
        var emptyIdentifier = RichAnswerRendererRegistry.openUIProgramDeclaration()
        emptyIdentifier.renderer = "  "
        XCTAssertThrowsError(
            try RichAnswerRendererRegistry(
                registrations: [RichAnswerRendererRegistration(declaration: emptyIdentifier)]
            )
        ) { error in
            XCTAssertEqual(error as? RichAnswerRendererRegistryError, .emptyRendererIdentifier)
        }

        var missingPreferred = RichAnswerRendererRegistry.openUIProgramDeclaration()
        missingPreferred.preferredSpecVersion = "unsupported"
        XCTAssertThrowsError(
            try RichAnswerRendererRegistry(
                registrations: [RichAnswerRendererRegistration(declaration: missingPreferred)]
            )
        ) { error in
            XCTAssertEqual(
                error as? RichAnswerRendererRegistryError,
                .missingPreferredSpecVersion(RichAnswerRendererRegistry.openUIProgramRenderer)
            )
        }

        let registration = RichAnswerRendererRegistration(
            declaration: RichAnswerRendererRegistry.openUIProgramDeclaration()
        )
        XCTAssertThrowsError(
            try RichAnswerRendererRegistry(registrations: [registration, registration])
        ) { error in
            XCTAssertEqual(
                error as? RichAnswerRendererRegistryError,
                .duplicateRenderer(RichAnswerRendererRegistry.openUIProgramRenderer)
            )
        }
    }

    /**
     * Verifies negotiation refuses unknown renderers and plans without evidence bindings.
     */
    func testNegotiationRequiresRegisteredRendererAndSourceBinding() {
        let fallback = RichAnswerRenderFallback(
            mode: .narrativeOnly,
            reason: "Renderer unavailable",
            text: "Evidence-backed fallback"
        )
        let unknownPlan = RichAnswerRenderPlan(
            renderer: "weibei.unknown",
            specVersion: "v1",
            spec: RichAnswerRenderSpec(),
            sourceBindings: [
                RichAnswerRenderSourceBinding(
                    id: "source",
                    evidenceID: "evidence-1",
                    target: "root",
                    role: "basis"
                ),
            ],
            fallback: fallback
        )
        let registry = RichAnswerRendererRegistry.defaultRegistry()

        let unknown = registry.negotiate(plan: unknownPlan)

        XCTAssertEqual(unknown.status, .capabilityMismatch)
        XCTAssertEqual(unknown.mismatch?.issues.first?.code, .unknownRenderer)

        let ungrounded = RichAnswerRenderPlan(
            renderer: RichAnswerRendererRegistry.openUIProgramRenderer,
            specVersion: "weibei.openui.v1",
            spec: RichAnswerRenderSpec(
                fields: [
                    "adapter": .string("legacy_t1_program"),
                    "componentFamilies": .array([.string("FunctionPlot")]),
                    "sceneID": .string("function"),
                ]
            ),
            fallback: fallback
        )
        let result = registry.negotiate(plan: ungrounded)
        XCTAssertEqual(result.status, .capabilityMismatch)
        XCTAssertTrue(result.mismatch?.issues.contains(where: { $0.code == .missingSourceBinding }) == true)
    }

    /**
     * Verifies representative compatibility plans remain accepted and mismatches remain diagnostic.
     */
    func testCompatibilityRegistryBehaviorReportPasses() {
        let report = RichAnswerRendererRegistrySelfCheck.run()

        XCTAssertTrue(report.passed, report.diagnostics.joined(separator: "\n"))
    }
}
