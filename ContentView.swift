//
//  ContentView.swift
//  Raft Browser
//
//  Re-created by ChatGPT on 4/26/25.
//

import SwiftUI
import WebKit
import AppKit
import Foundation

// Persist a device identifier in UserDefaults for license checks
private var persistentDeviceId: String {
    let key = "com.raftBrowser.deviceId"
    let defaults = UserDefaults.standard
    if let existing = defaults.string(forKey: key) {
        return existing
    }
    let newId = Host.current().localizedName ?? UUID().uuidString
    defaults.set(newId, forKey: key)
    return newId
}

struct LicenseResponse: Decodable {
    let status: String
    let expiresAt: Int?
}

struct WebView: NSViewRepresentable {
    @Binding var urlString: String
    @Binding var webViewRef: WKWebView?          // expose the instance to the parent

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let wk = WKWebView()
        // Enable JavaScript pop-ups and assign UI delegate
        wk.configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        wk.uiDelegate = context.coordinator
        wk.navigationDelegate = context.coordinator
        load(urlString, in: wk)
        DispatchQueue.main.async {
            webViewRef = wk                           // hand reference back up
        }
        return wk
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // Reload only when the address really changed
        if nsView.url?.absoluteString != resolvedURL(from: urlString)?.absoluteString {
            load(urlString, in: nsView)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: WebView
        init(_ parent: WebView) { self.parent = parent }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let url = webView.url?.absoluteString {
                parent.urlString = url
            }
        }

        // Open target="_blank" links in the same view
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        // Allow JavaScript alerts
        func webView(_ webView: WKWebView,
                     runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping () -> Void) {
            // Simply continue after alert
            completionHandler()
        }
    }

    private func load(_ input: String, in wk: WKWebView) {
        guard let url = resolvedURL(from: input) else { return }
        wk.load(URLRequest(url: url))
    }

    /// Converts user text into a valid URL; falls back to a Google search query.
    private func resolvedURL(from input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // If scheme is present, use directly
        if let direct = URL(string: text), direct.scheme != nil {
            return direct
        }

        // Try adding https:// only if it looks like a host
        if text.contains("."),
           let https = URL(string: "https://\(text)") {
            return https
        }

        // Otherwise treat as search terms
        let escaped = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://www.google.com/search?q=\(escaped)")
    }
}

struct BrowserTab: Identifiable, Hashable {
    let id = UUID()
    var address: String
}

private struct TabButton: View {
    let tab: BrowserTab
    var isSelected: Bool
    var closeAction: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            AsyncImage(url: faviconURL(from: tab.address)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                default:
                    Image(systemName: "globe")
                        .resizable()
                        .scaledToFit()
                }
            }
            .frame(width: 16, height: 16)
            .clipShape(RoundedRectangle(cornerRadius: 3))

            Button(action: closeAction) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .padding(6)
        .background(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func host(from address: String) -> String {
        URL(string: address)?.host ?? "New Tab"
    }

    private func faviconURL(from address: String) -> URL? {
        guard let host = URL(string: address)?.host else { return nil }
        return URL(string: "https://\(host)/favicon.ico")
    }
}

func checkLicense(key: String, completion: @escaping (LicenseResponse) -> Void) {
    guard let url = URL(string: "https://raft-license-server.onrender.com/verify") else {
        completion(LicenseResponse(status: "error", expiresAt: nil))
        return
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.addValue("application/json", forHTTPHeaderField: "Content-Type")

    let deviceId = persistentDeviceId
    let body: [String: String] = ["key": key, "deviceId": deviceId]
    request.httpBody = try? JSONEncoder().encode(body)

    URLSession.shared.dataTask(with: request) { data, response, error in
        guard let data = data,
              let result = try? JSONDecoder().decode(LicenseResponse.self, from: data) else {
            DispatchQueue.main.async {
                completion(LicenseResponse(status: "invalid", expiresAt: nil))
            }
            return
        }
        DispatchQueue.main.async {
            completion(result)
        }
    }.resume()
}

struct ContentView: View {
    // Prevent multiple event monitors
    private static var eventMonitorSet: Bool = false

    @State private var tabs: [BrowserTab] = [BrowserTab(address: "https://www.google.com")]
    @State private var selection: BrowserTab.ID?
    @State private var webViewRef: WKWebView? = nil

    @State private var addressField: String = "https://www.google.com"
    @FocusState private var isAddressFocused: Bool

    @State private var showLicensePrompt = true
    @State private var enteredKey = ""
    @State private var licenseAlertMessage: String = "Please enter your license key."
    @State private var showInfoAlert = false
    @State private var infoAlertMessage = ""
    @State private var showErrorAlert = false
    @State private var errorAlertMessage = ""
    @State private var isCheckingLicense = false

    // ─── NEW COUNTDOWN STATE ──────────────────────────────────────
    @State private var expirationDate: Date? = nil
    @State private var remainingTimeString: String = ""
    @State private var countdownTimer: Timer? = nil
    // ─────────────────────────────────────────────────────────────

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // MARK: - Scrollable tab bar
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(tabs) { tab in
                                Button(action: {
                                    selection = tab.id
                                    syncAddressField()
                                    isAddressFocused = false
                                }) {
                                    TabButton(tab: tab,
                                              isSelected: tab.id == (selection ?? tabs.first!.id),
                                              closeAction: { close(tab) })
                                }
                                .buttonStyle(.plain)
                                .id(tab.id)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                    }
                    .background(.ultraThinMaterial)
                }

                // MARK: - Address bar
                VStack(spacing: 2) {
                    HStack(spacing: 10) {
                        Button(action: goBack) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14))
                                .frame(width: 24, height: 24)
                                .background(Color.accentColor.opacity(0.15))
                                .cornerRadius(6)
                        }
                        .help("Back")
                        .disabled(!(webViewRef?.canGoBack ?? false))

                        Button(action: goForward) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14))
                                .frame(width: 24, height: 24)
                                .background(Color.accentColor.opacity(0.15))
                                .cornerRadius(6)
                        }
                        .help("Forward")
                        .disabled(!(webViewRef?.canGoForward ?? false))

                        Button(action: reloadPage) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14))
                                .frame(width: 24, height: 24)
                                .background(Color.accentColor.opacity(0.15))
                                .cornerRadius(6)
                        }
                        .help("Reload")

                        TextField("Search or enter website name", text: $addressField)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(maxWidth: .infinity)
                            .help("Type something and press ⏎")
                            .focused($isAddressFocused)
                            .submitLabel(.go)
                            .onSubmit { commit() }

                        Button(action: commit) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 14))
                                .frame(width: 24, height: 24)
                                .background(Color.accentColor.opacity(0.15))
                                .cornerRadius(6)
                        }
                        .keyboardShortcut(.defaultAction)
                        .help("Go")

                        Button(action: openChatGPT) {
                            Text("🐼")
                                .font(.system(size: 20))
                                .frame(width: 28, height: 28)
                        }
                        .help("Open ChatGPT")
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                Divider()

                // MARK: - Active web view
                if let idx = activeIndex {
                    WebView(urlString: $tabs[idx].address, webViewRef: $webViewRef)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .animation(.easeInOut(duration: 0.2), value: tabs)
                }

                Divider()

                // ─── SHOW LOCAL COUNTDOWN ───────────────────────────────
                if expirationDate != nil {
                    Text("Expires in: \(remainingTimeString)")
                        .font(.caption2)
                        .foregroundColor(.red)
                        .padding(.bottom, 4)
                }
                // ────────────────────────────────────────────────────────

                Text("Made by Skipper")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial)
            }

            if isCheckingLicense {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                ProgressView("Checking license…")
                    .padding(16)
                    .background(.ultraThinMaterial)
                    .cornerRadius(10)
            }
        }
        .frame(minWidth: 600, minHeight: 450)
        .background(.windowBackground)

        // MARK: — License Entry Alert
        .alert("Enter License Key", isPresented: $showLicensePrompt) {
            TextField("License Key", text: $enteredKey)
            Button("Submit") {
                isCheckingLicense = true
                checkLicense(key: enteredKey) { response in
                    DispatchQueue.main.async {
                        isCheckingLicense = false
                        switch response.status {
                        case "valid":
                            showLicensePrompt = false
                            showInfoAlert = true
                            if let ts = response.expiresAt {
                                startCountdown(from: Double(ts))
                                infoAlertMessage = "License valid! 🎉"
                            } else {
                                infoAlertMessage = "License valid!"
                            }
                        case "expired":
                            errorAlertMessage = "Your license has expired. Please resubscribe."
                            showErrorAlert = true
                        default:
                            errorAlertMessage = "Invalid license key. Please resubscribe."
                            showErrorAlert = true
                        }
                    }
                }
            }
        } message: {
            Text(licenseAlertMessage)
        }

        // MARK: — Info Alert
        .alert("License Active", isPresented: $showInfoAlert) {
            Button("OK") { }
        } message: {
            Text(infoAlertMessage)
        }

        // MARK: — Error Alert
        .alert("Subscription Required", isPresented: $showErrorAlert) {
            Button("OK") {
                NSApp.terminate(nil)
            }
        } message: {
            Text(errorAlertMessage)
                .font(.title)
        }

        .onAppear {
            if showLicensePrompt {
                // waiting for user to enter key
            } else {
                // initial server check + polling every 60s
                checkLicense(key: enteredKey) { response in
                    DispatchQueue.main.async {
                        if response.status != "valid" {
                            NSApp.terminate(nil)
                        } else if let ts = response.expiresAt {
                            startCountdown(from: Double(ts))
                        }
                    }
                }
                // poll every minute to refresh expiresAt
                Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
                    checkLicense(key: enteredKey) { response in
                        DispatchQueue.main.async {
                            if response.status != "valid" {
                                NSApp.terminate(nil)
                            } else if let ts = response.expiresAt {
                                startCountdown(from: Double(ts))
                            }
                        }
                    }
                }
            }

            DispatchQueue.main.async {
                selection = tabs.first?.id
                syncAddressField()
                if let webView = webViewRef {
                    NSApp.keyWindow?.makeFirstResponder(webView)
                }
                if !ContentView.eventMonitorSet {
                    NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                        NSApp.keyWindow == NSApp.mainWindow ? nil : event
                    }
                    ContentView.eventMonitorSet = true
                }
            }
        }
        .onDisappear {
            countdownTimer?.invalidate()
        }
        .onChange(of: selection) { _ in
            syncAddressField()
        }
    }

    private func addTab() {
        let newTab = BrowserTab(address: "https://www.google.com")
        tabs.append(newTab)
        selection = newTab.id
        addressField = newTab.address
        isAddressFocused = true
        if let url = URL(string: newTab.address) {
            webViewRef?.load(URLRequest(url: url))
        }
    }

    private func close(_ tab: BrowserTab) {
        guard let idx = tabs.firstIndex(of: tab) else { return }
        tabs.remove(at: idx)
        if tabs.isEmpty {
            addTab()
        } else {
            if idx < tabs.count {
                selection = tabs[idx].id
            } else {
                selection = tabs.last?.id
            }
        }
        DispatchQueue.main.async {
            syncAddressField()
        }
    }

    private func syncAddressField() {
        if let idx = activeIndex {
            addressField = tabs[idx].address
        }
    }

    private func verifyLicense(perform action: @escaping () -> Void) {
        checkLicense(key: enteredKey) { response in
            DispatchQueue.main.async {
                if response.status != "valid" {
                    NSApp.terminate(nil)
                } else {
                    action()
                }
            }
        }
    }

    private func commit() {
        verifyLicense {
            guard let idx = activeIndex else { return }
            let trimmed = addressField.trimmingCharacters(in: .whitespacesAndNewlines)
            addressField = trimmed
            if tabs[idx].address != trimmed {
                tabs[idx].address = trimmed
                if let url = resolvedURL(from: trimmed) {
                    webViewRef?.load(URLRequest(url: url))
                }
            }
        }
    }

    private func openChatGPT() {
        verifyLicense {
            if let idx = activeIndex {
                tabs[idx].address = "https://chat.openai.com"
                if let url = resolvedURL(from: "https://chat.openai.com") {
                    webViewRef?.load(URLRequest(url: url))
                }
            }
        }
    }

    private func goBack() { verifyLicense { webViewRef?.goBack() } }
    private func goForward() { verifyLicense { webViewRef?.goForward() } }
    private func reloadPage() { verifyLicense { webViewRef?.reload() } }

    private func resolvedURL(from input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let direct = URL(string: text), direct.scheme != nil {
            return direct
        }
        if text.contains("."), let https = URL(string: "https://\(text)") {
            return https
        }
        let escaped = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://www.google.com/search?q=\(escaped)")
    }

    private var activeIndex: Int? {
        if let sel = selection {
            return tabs.firstIndex(where: { $0.id == sel })
        }
        return tabs.indices.first
    }

    // ─── HELPER: LOCAL COUNTDOWN ────────────────────────────────
    private func startCountdown(from expiresAtMs: Double) {
        expirationDate = Date(timeIntervalSince1970: expiresAtMs / 1000)
        countdownTimer?.invalidate()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            guard let exp = expirationDate else { return }
            let interval = exp.timeIntervalSinceNow
            if interval <= 0 {
                remainingTimeString = "Expired"
                countdownTimer?.invalidate()
                // Prompt user when the key expires
                showErrorAlert = true
                errorAlertMessage = "Your license key has expired. Please re-enter it to continue."
                showLicensePrompt = true
            } else {
                let hrs = Int(interval) / 3600
                let mins = (Int(interval) % 3600) / 60
                let secs = Int(interval) % 60
                remainingTimeString = String(format: "%02dh %02dm %02ds", hrs, mins, secs)
            }
        }
        countdownTimer?.fire()
    }
    // ──────────────────────────────────────────────────────────
}

#Preview {
    ContentView()
}
