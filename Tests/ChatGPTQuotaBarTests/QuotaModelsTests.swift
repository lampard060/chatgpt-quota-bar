import Foundation
import Testing
@testable import ChatGPTQuotaBar

@Test func parsesRemainingPercentAndResetCredits() throws {
    let response: [String: Any] = [
        "id": 2,
        "result": [
            "rateLimits": [
                "planType": "plus",
                "primary": [
                    "usedPercent": 35,
                    "resetsAt": 1_788_065_409,
                    "windowDurationMins": 300,
                ],
                "secondary": [
                    "usedPercent": 6,
                    "resetsAt": 1_788_652_209,
                    "windowDurationMins": 10_080,
                ],
                "credits": [
                    "balance": "0",
                    "hasCredits": false,
                    "unlimited": false,
                ],
            ],
            "rateLimitResetCredits": ["availableCount": 1],
        ],
    ]

    let snapshot = try QuotaSnapshot.parseRPCResponse(response)
    #expect(snapshot.planType == "plus")
    #expect(snapshot.primary?.remainingPercent == 65)
    #expect(snapshot.secondary?.remainingPercent == 94)
    #expect(snapshot.primary?.durationMinutes == 300)
    #expect(snapshot.credits?.balance == "0")
    #expect(snapshot.resetCreditCount == 1)
}

@Test func parsesResetCreditExpiry() throws {
    let response: [String: Any] = [
        "id": 2,
        "result": [
            "rateLimits": [
                "credits": ["hasCredits": false, "unlimited": false],
            ],
            "rateLimitResetCredits": [
                "availableCount": 1,
                "credits": [[
                    "status": "available",
                    "title": "Full reset",
                    "expiresAt": 1_789_944_845,
                ]],
            ],
        ],
    ]

    let snapshot = try QuotaSnapshot.parseRPCResponse(response)
    #expect(snapshot.resetCredits.count == 1)
    #expect(snapshot.resetCredits.first?.status == "available")
    #expect(snapshot.resetCredits.first?.expiresAt?.timeIntervalSince1970 == 1_789_944_845)
}

@Test func clampsRemainingPercent() {
    #expect(QuotaWindow(dictionary: ["usedPercent": -5])?.remainingPercent == 100)
    #expect(QuotaWindow(dictionary: ["usedPercent": 140])?.remainingPercent == 0)
}

@Test func parsesNumericCreditBalance() {
    let credits = CreditsSnapshot(dictionary: [
        "balance": 250,
        "hasCredits": true,
        "unlimited": false,
    ])

    #expect(credits?.balance == "250")
}

@Test func formatsCompactResetTimeAndDate() throws {
    let timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
    let primaryReset = try #require(ISO8601DateFormatter().date(from: "2026-08-30T04:50:00Z"))
    let secondaryReset = try #require(ISO8601DateFormatter().date(from: "2026-09-06T01:30:00Z"))
    let snapshot = QuotaSnapshot(
        planType: "plus",
        primary: QuotaWindow(dictionary: [
            "usedPercent": 35,
            "resetsAt": Int(primaryReset.timeIntervalSince1970),
        ]),
        secondary: QuotaWindow(dictionary: [
            "usedPercent": 6,
            "resetsAt": Int(secondaryReset.timeIntervalSince1970),
        ]),
        credits: nil,
        resetCreditCount: 1,
        resetCredits: []
    )

    let title = QuotaStatusFormatter(timeZone: timeZone).title(for: snapshot)
    #expect(title == "5h 65% ↻12:50 · 周 94% ↻9/6")
}
