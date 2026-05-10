import Foundation

public enum DateFormatters {
    public static let absolute: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    public static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    public static func relativeText(from timestamp: Double, reference: Date = Date()) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        return relative.localizedString(for: date, relativeTo: reference)
    }

    public static func absoluteText(from timestamp: Double) -> String {
        absolute.string(from: Date(timeIntervalSince1970: timestamp))
    }
}
