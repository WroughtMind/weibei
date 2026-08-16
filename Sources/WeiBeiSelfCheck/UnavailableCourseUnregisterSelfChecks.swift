import Foundation
import WeiBeiCore

func checkUnavailableCourseUnregister() {
    expect(
        UnavailableCourseUnregister.shouldOfferUnregister(
            rootURL: nil,
            unavailableReason: nil
        ),
        "a missing course folder must offer unregister"
    )
    expect(
        UnavailableCourseUnregister.shouldOfferUnregister(
            rootURL: URL(fileURLWithPath: "/tmp/missing-course", isDirectory: true),
            unavailableReason: "bookmark failed"
        ),
        "an unavailable reason must offer unregister"
    )
    expect(
        !UnavailableCourseUnregister.shouldOfferUnregister(
            rootURL: URL(fileURLWithPath: "/tmp/present-course", isDirectory: true),
            unavailableReason: nil
        ),
        "an available course folder must not use the unregister-only entry"
    )

    let chinese = UnavailableCourseUnregister.confirmationMessage(chinese: true)
    let english = UnavailableCourseUnregister.confirmationMessage(chinese: false)
    expect(
        chinese.contains("不移动") && chinese.contains("不删除"),
        "Chinese confirmation must say files are not moved or deleted"
    )
    expect(
        english.lowercased().contains("does not move")
            && english.lowercased().contains("delete"),
        "English confirmation must say files are not moved or deleted"
    )
    expect(
        !chinese.contains("废纸篓") && !english.lowercased().contains("trash"),
        "unregister confirmation must not mention Trash"
    )
}
