import SwiftUI
import DGCharts

/// A UIViewRepresentable wrapper around DGCharts' CombinedChartView.
struct CombinedChartUIView: UIViewRepresentable {
    let barData: [String: Double]
    let averageData: [String: Double]?
    let labels: [String]
    var displayLabels: [String]? = nil
    let posData: [String: Int]?
    let showPOS: Bool
    var highlightIndex: Int? = nil

    @Environment(\.colorScheme) var colorScheme

    func makeUIView(context: Context) -> CombinedChartView {
        let chartView = CombinedChartView()
        chartView.noDataText = "No data"
        chartView.legend.enabled = false
        chartView.doubleTapToZoomEnabled = false
        chartView.pinchZoomEnabled = false
        chartView.scaleXEnabled = false
        chartView.scaleYEnabled = false
        chartView.highlightPerTapEnabled = false
        chartView.highlightPerDragEnabled = false
        chartView.drawOrder = [
            CombinedChartView.DrawOrder.bar.rawValue,
            CombinedChartView.DrawOrder.line.rawValue
        ]
        configureChart(chartView)
        return chartView
    }

    func updateUIView(_ chartView: CombinedChartView, context: Context) {
        configureChart(chartView)
    }

    private func configureChart(_ chartView: CombinedChartView) {
        let isDark = colorScheme == .dark
        let textColor = isDark ? UIColor.white : UIColor.black
        let gridColor = UIColor.gray.withAlphaComponent(0.3)
        let hasAverage = averageData != nil && averageData!.values.contains(where: { $0 > 0 })
        let hasPOSData = showPOS && posData?.values.contains(where: { $0 > 0 }) == true

        // X-Axis
        let xAxis = chartView.xAxis
        xAxis.labelPosition = .bottom
        xAxis.drawGridLinesEnabled = false
        xAxis.labelTextColor = textColor
        xAxis.labelFont = .systemFont(ofSize: 10)
        xAxis.granularity = 1
        xAxis.valueFormatter = IndexAxisValueFormatter(values: displayLabels ?? labels)
        xAxis.labelCount = min(labels.count, 12)

        // Left Y-Axis
        let leftAxis = chartView.leftAxis
        leftAxis.labelTextColor = textColor
        leftAxis.labelFont = .systemFont(ofSize: 10)
        leftAxis.gridColor = gridColor
        leftAxis.axisMinimum = 0
        leftAxis.granularity = 1
        leftAxis.drawZeroLineEnabled = false

        // Right Y-Axis
        let rightAxis = chartView.rightAxis
        if hasPOSData {
            rightAxis.enabled = true
            rightAxis.labelTextColor = UIColor.systemGreen
            rightAxis.labelFont = .systemFont(ofSize: 10)
            rightAxis.drawGridLinesEnabled = false
            rightAxis.axisMinimum = 0
            rightAxis.granularity = 1
            rightAxis.drawZeroLineEnabled = false
        } else {
            rightAxis.enabled = false
        }

        // --- Build Combined Data ---
        let combinedData = CombinedChartData()

        // Bar entries
        var barDataSets: [BarChartDataSet] = []

        var currentEntries: [BarChartDataEntry] = []
        var barColors: [UIColor] = []
        for (i, label) in labels.enumerated() {
            let val = barData[label] ?? 0
            let rounded = val.rounded() < 1 ? 0 : val.rounded()
            currentEntries.append(BarChartDataEntry(x: Double(i), y: rounded))
            if let hi = highlightIndex, i == hi {
                barColors.append(.systemGreen)
            } else {
                barColors.append(.systemBlue.withAlphaComponent(i % 2 == 0 ? 1.0 : 0.85))
            }
        }
        let currentSet = BarChartDataSet(entries: currentEntries, label: "Data")
        currentSet.colors = barColors
        currentSet.drawValuesEnabled = false
        barDataSets.append(currentSet)

        if hasAverage, let avg = averageData {
            var avgEntries: [BarChartDataEntry] = []
            var avgColors: [UIColor] = []
            for (i, label) in labels.enumerated() {
                let val = avg[label] ?? 0
                let rounded = val.rounded() < 1 ? 0 : val.rounded()
                avgEntries.append(BarChartDataEntry(x: Double(i), y: rounded))
                avgColors.append(.systemOrange.withAlphaComponent(i % 2 == 0 ? 0.85 : 0.7))
            }
            let avgSet = BarChartDataSet(entries: avgEntries, label: "Average")
            avgSet.colors = avgColors
            avgSet.drawValuesEnabled = false
            barDataSets.append(avgSet)
        }

        let barChartData = BarChartData(dataSets: barDataSets)
        let isManyBars = labels.count > 12
        let n = Double(labels.count)
        if hasAverage && barDataSets.count > 1 {
            let groupSpace = isManyBars ? 0.2 : 0.1
            let barSpace = 0.02
            let barWidth = isManyBars ? 0.38 : 0.43
            barChartData.barWidth = barWidth
            barChartData.groupBars(fromX: 0, groupSpace: groupSpace, barSpace: barSpace)
            xAxis.centerAxisLabelsEnabled = true
            xAxis.axisMinimum = 0
            xAxis.axisMaximum = barChartData.groupWidth(groupSpace: groupSpace, barSpace: barSpace) * n
        } else {
            barChartData.barWidth = isManyBars ? 0.4 : 0.6
            xAxis.centerAxisLabelsEnabled = false
            xAxis.axisMinimum = -0.5
            xAxis.axisMaximum = n - 0.5
        }
        combinedData.barData = barChartData

        // Line entries (POS)
        if hasPOSData, let pos = posData {
            var lineEntries: [ChartDataEntry] = []
            for (i, label) in labels.enumerated() {
                let txCount = pos[label] ?? 0
                lineEntries.append(ChartDataEntry(x: Double(i), y: Double(txCount)))
            }

            let lineSet = LineChartDataSet(entries: lineEntries, label: "Transactions")
            lineSet.axisDependency = .right
            lineSet.setColor(.systemGreen)
            lineSet.lineWidth = 2.5
            lineSet.mode = .horizontalBezier
            lineSet.drawCirclesEnabled = false
            lineSet.drawValuesEnabled = false
            lineSet.drawFilledEnabled = false

            combinedData.lineData = LineChartData(dataSet: lineSet)
        }

        chartView.data = combinedData

        // Apply rounded bar renderer AFTER data is set so sub-renderers exist
        let roundedRenderer = RoundedBarCombinedRenderer(
            chart: chartView,
            animator: chartView.chartAnimator,
            viewPortHandler: chartView.viewPortHandler
        )
        chartView.renderer = roundedRenderer
        chartView.notifyDataSetChanged()
    }
}

// MARK: - Rounded Bar Renderer

class RoundedBarCombinedRenderer: CombinedChartRenderer {
    override init(chart: CombinedChartView, animator: Animator, viewPortHandler: ViewPortHandler) {
        super.init(chart: chart, animator: animator, viewPortHandler: viewPortHandler)
        for (i, renderer) in subRenderers.enumerated() {
            if renderer is BarChartRenderer {
                subRenderers[i] = RoundedBarRenderer(
                    dataProvider: chart,
                    animator: animator,
                    viewPortHandler: viewPortHandler
                )
            }
        }
    }
}

class RoundedBarRenderer: BarChartRenderer {
    private let radius: CGFloat = 3.5

    override func drawDataSet(context: CGContext, dataSet: BarChartDataSetProtocol, index: Int) {
        guard let dataProvider = dataProvider,
              let barData = dataProvider.barData else { return }

        let trans = dataProvider.getTransformer(forAxis: dataSet.axisDependency)
        let phaseY = animator.phaseY
        let barWidth = barData.barWidth

        for i in 0..<dataSet.entryCount {
            guard let entry = dataSet.entryForIndex(i) as? BarChartDataEntry else { continue }

            let y = entry.y * phaseY
            if y == 0 { continue }

            let x = entry.x
            let halfW = barWidth / 2.0

            var pts = [
                CGPoint(x: x - halfW, y: 0),
                CGPoint(x: x + halfW, y: y)
            ]
            trans.pointValuesToPixel(&pts)

            let left = min(pts[0].x, pts[1].x)
            let right = max(pts[0].x, pts[1].x)
            let top = min(pts[0].y, pts[1].y)
            let bottom = max(pts[0].y, pts[1].y)

            let barRect = CGRect(x: left, y: top, width: right - left, height: bottom - top)

            guard viewPortHandler.isInBoundsLeft(barRect.maxX) else { continue }
            guard viewPortHandler.isInBoundsRight(barRect.minX) else { continue }

            // Safe color access
            let colorIndex = i % max(1, dataSet.colors.count)
            context.setFillColor(dataSet.colors[colorIndex].cgColor)

            let r = min(radius, barRect.width / 2, max(0, barRect.height))
            let path = UIBezierPath(
                roundedRect: barRect,
                byRoundingCorners: [.topLeft, .topRight],
                cornerRadii: CGSize(width: r, height: r)
            )
            context.addPath(path.cgPath)
            context.fillPath()
        }
    }
}
