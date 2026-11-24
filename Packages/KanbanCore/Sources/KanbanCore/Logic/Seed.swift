import Foundation

/// Written on first launch only.
public enum Seed {
    public static func file(now: Date) -> BoardFile {
        let brochure = TaskCard(
            title: "Complete SIP brochure",
            nextStep: "Alumni page still pending (rest is done)",
            category: "Brochure",
            priority: .high,
            column: .inProgress,
            sortIndex: 1,
            createdAt: now
        )
        let infographic = TaskCard(
            title: "Post infographic on LinkedIn",
            nextStep: "Design + caption, then post",
            category: "LinkedIn",
            priority: .medium,
            column: .todo,
            sortIndex: 1,
            createdAt: now
        )
        let recruiters = TaskCard(
            title: "Recruiter calling — past recruiters' HRs",
            nextStep: "Invite HRs of past-year recruiters to campus for summer internships",
            category: "Recruiter outreach",
            priority: .high,
            column: .todo,
            sortIndex: 2,
            startDate: CalendarDay(year: 2026, month: 10, day: 12),
            createdAt: now
        )
        return BoardFile(cards: [brochure, infographic, recruiters])
    }
}
