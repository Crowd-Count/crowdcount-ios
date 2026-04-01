import Foundation

// MARK: - POS Provider

enum POSProvider: String {
    case square
    case toast
}

// MARK: - POS Connection Info

struct POSConnectionInfo {
    let connected: Bool
    let provider: POSProvider?
    let posLocationName: String?
    let posLocationId: String?
    let merchantId: String?
    let posAccountId: String?
    let connectedAt: String?

    static func from(_ json: [String: Any]) -> POSConnectionInfo {
        let providerStr = json["provider"] as? String
        return POSConnectionInfo(
            connected: json["connected"] as? Bool ?? false,
            provider: providerStr.flatMap { POSProvider(rawValue: $0) },
            posLocationName: json["pos_location_name"] as? String,
            posLocationId: json["pos_location_id"] as? String,
            merchantId: json["merchant_id"] as? String,
            posAccountId: json["pos_account_id"] as? String,
            connectedAt: json["connected_at"] as? String
        )
    }
}

// MARK: - POS Store Location

struct POSStoreLocation: Identifiable {
    let id: String
    let name: String
    let address: String?

    static func from(_ json: [String: Any]) -> POSStoreLocation {
        POSStoreLocation(
            id: json["id"] as? String ?? "",
            name: json["name"] as? String ?? "",
            address: json["address"] as? String
        )
    }
}

// MARK: - POS Transaction Data

struct POSTransactionData {
    let totalTransactions: Int
    let totalRevenue: Int // in cents
    let hourlyBreakdown: [String: POSHourlyEntry]
    let currency: String

    struct POSHourlyEntry {
        let transactions: Int
        let revenue: Int
    }

    static func from(_ json: [String: Any]) -> POSTransactionData {
        var hourly: [String: POSHourlyEntry] = [:]
        if let breakdown = json["hourly_breakdown"] as? [String: [String: Any]] {
            for (hour, entry) in breakdown {
                hourly[hour] = POSHourlyEntry(
                    transactions: entry["transactions"] as? Int ?? 0,
                    revenue: entry["revenue"] as? Int ?? 0
                )
            }
        }
        return POSTransactionData(
            totalTransactions: json["total_transactions"] as? Int ?? 0,
            totalRevenue: json["total_revenue"] as? Int ?? 0,
            hourlyBreakdown: hourly,
            currency: json["currency"] as? String ?? "USD"
        )
    }
}

// MARK: - POS Period Stats

struct POSPeriodStats {
    let transactions: Int
    let revenue: Int // in cents
    let currency: String
    let entries: Int
    let conversionRate: Double // percentage, capped at 100
    let revenuePerVisitor: Int // in cents
    let avgTransaction: Int // in cents
    let hourlyData: [String: POSTransactionData.POSHourlyEntry]?

    static func from(_ json: [String: Any]) -> POSPeriodStats {
        var hourly: [String: POSTransactionData.POSHourlyEntry]? = nil
        if let hourlyJson = json["hourly_data"] as? [String: [String: Any]] {
            var parsed: [String: POSTransactionData.POSHourlyEntry] = [:]
            for (hour, entry) in hourlyJson {
                parsed[hour] = POSTransactionData.POSHourlyEntry(
                    transactions: entry["transactions"] as? Int ?? 0,
                    revenue: entry["revenue"] as? Int ?? 0
                )
            }
            hourly = parsed
        }
        return POSPeriodStats(
            transactions: json["transactions"] as? Int ?? 0,
            revenue: json["revenue"] as? Int ?? 0,
            currency: json["currency"] as? String ?? "USD",
            entries: json["entries"] as? Int ?? 0,
            conversionRate: json["conversion_rate"] as? Double ?? 0,
            revenuePerVisitor: json["revenue_per_visitor"] as? Int ?? 0,
            avgTransaction: json["avg_transaction"] as? Int ?? 0,
            hourlyData: hourly
        )
    }
}

// MARK: - POS Insights Response

struct POSInsightsResponse {
    let today: POSPeriodStats
    let prevDay: POSPeriodStats
    let week: POSPeriodStats
    let prevWeek: POSPeriodStats
    let year: POSPeriodStats
    let prevYear: POSPeriodStats

    static func from(_ json: [String: Any]) -> POSInsightsResponse {
        POSInsightsResponse(
            today: POSPeriodStats.from(json["today"] as? [String: Any] ?? [:]),
            prevDay: POSPeriodStats.from(json["prev_day"] as? [String: Any] ?? [:]),
            week: POSPeriodStats.from(json["week"] as? [String: Any] ?? [:]),
            prevWeek: POSPeriodStats.from(json["prev_week"] as? [String: Any] ?? [:]),
            year: POSPeriodStats.from(json["year"] as? [String: Any] ?? [:]),
            prevYear: POSPeriodStats.from(json["prev_year"] as? [String: Any] ?? [:])
        )
    }
}

// MARK: - Formatting Helpers

enum POSFormatting {
    /// Format cents as dollars (e.g. 1250 → "$12.50")
    static func formatCurrency(_ cents: Int, currency: String = "USD") -> String {
        let dollars = Double(cents) / 100.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: dollars)) ?? "$\(String(format: "%.2f", dollars))"
    }

    /// Calculate percentage change between two values. Returns nil if previous is 0.
    static func trendPercentage(current: Int, previous: Int) -> Double? {
        guard previous > 0 else { return nil }
        return Double(current - previous) / Double(previous) * 100.0
    }
}
