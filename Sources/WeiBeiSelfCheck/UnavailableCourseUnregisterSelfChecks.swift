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
    // 产品安全契约,不是普通锁字断言:卸载确认必须向用户担保「不移动、不删除」,
    // 且不得出现「废纸篓」字眼;修改此措辞须经产品评审(2026-08-25 测试审计定案)。
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
