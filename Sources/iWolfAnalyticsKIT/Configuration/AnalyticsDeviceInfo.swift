//
//  AnalyticsDeviceInfo.swift
//  iWolfAnalyticsKIT
//
//  Created by silenGSR on 21/11/2026.
//


import Foundation

#if os(iOS)
import UIKit
#endif

/// Collects technical information about the host application and device.
enum AnalyticsDeviceInfo {

    static let appVersion: String = {
        guard let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String else {
            return "unknown"
        }

        let normalized = version.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        return normalized.isEmpty ? "unknown" : normalized
    }()

    static let osVersion: String = {
        let version = ProcessInfo.processInfo.operatingSystemVersion

        let result = "\(version.majorVersion).\(version.minorVersion)"

        return version.patchVersion > 0
            ? "\(result).\(version.patchVersion)"
            : result
    }()

    static let deviceIdentifier: String? = {
        #if os(iOS)
        var systemInfo = utsname()
        uname(&systemInfo)

        return withUnsafeBytes(of: &systemInfo.machine) { bytes in
            let identifier = bytes.prefix {
                $0 != 0
            }

            return String(
                decoding: identifier,
                as: UTF8.self
            )
        }
        #elseif os(macOS)
        var size = 0

        guard sysctlbyname(
            "hw.model",
            nil,
            &size,
            nil,
            0
        ) == 0, size > 0 else {
            return nil
        }

        var buffer = [CChar](repeating: 0, count: size)

        guard sysctlbyname(
            "hw.model",
            &buffer,
            &size,
            nil,
            0
        ) == 0 else {
            return nil
        }

        return String(
            decoding: buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) },
            as: UTF8.self
        )
        #else
        return nil
        #endif
    }()

    static var country: String? {
        guard let country = Locale.current.region?.identifier.uppercased(),
              country.range(
                  of: "^[A-Z]{2}$",
                  options: .regularExpression
              ) != nil else {
            return nil
        }

        return country
    }
}
