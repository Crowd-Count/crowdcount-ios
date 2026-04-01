import SwiftUI

struct BarGraphYear: View {
    var yearData: [String: Double]
    var averageYearData: [String: Double]?
    var selectedYear: String

    // POS overlay
    var posYearData: [String: Int]? = nil
    var showPOSOverlay: Bool = false

    private let allMonths = ["January", "February", "March", "April", "May", "June",
                             "July", "August", "September", "October", "November", "December"]

    var body: some View {
        VStack {
            CombinedChartUIView(
                barData: yearData,
                averageData: averageYearData,
                labels: allMonths,
                displayLabels: allMonths.map { String($0.prefix(1)) },
                posData: posYearData,
                showPOS: showPOSOverlay
            )
            .frame(height: 200)
            .padding(.horizontal)

            LegendViewYear(
                selectedYear: selectedYear,
                showAverage: averageYearData != nil,
                showPOS: showPOSOverlay
            )
            .padding(.top, 20)
        }
        .padding([.top, .bottom])
    }
}

struct LegendViewYear: View {
    var selectedYear: String
    var showAverage: Bool
    var showPOS: Bool = false
    @State private var showAlert = false

    var body: some View {
        FlowLayout(spacing: 6) {
            legendItem(color: .blue, text: selectedYear)

            Button(action: { self.showAlert = true }) {
                legendItem(color: .orange, text: "Yearly Average", showInfo: true)
            }
            .alert(isPresented: $showAlert) {
                Alert(title: Text("Info for Yearly Average"),
                      message: Text("The average is calculated based on data from the same month over the previous 3 years, provided there is enough data.\n\nIf there isn't sufficient data, the average will not be displayed on the graph."),
                      dismissButton: .default(Text("OK")))
            }

            if showPOS {
                legendItem(color: .green, text: "Transactions", isDashed: true)
            }
        }
        .padding(.horizontal)
    }

    private func legendItem(color: Color, text: String, showInfo: Bool = false, isDashed: Bool = false) -> some View {
        HStack(spacing: 4) {
            if isDashed {
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(width: 14, height: 3)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
            }
            Text(text)
                .font(.caption)
                .foregroundColor(.primary)
            if showInfo {
                Image(systemName: "info.circle.fill")
                    .font(.caption2)
                    .foregroundColor(.primary)
            }
        }
    }
}

struct BarGraphYear_Previews: PreviewProvider {
    static var previews: some View {
        BarGraphYear(
            yearData: [
                "January": 45.2, "February": 42.8, "March": 48.1, "April": 52.3,
                "May": 55.7, "June": 58.9
            ],
            averageYearData: [
                "January": 43.0, "February": 41.5, "March": 46.8, "April": 50.2,
                "May": 53.4, "June": 56.7
            ],
            selectedYear: "2024"
        )
        .frame(height: 300)
    }
}
