import AppKit
import UserNotifications
import WebKit

// ponytail: một hằng số; nếu Meta đổi điểm vào chat thì sửa ở đây (vd https://www.messenger.com/)
let startURL = URL(string: "https://www.facebook.com/messages/")!
let inAppHosts = ["facebook.com", "messenger.com"]
// UA Safari để Meta không báo "trình duyệt không hỗ trợ"
let safariUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Safari/605.1.15"

// WKWebView không có window.Notification -> giả lập, chuyển sang thông báo macOS
let notificationShim = """
(() => {
  class N {
    static get permission() { return 'granted'; }
    static requestPermission(cb) { cb && cb('granted'); return Promise.resolve('granted'); }
    constructor(title, o = {}) {
      this.title = title; this.body = o.body || '';
      window.webkit.messageHandlers.notify.postMessage({ title: String(title), body: String(this.body) });
    }
    close() {} addEventListener() {} removeEventListener() {}
  }
  window.Notification = N;

  // Chỉ giữ phần tin nhắn: link sang trang Facebook khác -> mở trình duyệt
  const keep = p => ['/messages', '/t/', '/e2ee', '/messenger_media', '/photo'].some(x => p.startsWith(x));
  document.addEventListener('click', e => {
    const a = e.target.closest && e.target.closest('a[href]');
    if (!a) return;
    const u = new URL(a.href, location.href);
    if (/(^|\\.)(facebook|messenger)\\.com$/.test(u.hostname) && !keep(u.pathname)) {
      e.preventDefault(); e.stopPropagation();
      window.webkit.messageHandlers.openExternal.postMessage(u.href);
    }
  }, true);

  // Font hệ thống macOS (San Francisco) thay cho Helvetica của Facebook
  const st = document.createElement('style');
  st.textContent = 'body, body * { font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif !important; }';
  document.documentElement.appendChild(st);

  // Phím tắt gọi từ menu native
  window.__mx = {
    search() {
      const i = document.querySelector('input[type="search"]')
        || document.querySelector('input[aria-label*="Messenger"], input[placeholder*="Messenger"]');
      if (i) { i.focus(); i.select(); }
    },
    openChat(n) {
      const seen = new Set(), list = [];
      for (const a of document.querySelectorAll('a[href*="/t/"]')) {
        const h = a.getAttribute('href');
        if (!seen.has(h)) { seen.add(h); list.push(a); }
      }
      list[n - 1]?.click();
    },
  };
})();
"""

// ponytail: thanh menu Facebook cao 56px; nếu Meta đổi chiều cao thì sửa số này
let facebookBannerHeight: CGFloat = 56
// Trang được ở trong app (giữ khớp với keep() trong JS). Chỉ trang chat mới giấu thanh menu.
let messagePaths = ["/messages", "/t/", "/e2ee"]
let inAppPaths = messagePaths + ["/messenger_media", "/photo"]
func hasPrefix(_ url: URL?, _ list: [String]) -> Bool { list.contains { url?.path.hasPrefix($0) == true } }

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate,
    WKScriptMessageHandler, UNUserNotificationCenterDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    var titleObserver: NSKeyValueObservation?
    var urlObserver: NSKeyValueObservation?
    var colorObserver: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default() // giữ cookie -> không phải đăng nhập lại
        config.userContentController.addUserScript(
            WKUserScript(source: notificationShim, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        config.userContentController.add(self, name: "notify")
        config.userContentController.add(self, name: "openExternal")

        webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = safariUA
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true

        // Badge Dock lấy từ tiêu đề trang, dạng "(3) Messenger"
        titleObserver = webView.observe(\.title) { view, _ in
            let title = view.title ?? ""
            let count = title.range(of: #"^\(\d+\+?\)"#, options: .regularExpression)
                .map { String(title[$0].dropFirst().dropLast()) }
            DispatchQueue.main.async { NSApp.dockTile.badgeLabel = count }
        }

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 750),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Messenger"
        // Thanh tiêu đề liền màu với trang (tự theo sáng/tối)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        colorObserver = webView.observe(\.underPageBackgroundColor, options: [.initial, .new]) { view, _ in
            DispatchQueue.main.async { self.window?.backgroundColor = view.underPageBackgroundColor }
        }
        let container = NSView()
        if #available(macOS 14, *) { container.clipsToBounds = true }
        window.contentView = container
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)
        setBannerHidden(true)
        // Trang chat: giấu thanh menu. Xem ảnh/đăng nhập: hiện đủ để không che nút đóng.
        urlObserver = webView.observe(\.url) { view, _ in
            DispatchQueue.main.async { self.setBannerHidden(hasPrefix(view.url, messagePaths)) }
        }
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("MainWindow")
        window.makeKeyAndOrderFront(nil)

        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }

        NSApp.mainMenu = buildMenu()
        NSApp.activate(ignoringOtherApps: true)
        webView.load(URLRequest(url: startURL))
    }

    // Đóng cửa sổ = ẩn, app vẫn chạy nền để nhận tin
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    func openOutside(_ url: URL) {
        NSLog("openOutside %@", url.absoluteString)
        NSWorkspace.shared.open(url)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.makeKeyAndOrderFront(nil)
        return true
    }

    // Link ngoài Facebook/Messenger -> trình duyệt mặc định
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard action.targetFrame?.isMainFrame == true, let url = action.request.url,
              url.scheme == "http" || url.scheme == "https" else { return decisionHandler(.allow) }
        // Bấm link trong app: chỉ giữ trang tin nhắn. Redirect/đăng nhập (không phải bấm link) vẫn cho qua.
        if isInApp(url) && (action.navigationType != .linkActivated || hasPrefix(url, inAppPaths)) { return decisionHandler(.allow) }
        openOutside(url)
        decisionHandler(.cancel)
    }

    // target=_blank / window.open
    func webView(_ webView: WKWebView, createWebViewWith config: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url, url.scheme == "http" || url.scheme == "https" {
            if isInApp(url) && hasPrefix(url, inAppPaths) { webView.load(action.request) } else { openOutside(url) }
        }
        return nil
    }

    // Chọn ảnh/file để gửi
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { completionHandler($0 == .OK ? panel.urls : nil) }
    }

    // Tin nhắn mới từ web -> thông báo macOS
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "openExternal" {
            if let s = message.body as? String, let url = URL(string: s), url.scheme == "https" || url.scheme == "http" {
                openOutside(url)
            }
            return
        }
        guard let body = message.body as? [String: String] else { return }
        let content = UNMutableNotificationContent()
        content.title = body["title"] ?? "Messenger"
        content.body = body["body"] ?? ""
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    // Bấm thông báo -> mở cửa sổ
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            self.window.makeKeyAndOrderFront(nil)
        }
        completionHandler()
    }

    func isInApp(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return inAppHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    // WebView cao hơn cửa sổ đúng bằng thanh menu Facebook, phần thừa nằm khuất phía trên
    func setBannerHidden(_ hidden: Bool) {
        guard let c = webView.superview else { return }
        webView.frame = NSRect(x: 0, y: 0, width: c.bounds.width,
                               height: c.bounds.height + (hidden ? facebookBannerHeight : 0))
    }

    @objc func reload() { webView.reload() }
    @objc func goBack() { webView.goBack() }
    @objc func search() { webView.evaluateJavaScript("window.__mx?.search()") }
    @objc func openChat(_ sender: NSMenuItem) { webView.evaluateJavaScript("window.__mx?.openChat(\(sender.tag))") }
    @objc func zoomIn() { webView.pageZoom = min(webView.pageZoom + 0.1, 2) }
    @objc func zoomOut() { webView.pageZoom = max(webView.pageZoom - 0.1, 0.5) }
    @objc func zoomReset() { webView.pageZoom = 1 }

    func buildMenu() -> NSMenu {
        let main = NSMenu()
        func add(_ title: String, _ items: [NSMenuItem]) {
            let sub = NSMenu(title: title)
            items.forEach(sub.addItem)
            let item = NSMenuItem()
            item.submenu = sub
            main.addItem(item)
        }
        func item(_ t: String, _ a: Selector?, _ k: String, _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let i = NSMenuItem(title: t, action: a, keyEquivalent: k)
            i.keyEquivalentModifierMask = mods
            return i
        }
        add("Messenger", [
            item("Hide Messenger", #selector(NSApplication.hide(_:)), "h"),
            .separator(),
            item("Quit Messenger", #selector(NSApplication.terminate(_:)), "q"),
        ])
        add("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
        ])
        add("View", [
            item("Reload", #selector(reload), "r"),
            .separator(),
            item("Actual Size", #selector(zoomReset), "0"),
            item("Zoom In", #selector(zoomIn), "="),
            item("Zoom Out", #selector(zoomOut), "-"),
        ])
        add("Go", [item("Back", #selector(goBack), "["), item("Search Chats", #selector(search), "k"), .separator()] + (1...9).map { n in
            let i = item("Chat \(n)", #selector(openChat(_:)), "\(n)")
            i.tag = n
            return i
        })
        add("Window", [
            item("Minimize", #selector(NSWindow.miniaturize(_:)), "m"),
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
        ])
        return main
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
