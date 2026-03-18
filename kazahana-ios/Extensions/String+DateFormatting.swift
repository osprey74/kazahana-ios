import Foundation

extension String {
    /// ISO8601形式の日付文字列を相対時刻表示に変換する ("1分前"、"2時間前" 等)
    var relativeFormatted: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: self) else {
            let fallback = ISO8601DateFormatter()
            guard let date2 = fallback.date(from: self) else { return self }
            return relativeString(from: date2)
        }
        return relativeString(from: date)
    }

    private func relativeString(from date: Date) -> String {
        let now = Date()
        let diff = now.timeIntervalSince(date)
        if diff < 60 {
            return "今"
        } else if diff < 3600 {
            let minutes = Int(diff / 60)
            return "\(minutes)分前"
        } else if diff < 86400 {
            let hours = Int(diff / 3600)
            return "\(hours)時間前"
        } else if diff < 86400 * 7 {
            let days = Int(diff / 86400)
            return "\(days)日前"
        } else {
            let cal = Calendar.current
            let comps = cal.dateComponents([.year, .month, .day], from: date)
            if let y = comps.year, let m = comps.month, let d = comps.day {
                return "\(y)/\(m)/\(d)"
            }
            return self
        }
    }
}
