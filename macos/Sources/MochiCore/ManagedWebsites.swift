import Foundation

/// A kind of 网站数据, as 管理网站和数据… names it (#106). WebKit has more data types than this;
/// the platform folds each into one of these. Declared in display order.
public enum WebsiteDataKind: String, CaseIterable, Sendable {
    case cookies
    case localStorage
    case databases
    case cache
    case serviceWorkers
    case other

    public var displayName: String {
        switch self {
        case .cookies: "Cookie"
        case .localStorage: "本地存储"
        case .databases: "数据库"
        case .cache: "缓存"
        case .serviceWorkers: "Service Worker"
        case .other: "其他数据"
        }
    }
}

/// One of WebKit's website data records: everything stored under a registrable domain
/// (`displayName` is `google.com` for `meet.google.com`'s data), and the only unit it deletes by.
public struct WebsiteDataRecord: Equatable, Sendable {
    public var displayName: String
    public var kinds: Set<WebsiteDataKind>

    public init(displayName: String, kinds: Set<WebsiteDataKind>) {
        self.displayName = displayName
        self.kinds = kinds
    }
}

/// One host's 网页权限 exceptions; `nil` where the host has none for that permission.
public struct WebsiteHostExceptions: Equatable, Sendable {
    public var host: String
    public var camera: WidgetConfig.MediaCapturePermission?
    public var microphone: WidgetConfig.MediaCapturePermission?

    public init(host: String, camera: WidgetConfig.MediaCapturePermission?, microphone: WidgetConfig.MediaCapturePermission?) {
        self.host = host
        self.camera = camera
        self.microphone = microphone
    }
}

/// A row of 管理网站和数据…: a website data record and the exceptions of the hosts under it, or a
/// host with exceptions that no record covers.
public struct ManagedWebsite: Equatable, Identifiable, Sendable {
    /// The record's display name, or the host itself when no record covers it.
    public var domain: String
    /// What the record holds, in `WebsiteDataKind` order — `nil` without a record.
    public var dataKinds: [WebsiteDataKind]?
    /// Sorted by host.
    public var exceptions: [WebsiteHostExceptions]

    public init(domain: String, dataKinds: [WebsiteDataKind]?, exceptions: [WebsiteHostExceptions]) {
        self.domain = domain
        self.dataKinds = dataKinds
        self.exceptions = exceptions
    }

    public var id: String { domain }
    public var hasData: Bool { dataKinds != nil }
}

public enum ManagedWebsites {
    /// Merges `records` with `config`'s 网页权限 exceptions (ADR-0027): a host goes under the record
    /// it equals or ends with as `.` + the record's name — the longest such, should two match — and
    /// a host no record covers is a website of its own. No public suffix list: WebKit's records
    /// already are registrable domains, so `notgoogle.com` never lands under `google.com`.
    public static func grouping(_ records: [WebsiteDataRecord], exceptionsIn config: WidgetConfig) -> [ManagedWebsite] {
        var websites: [String: ManagedWebsite] = [:]
        for record in records {
            let domain = record.displayName.lowercased()
            let kinds = WebsiteDataKind.allCases.filter { record.kinds.contains($0) }
            websites[domain] = ManagedWebsite(domain: domain, dataKinds: kinds, exceptions: [])
        }
        let recordDomains = websites.keys.sorted { $0.count > $1.count }
        for exceptions in hostExceptions(in: config) {
            let host = exceptions.host
            let domain = recordDomains.first { host == $0 || host.hasSuffix("." + $0) } ?? host
            websites[domain, default: ManagedWebsite(domain: domain, dataKinds: nil, exceptions: [])]
                .exceptions.append(exceptions)
        }
        return websites.values.sorted { $0.domain < $1.domain }
    }

    /// 搜索: websites whose domain or any exception host contains `query`, ignoring case; a blank
    /// query keeps them all.
    public static func filtered(_ websites: [ManagedWebsite], matching query: String) -> [ManagedWebsite] {
        let query = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return websites }
        return websites.filter { website in
            website.domain.contains(query) || website.exceptions.contains { $0.host.contains(query) }
        }
    }

    /// Both permissions' exceptions, one entry per host, sorted by host.
    private static func hostExceptions(in config: WidgetConfig) -> [WebsiteHostExceptions] {
        let camera = config.pagePermissionExceptions(.camera)
        let microphone = config.pagePermissionExceptions(.microphone)
        let hosts = Set(camera.map(\.host) + microphone.map(\.host)).sorted()
        return hosts.map { host in
            WebsiteHostExceptions(
                host: host,
                camera: camera.first { $0.host == host }?.setting,
                microphone: microphone.first { $0.host == host }?.setting)
        }
    }
}
