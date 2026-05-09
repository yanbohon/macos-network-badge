import AppKit
import Foundation
import WebKit

@MainActor
final class WebLoginWindowController: NSObject, ObservableObject, WKNavigationDelegate {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var statusField: NSTextField?
    private weak var monitor: SubscriptionMonitor?
    private var pollTimer: Timer?
    private var isCompleting = false

    func showWindow(monitor: SubscriptionMonitor) {
        self.monitor = monitor

        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard
            let url = URL(string: monitor.baseURLText),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else {
            return
        }

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController.addUserScript(WKUserScript(
            source: Self.authCaptureScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        self.webView = webView

        let statusField = NSTextField(labelWithString: "请在网页中完成登录")
        statusField.textColor = .secondaryLabelColor
        statusField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        self.statusField = statusField

        let reloadButton = NSButton(title: "重新载入", target: self, action: #selector(reload))
        let closeButton = NSButton(title: "关闭", target: self, action: #selector(close))
        let toolbar = NSStackView(views: [statusField, reloadButton, closeButton])
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.spacing = 8
        statusField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [toolbar, webView])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        webView.heightAnchor.constraint(greaterThanOrEqualToConstant: 620).isActive = true
        webView.widthAnchor.constraint(greaterThanOrEqualToConstant: 860).isActive = true

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 720),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "网页登录"
        newWindow.contentView = stack
        newWindow.isReleasedWhenClosed = false
        newWindow.center()
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = newWindow

        webView.load(URLRequest(url: url))
        startPolling()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        checkForToken()
    }

    @objc private func reload() {
        webView?.reload()
        startPolling()
    }

    @objc private func close() {
        pollTimer?.invalidate()
        pollTimer = nil
        window?.close()
        window = nil
        webView = nil
        statusField = nil
        isCompleting = false
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForToken()
            }
        }
    }

    private func checkForToken() {
        guard !isCompleting, let webView else { return }

        webView.evaluateJavaScript(Self.storageSnapshotScript) { [weak self, weak webView] result, _ in
            guard let self, let webView else { return }

            var storage: [String: String] = [:]
            if let json = result as? String,
               let data = json.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
                storage = decoded
            }

            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self else { return }
                let cookieMap = cookies.reduce(into: [String: String]()) { result, cookie in
                    result[cookie.name] = cookie.value
                }
                guard let token = WebLoginTokenExtractor.extract(from: storage, cookies: cookieMap) else {
                    return
                }
                self.finish(with: token)
            }
        }
    }

    private func finish(with token: WebLoginToken) {
        guard !isCompleting, let monitor else { return }
        isCompleting = true
        pollTimer?.invalidate()
        statusField?.stringValue = "已获取登录态，正在验证套餐"

        Task { @MainActor in
            do {
                try await monitor.completeWebLogin(token)
                statusField?.stringValue = "验证成功"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                    self?.close()
                }
            } catch {
                isCompleting = false
                statusField?.stringValue = monitor.lastError ?? "验证失败"
                startPolling()
            }
        }
    }

    private static let authCaptureScript = """
    (function() {
      if (window.__usageMonitorAuthHooked) { return; }
      window.__usageMonitorAuthHooked = true;
      const key = '\(WebLoginTokenExtractor.capturedAuthStorageKey)';
      const capture = function(url, text) {
        try {
          if (!url || !String(url).includes('/api/v1/auth/login')) { return; }
          const json = JSON.parse(text);
          if (json && json.data && json.data.access_token) {
            window.localStorage.setItem(key, JSON.stringify(json));
          }
        } catch (e) {}
      };

      const originalFetch = window.fetch;
      if (originalFetch) {
        window.fetch = function() {
          const args = arguments;
          return originalFetch.apply(this, args).then(function(response) {
            try {
              const requestUrl = response.url || String(args[0]);
              response.clone().text().then(function(text) { capture(requestUrl, text); });
            } catch (e) {}
            return response;
          });
        };
      }

      const originalOpen = XMLHttpRequest.prototype.open;
      const originalSend = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function(method, url) {
        this.__usageMonitorRequestUrl = url;
        return originalOpen.apply(this, arguments);
      };
      XMLHttpRequest.prototype.send = function() {
        this.addEventListener('loadend', function() {
          capture(this.responseURL || this.__usageMonitorRequestUrl || '', this.responseText || '');
        });
        return originalSend.apply(this, arguments);
      };
    })();
    """

    private static let storageSnapshotScript = """
    (function() {
      const output = {};
      const copy = function(prefix, storage) {
        try {
          for (let i = 0; i < storage.length; i++) {
            const key = storage.key(i);
            output[prefix + key] = storage.getItem(key);
          }
        } catch (e) {}
      };
      copy('local:', window.localStorage);
      copy('session:', window.sessionStorage);
      return JSON.stringify(output);
    })();
    """
}
