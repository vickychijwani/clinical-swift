import Dependencies
import Foundation
import MessageUI
import UIKit

nonisolated struct AppointmentMessagingClient: Sendable {
    var canSendText: @MainActor @Sendable () -> Bool
    var copy: @MainActor @Sendable (_ message: String) -> Void
    var openWhatsApp: @MainActor @Sendable (_ phoneDigits: String, _ message: String) async -> Bool
}

nonisolated extension AppointmentMessagingClient: DependencyKey {
    nonisolated static let liveValue = Self(
        canSendText: {
            MFMessageComposeViewController.canSendText()
        },
        copy: { message in
            UIPasteboard.general.string = message
        },
        openWhatsApp: { phoneDigits, message in
            guard let url = whatsappURL(phoneDigits: phoneDigits, message: message)
            else {
                return false
            }

            return await UIApplication.shared.openAsync(url)
        }
    )

    nonisolated static let testValue = Self(
        canSendText: { false },
        copy: { _ in },
        openWhatsApp: { _, _ in false }
    )
}

extension DependencyValues {
    nonisolated var appointmentMessagingClient: AppointmentMessagingClient {
        get { self[AppointmentMessagingClient.self] }
        set { self[AppointmentMessagingClient.self] = newValue }
    }
}

private func whatsappURL(phoneDigits: String, message: String) -> URL? {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "wa.me"
    components.path = "/\(phoneDigits)"
    components.queryItems = [
        URLQueryItem(name: "text", value: message)
    ]
    return components.url
}

extension UIApplication {
    fileprivate func openAsync(_ url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            open(url, options: [:]) { didOpen in
                continuation.resume(returning: didOpen)
            }
        }
    }
}
