import Foundation

extension Date {
    /// The format stores dates as ISO 8601 with second precision, which is all a blog post
    /// needs and keeps `post.json` readable. Dates are normalised on the way in so that a
    /// value round-trips through the file unchanged instead of losing a fraction of a second
    /// and making an untouched post look edited.
    var truncatedToSecond: Date {
        Date(timeIntervalSince1970: timeIntervalSince1970.rounded(.down))
    }
}
