import Testing
import CoreGraphics
@testable import Vidrio

struct GridLayoutTests {
    private let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test func testSinglePaneFillsBounds() {
        let layout = GridLayout.compute(count: 1, focusedIndex: 0, bounds: bounds, spacing: 8)
        #expect(layout.frames.count == 1)
        #expect(abs(layout.frames[0].width - (bounds.width - 16)) < 0.5)
        #expect(abs(layout.frames[0].height - (bounds.height - 16)) < 0.5)
    }

    @Test func testGridDimensionsAreAsSquareAsPossible() {
        // 4 panes -> 2x2, 5 -> 3 cols x 2 rows (ceil(sqrt(5)) = 3), 9 -> 3x3.
        #expect(GridLayout.compute(count: 4, focusedIndex: 0, bounds: bounds).indexAt.count == 2)
        #expect(GridLayout.compute(count: 4, focusedIndex: 0, bounds: bounds).indexAt[0].count == 2)

        let five = GridLayout.compute(count: 5, focusedIndex: 0, bounds: bounds)
        #expect(five.indexAt.count == 2)
        #expect(five.indexAt[0].count == 3)
        #expect(five.indexAt[1].count == 2) // ragged last row

        let nine = GridLayout.compute(count: 9, focusedIndex: 0, bounds: bounds)
        #expect(nine.indexAt.count == 3)
        #expect(nine.indexAt.allSatisfy { $0.count == 3 })
    }

    @Test func testEveryPaneGetsExactlyOneFrame() {
        let layout = GridLayout.compute(count: 7, focusedIndex: 3, bounds: bounds)
        #expect(layout.frames.count == 7)
        #expect(layout.frames.allSatisfy { $0.width > 0 && $0.height > 0 })
    }

    @Test func testFocusedPaneIsStrictlyLargerThanAnUnfocusedOne() {
        let layout = GridLayout.compute(count: 4, focusedIndex: 0, bounds: bounds, spacing: 8, focusWeight: 1.7)
        let focused = layout.frames[0]
        // Index 3 sits in a different row and column from index 0 in a 2x2
        // grid, so it never inherits the focused row/column's extra weight.
        let opposite = layout.frames[3]
        #expect(focused.width > opposite.width)
        #expect(focused.height > opposite.height)
    }

    @Test func testFramesTileTheFullBoundsWithNoOverlapGaps() {
        // Sum of row heights (plus inter-row spacing) should reconstruct the
        // full available height, for both a square and a ragged grid.
        for count in [1, 2, 3, 4, 5, 6, 7, 8, 9] {
            let layout = GridLayout.compute(count: count, focusedIndex: count / 2, bounds: bounds, spacing: 8)
            let totalHeight = layout.indexAt.reduce(0.0) { sum, row in
                sum + layout.frames[row[0]].height
            } + 8 * CGFloat(layout.indexAt.count + 1)
            #expect(abs(totalHeight - bounds.height) < 0.5, "count \(count) height mismatch")
        }
    }

    @Test func testAdjacencyNavigationInSquareGrid() {
        // 2x2 grid: [0 1]
        //           [2 3]
        let layout = GridLayout.compute(count: 4, focusedIndex: 0, bounds: bounds)
        #expect(GridLayout.move(from: 0, direction: .right, layout: layout) == 1)
        #expect(GridLayout.move(from: 0, direction: .down, layout: layout) == 2)
        #expect(GridLayout.move(from: 3, direction: .up, layout: layout) == 1)
        #expect(GridLayout.move(from: 3, direction: .left, layout: layout) == 2)
    }

    @Test func testNavigationClampsAtEdges() {
        let layout = GridLayout.compute(count: 4, focusedIndex: 0, bounds: bounds)
        #expect(GridLayout.move(from: 0, direction: .up, layout: layout) == 0)
        #expect(GridLayout.move(from: 0, direction: .left, layout: layout) == 0)
        #expect(GridLayout.move(from: 3, direction: .down, layout: layout) == 3)
        #expect(GridLayout.move(from: 3, direction: .right, layout: layout) == 3)
    }

    @Test func testNavigationIntoRaggedRowClampsColumn() {
        // 5 panes: [0 1 2]
        //          [3 4]
        // Moving down from column 2 (index 2) should land on the last
        // column that actually exists in the short row (index 4).
        let layout = GridLayout.compute(count: 5, focusedIndex: 2, bounds: bounds)
        #expect(GridLayout.move(from: 2, direction: .down, layout: layout) == 4)
    }

    @Test func testEmptyGridIsSafe() {
        let layout = GridLayout.compute(count: 0, focusedIndex: 0, bounds: bounds)
        #expect(layout.frames.isEmpty)
        #expect(GridLayout.move(from: 0, direction: .up, layout: layout) == 0)
    }
}
