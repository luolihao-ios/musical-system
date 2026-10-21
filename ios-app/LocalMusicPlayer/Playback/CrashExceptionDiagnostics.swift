import Foundation

// C 函数指针引用在非隔离的顶层声明，不能在 install 的 MainActor 中临时创建闭包。
private func recordUncaughtObjectiveCException(_ exception: NSException) {
    CrashExceptionDiagnostics.handle(exception)
}

enum CrashExceptionDiagnostics {
    // 启动主线程安装一次，此后只读；C 异常回调不能依赖 MainActor。
    nonisolated(unsafe) private static var previous: (@convention(c) (NSException) -> Void)?
    @MainActor private static var installed = false

    static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("music-crash-diagnostics.log")
    }

    @MainActor
    static func install() {
        guard !installed else { return }
        installed = true
        previous = NSGetUncaughtExceptionHandler()
        NSSetUncaughtExceptionHandler(recordUncaughtObjectiveCException)
        PlaybackDiagnostics.log("session version=\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "?") build=\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") ?? "?") ObjC异常记录已安装；Swift trap/系统强杀需系统ips")
    }

    fileprivate static func handle(_ exception: NSException) {
        record(exception)
        previous?(exception)
    }

    static func report(for exception: NSException) -> String {
        """
        \(DiagnosticTimestamp.string()) Objective-C未捕获异常
        version=\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "?") build=\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") ?? "?")
        name=\(exception.name.rawValue) reason=\(exception.reason ?? "未提供") main=\(Thread.isMainThread)
        exceptionStack:
        \(exception.callStackSymbols.isEmpty ? "异常未提供原始堆栈" : exception.callStackSymbols.joined(separator: "\n"))
        \n
        """
    }

    static func record(_ exception: NSException) {
        // 尽力同步落盘，不复用其他日志锁、不进入异步队列；不吞掉异常或假装恢复。
        let url = fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(report(for: exception).utf8).write(to: url, options: .atomic)
    }
}
