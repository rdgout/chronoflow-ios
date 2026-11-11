import DesignSystem
import Foundation
import Testing

@testable import TripWizardUI

@Suite @MainActor struct WizardFlightRowLayoutTests {
    @Test func rowPlacesControlsAtTrailingEdgeAndCentersCaption() {
        let layout = WizardFlightRowLayout(spacing: PlanUITokens.space2, fillsWidth: true)
        let result = layout.arrangement(
            width: 360, sizes: [CGSize(width: 90, height: 40), CGSize(width: 200, height: 36)])
        #expect(result.size == CGSize(width: 360, height: 40))
        #expect(
            result.frames == [CGRect(x: 0, y: 0, width: 90, height: 40), CGRect(x: 160, y: 2, width: 200, height: 36)])
    }

    @Test func narrowRowStacksAndConstrainsLongCaption() {
        let layout = WizardFlightRowLayout(spacing: PlanUITokens.space2, fillsWidth: true)
        let result = layout.arrangement(
            width: 200, sizes: [CGSize(width: 250, height: 40), CGSize(width: 180, height: 36)],
            stackedSizes: [CGSize(width: 200, height: 60), CGSize(width: 180, height: 36)])
        #expect(result.size == CGSize(width: 200, height: 96 + PlanUITokens.space2))
        #expect(result.frames[0] == CGRect(x: 0, y: 0, width: 200, height: 60))
        #expect(result.frames[1] == CGRect(x: 0, y: 60 + PlanUITokens.space2, width: 180, height: 36))
    }

    @Test func controlWidthsCanCrossWrapBoundaryWithoutChangingChildOrder() {
        let layout = WizardFlightRowLayout(spacing: PlanUITokens.space2)
        let sizes = [CGSize(width: 140, height: 36), CGSize(width: 80, height: 36)]
        let boundary = sizes[0].width + sizes[1].width + PlanUITokens.space2
        let row = layout.arrangement(width: boundary, sizes: sizes)
        let column = layout.arrangement(width: boundary - 1, sizes: sizes)
        #expect(row.frames.map(\.size) == sizes)
        #expect(column.frames.map(\.size) == sizes)
        #expect(row.frames[1].minX == 140 + PlanUITokens.space2)
        #expect(column.frames[1].minY == 36 + PlanUITokens.space2)
        #expect(column.size.width == 140)
    }

    @Test func unspecifiedWidthUsesIdealHorizontalSize() {
        let result = WizardFlightRowLayout(spacing: PlanUITokens.space2).arrangement(
            width: nil, sizes: [CGSize(width: 100, height: 40), CGSize(width: 60, height: 32)])
        #expect(result.size == CGSize(width: 160 + PlanUITokens.space2, height: 40))
        #expect(result.frames[1].minY == 4)
    }
}
