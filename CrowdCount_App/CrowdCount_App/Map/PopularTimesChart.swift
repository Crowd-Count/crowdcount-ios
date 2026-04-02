import SwiftUI
import Charts

struct PopularTimesData {
    let hourlyAveragesUTC: [String: Double]  // "0"-"23" -> avg count (UTC hours)
    let dayOfWeek: String                    // e.g. "Friday"
    let busynessLevel: Int?                  // 1-5 server-computed busyness level

    /// Shift UTC hour keys to local timezone hours
    var hourlyAverages: [String: Double] {
        let offsetSeconds = TimeZone.current.secondsFromGMT()
        let offsetHours = offsetSeconds / 3600
        var shifted: [String: Double] = [:]
        for (key, value) in hourlyAveragesUTC {
            guard let utcHour = Int(key) else { continue }
            let localHour = (utcHour + offsetHours + 24) % 24
            shifted[String(localHour)] = value
        }
        return shifted
    }
}

struct PopularTimesChart: View {
    let data: PopularTimesData
    let accentColor: Color
    let currentCount: Int
    let isClosed: Bool

    private let allHours = (0..<24).map { String($0) }
    private let labeledHours: Set<Int> = [0, 6, 9, 12, 15, 18, 21]

    private var currentHour: String {
        String(Calendar.current.component(.hour, from: Date()))
    }

    private var localDayOfWeek: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "EEEE"
        return formatter.string(from: Date())
    }

    private var localAverages: [String: Double] {
        data.hourlyAverages
    }

    private var peakValue: Double {
        let todayMax = localAverages.values.max() ?? 0
        return max(todayMax, Double(currentCount))
    }

    private var busynessLabel: (text: String, color: Color)? {
        guard !isClosed, let level = data.busynessLevel else { return nil }
        switch level {
        case 1: return ("Not busy", .secondary)
        case 2: return ("Less busy than usual", .secondary)
        case 3: return ("As busy as usual", .secondary)
        case 4: return ("Busy", .orange)
        case 5: return ("Very busy", .red)
        default: return nil
        }
    }

    private var hourComparisonLabel: (text: String, color: Color)? {
        guard !isClosed, currentCount > 0 else { return nil }
        guard let avgNow = localAverages[currentHour], avgNow > 0 else { return nil }
        let diff = Double(currentCount) - avgNow
        let pct = Int(abs(diff / avgNow) * 100)
        if pct < 10 { return ("About as expected right now", .secondary) }
        if diff > 0 { return ("\(pct)% more than expected right now", .secondary) }
        return ("\(pct)% less than expected right now", .secondary)
    }

    private var uses24HourClock: Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let timeString = formatter.string(from: Date())
        return !timeString.contains(formatter.amSymbol) && !timeString.contains(formatter.pmSymbol)
    }

    private func hourLabel(_ hour: Int) -> String {
        if uses24HourClock {
            return "\(hour)"
        }
        switch hour {
        case 0: return "12a"
        case 6: return "6a"
        case 9: return "9a"
        case 12: return "12p"
        case 15: return "3p"
        case 18: return "6p"
        case 21: return "9p"
        default: return ""
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Popular times")
                    .font(.subheadline.weight(.medium))
                Text(localDayOfWeek)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if let busyness = busynessLabel {
                HStack(spacing: 4) {
                    Circle()
                        .fill(busyness.color)
                        .frame(width: 6, height: 6)
                    Text(busyness.text)
                        .font(.caption)
                        .foregroundColor(busyness.color)
                }
            }

            if let hourComp = hourComparisonLabel {
                Text(hourComp.text)
                    .font(.caption)
                    .foregroundColor(hourComp.color)
            }

            Chart {
                ForEach(allHours, id: \.self) { hour in
                    let avgValue = localAverages[hour] ?? 0
                    let isCurrentHour = hour == currentHour && !isClosed && !data.dayOfWeek.isEmpty

                    if isCurrentHour && avgValue <= 0 {
                        // No usual data for this hour: just show accent bar
                        RectangleMark(
                            x: .value("Hour", hour),
                            yStart: .value("Start", 0),
                            yEnd: .value("End", Double(currentCount))
                        )
                        .foregroundStyle(accentColor)
                        .cornerRadius(3)
                    } else if isCurrentHour && Double(currentCount) > avgValue {
                        // Current > usual: accent bar behind, usual bar overlays on top
                        RectangleMark(
                            x: .value("Hour", hour),
                            yStart: .value("Start", 0),
                            yEnd: .value("End", Double(currentCount))
                        )
                        .foregroundStyle(accentColor.opacity(0.8))
                        .cornerRadius(3)

                        BarMark(
                            x: .value("Hour", hour),
                            y: .value("Count", avgValue)
                        )
                        .foregroundStyle(Color.secondary.opacity(0.65))
                        .cornerRadius(3)
                    } else if isCurrentHour {
                        // Current <= usual: usual bar behind (only if taller), accent bar on top
                        if avgValue > Double(currentCount) {
                            RectangleMark(
                                x: .value("Hour", hour),
                                yStart: .value("Start", 0),
                                yEnd: .value("End", avgValue)
                            )
                            .foregroundStyle(Color.secondary.opacity(0.3))
                            .cornerRadius(3)
                        }

                        RectangleMark(
                            x: .value("Hour", hour),
                            yStart: .value("Start", 0),
                            yEnd: .value("End", Double(currentCount))
                        )
                        .foregroundStyle(accentColor)
                        .cornerRadius(3)
                    } else {
                        BarMark(
                            x: .value("Hour", hour),
                            y: .value("Count", max(avgValue, 0))
                        )
                        .foregroundStyle(Color.secondary.opacity(0.3))
                        .cornerRadius(3)
                    }
                }
            }
            .chartXScale(domain: allHours)
            .chartXAxis {
                AxisMarks { value in
                    if let strValue = value.as(String.self),
                       let intValue = Int(strValue),
                       labeledHours.contains(intValue) {
                        AxisValueLabel {
                            Text(hourLabel(intValue))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .chartYAxis(.hidden)
            .chartYScale(domain: 0...max(peakValue, 10))
            .animation(.easeInOut(duration: 0.3), value: data.hourlyAveragesUTC)
            .frame(height: 120)

            // Legend
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 10, height: 10)
                    Text("Usual")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if !isClosed {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(accentColor)
                            .frame(width: 10, height: 10)
                        Text("Right now")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

#Preview("Popular Times - Busy Hour") {
    PopularTimesChart(
        data: PopularTimesData(
            hourlyAveragesUTC: [
                "6": 3.0, "7": 8.0, "8": 15.0, "9": 22.0, "10": 28.0, "11": 32.0,
                "12": 35.0, "13": 30.0, "14": 25.0, "15": 20.0, "16": 18.0,
                "17": 22.0, "18": 28.0, "19": 25.0, "20": 15.0, "21": 8.0, "22": 4.0
            ],
            dayOfWeek: "Friday",
            busynessLevel: 4
        ),
        accentColor: .blue,
        currentCount: 28,
        isClosed: false
    )
    .padding()
}

#Preview("Popular Times - Less Than Usual") {
    PopularTimesChart(
        data: PopularTimesData(
            hourlyAveragesUTC: [
                "0": 5.0, "1": 3.0, "2": 2.0, "3": 1.0, "4": 1.0, "5": 2.0,
                "6": 8.0, "7": 15.0, "8": 22.0, "9": 28.0, "10": 30.0, "11": 32.0,
                "12": 35.0, "13": 30.0, "14": 25.0, "15": 22.0, "16": 20.0,
                "17": 24.0, "18": 28.0, "19": 22.0, "20": 15.0, "21": 10.0, "22": 7.0, "23": 4.0
            ],
            dayOfWeek: "Tuesday",
            busynessLevel: 2
        ),
        accentColor: .orange,
        currentCount: 8,
        isClosed: false
    )
    .padding()
}

#Preview("Popular Times - In Card") {
    let sampleData = PopularTimesData(
        hourlyAveragesUTC: [
            "6": 3.0, "7": 8.0, "8": 15.0, "9": 22.0, "10": 28.0, "11": 32.0,
            "12": 35.0, "13": 30.0, "14": 25.0, "15": 20.0, "16": 18.0,
            "17": 22.0, "18": 28.0, "19": 25.0, "20": 15.0, "21": 8.0, "22": 4.0
        ],
        dayOfWeek: "Friday",
        busynessLevel: 4
    )

    VStack {
        Spacer()
        VStack(spacing: 16) {
            // Simulated card header
            HStack {
                Circle()
                    .fill(.red)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "flag.2.crossed.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                    )
                Text("CrowdCount HQ")
                    .font(.headline)
                Spacer()
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }

            // Simulated count row
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current count")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("42")
                            .font(.system(size: 48, weight: .bold))
                        Text("↑")
                            .font(.title)
                            .foregroundColor(.green)
                    }
                }
                Spacer()
                Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .foregroundColor(.white)
                    .background(Capsule().fill(.red))
            }

            // Popular times chart
            PopularTimesChart(data: sampleData, accentColor: .red, currentCount: 42, isClosed: false)
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 40)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: -4)
        )
    }
    .edgesIgnoringSafeArea(.bottom)
    .preferredColorScheme(.dark)
}
