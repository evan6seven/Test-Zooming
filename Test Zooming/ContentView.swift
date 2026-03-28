//
//  ContentView.swift
//  Test Zooming
//
//  Created by mainuser on 2/16/26.
//

import SwiftUI
import WebKit

#if os(macOS)
import AppKit
typealias PlainWebViewRepresentable = NSViewRepresentable

private final class PlatformWKWebView: WKWebView {
    var magnifyEventHandler: ((PlatformWKWebView, NSEvent) -> Bool)?
    var layoutHandler: ((PlatformWKWebView) -> Void)?
    private var scrollEventMonitor: Any?
    private var lastLaidOutSize: CGSize = .zero

    deinit {
        removeScrollEventMonitor()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            removeScrollEventMonitor()
        } else {
            installScrollEventMonitor()
        }
    }

    override func scrollWheel(with event: NSEvent) {
        forwardScrollWheelToAncestor(event)
    }

    override func layout() {
        super.layout()

        guard bounds.size != lastLaidOutSize else { return }
        lastLaidOutSize = bounds.size
        layoutHandler?(self)
    }

    override func magnify(with event: NSEvent) {
        if magnifyEventHandler?(self, event) == true {
            return
        }
        super.magnify(with: event)
    }

    func alignMagnifiedContentToTop() {
        for scrollView in descendantScrollViews() {
            guard let documentView = scrollView.documentView else { continue }

            scrollView.layoutSubtreeIfNeeded()
            documentView.layoutSubtreeIfNeeded()

            let visibleHeight = scrollView.contentView.bounds.height
            let contentHeight = documentView.bounds.height
            let targetY: CGFloat

            if documentView.isFlipped {
                targetY = 0
            } else {
                targetY = max(contentHeight - visibleHeight, 0)
            }

            let targetX = scrollView.contentView.bounds.origin.x
            let targetPoint = NSPoint(x: targetX, y: targetY)
            if scrollView.contentView.bounds.origin != targetPoint {
                scrollView.contentView.scroll(to: targetPoint)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }
    }

    private func installScrollEventMonitor() {
        guard scrollEventMonitor == nil else { return }

        scrollEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
            guard let self, let window = self.window, event.window === window else {
                return event
            }

            let location = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(location) else {
                return event
            }

            self.forwardScrollWheelToAncestor(event)
            return nil
        }
    }

    private func removeScrollEventMonitor() {
        guard let scrollEventMonitor else { return }
        NSEvent.removeMonitor(scrollEventMonitor)
        self.scrollEventMonitor = nil
    }

    private func forwardScrollWheelToAncestor(_ event: NSEvent) {
        var ancestor: NSView? = superview
        while let current = ancestor {
            if let scrollView = current as? NSScrollView {
                scrollView.scrollWheel(with: event)
                return
            }
            ancestor = current.superview
        }
    }

    private func descendantScrollViews() -> [NSScrollView] {
        findDescendantScrollViews(in: self)
            .sorted { lhs, rhs in
                let lhsSize = lhs.documentView?.bounds.height ?? 0
                let rhsSize = rhs.documentView?.bounds.height ?? 0
                return lhsSize > rhsSize
            }
    }

    private func findDescendantScrollViews(in view: NSView) -> [NSScrollView] {
        var matches: [NSScrollView] = []

        for subview in view.subviews {
            if let scrollView = subview as? NSScrollView {
                matches.append(scrollView)
            }

            matches.append(contentsOf: findDescendantScrollViews(in: subview))
        }

        return matches
    }
}
#else
import UIKit
typealias PlainWebViewRepresentable = UIViewRepresentable
typealias PlatformWKWebView = WKWebView
#endif

struct PlainWebView: PlainWebViewRepresentable {
    let url: URL
    @Binding var zoomScale: CGFloat
    @Binding var frameScale: CGFloat
    @Binding var baseContentHeight: CGFloat
    @Binding var pinchGestureScale: CGFloat
    @Binding var pinchGestureState: String
    private let metricsHandlerName = "webViewportMetrics"

    #if os(macOS)
    func makeNSView(context: Context) -> WKWebView {
        let webView = makeWebView(with: context.coordinator)
        context.coordinator.loadIfNeeded(url, in: webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        updateWebView(nsView, with: context.coordinator)
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.teardown(from: nsView)
    }
    #else
    func makeUIView(context: Context) -> WKWebView {
        let webView = makeWebView(with: context.coordinator)
        context.coordinator.loadIfNeeded(url, in: webView)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        updateWebView(uiView, with: context.coordinator)
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.teardown(from: uiView)
    }
    #endif

    private func makeWebView(with coordinator: Coordinator) -> WKWebView {
        let config = WKWebViewConfiguration()
        configure(config, handler: coordinator)
        let webView = PlatformWKWebView(frame: .zero, configuration: config)
        coordinator.configure(webView)
        webView.navigationDelegate = coordinator
        return webView
    }

    private func updateWebView(_ webView: WKWebView, with coordinator: Coordinator) {
        coordinator.zoomScale = $zoomScale
        coordinator.frameScale = $frameScale
        coordinator.baseContentHeight = $baseContentHeight
        coordinator.pinchGestureScale = $pinchGestureScale
        coordinator.pinchGestureState = $pinchGestureState
        coordinator.configure(webView)
        coordinator.loadIfNeeded(url, in: webView)
    }

    private func configure(_ config: WKWebViewConfiguration, handler: Coordinator) {
        #if os(iOS)
        config.defaultWebpagePreferences.preferredContentMode = .mobile
        config.ignoresViewportScaleLimits = true
        config.userContentController.addUserScript(
            WKUserScript(
                source: Self.viewportScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        #endif

        config.userContentController.add(handler, name: metricsHandlerName)
        config.userContentController.addUserScript(
            WKUserScript(
                source: Self.metricsScript(handlerName: metricsHandlerName),
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            zoomScale: $zoomScale,
            frameScale: $frameScale,
            baseContentHeight: $baseContentHeight,
            pinchGestureScale: $pinchGestureScale,
            pinchGestureState: $pinchGestureState
        )
    }

    private static func metricsScript(handlerName: String) -> String {
        """
        (function() {
            if (window.__codexMetricsInstalled) { return; }
            window.__codexMetricsInstalled = true;

            function measure() {
                var viewport = window.visualViewport;
                var scale = viewport && viewport.scale ? viewport.scale : 1;
                var root = document.scrollingElement || document.documentElement || document.body;
                var rawHeight = root ? root.scrollHeight : 0;

                window.webkit.messageHandlers.\(handlerName).postMessage({
                    scale: scale,
                    rawHeight: rawHeight
                });
            }

            var scheduled = false;
            function scheduleMeasure() {
                if (scheduled) { return; }
                scheduled = true;
                requestAnimationFrame(function() {
                    scheduled = false;
                    measure();
                });
            }

            window.addEventListener('load', scheduleMeasure, true);
            document.addEventListener('readystatechange', scheduleMeasure, true);
            if (window.visualViewport) {
                window.visualViewport.addEventListener('resize', scheduleMeasure, true);
            }

            scheduleMeasure();
        })();
        """
    }

    private static let viewportScript = """
    (function() {
        var meta = document.querySelector('meta[name="viewport"]');
        if (!meta) {
            meta = document.createElement('meta');
            meta.name = 'viewport';
            document.head.appendChild(meta);
        }

        meta.setAttribute(
            'content',
            'width=device-width, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes'
        );
    })();
    """

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var zoomScale: Binding<CGFloat>
        var frameScale: Binding<CGFloat>
        var baseContentHeight: Binding<CGFloat>
        var pinchGestureScale: Binding<CGFloat>
        var pinchGestureState: Binding<String>
        private var loadedURL: URL?
        private var isPinching = false
        private var hasLockedBaseHeight = false
        private var lockedBaseHeight: CGFloat?
        private weak var webView: WKWebView?
        #if os(iOS)
        private weak var observedPinchGesture: UIPinchGestureRecognizer?
        #else
        private var observedMagnification: NSKeyValueObservation?
        private var pendingMagnificationCommit: DispatchWorkItem?
        private var pendingAlignmentWorkItem: DispatchWorkItem?
        private var suppressMagnificationObservation = false
        #endif

        init(
            zoomScale: Binding<CGFloat>,
            frameScale: Binding<CGFloat>,
            baseContentHeight: Binding<CGFloat>,
            pinchGestureScale: Binding<CGFloat>,
            pinchGestureState: Binding<String>
        ) {
            self.zoomScale = zoomScale
            self.frameScale = frameScale
            self.baseContentHeight = baseContentHeight
            self.pinchGestureScale = pinchGestureScale
            self.pinchGestureState = pinchGestureState
        }

        func configure(_ webView: WKWebView) {
            self.webView = webView
            #if os(iOS)
            webView.scrollView.isScrollEnabled = false
            webView.scrollView.alwaysBounceVertical = false
            webView.scrollView.bounces = false
            webView.scrollView.contentInsetAdjustmentBehavior = .never
            webView.scrollView.pinchGestureRecognizer?.isEnabled = true

            if observedPinchGesture !== webView.scrollView.pinchGestureRecognizer {
                observedPinchGesture?.removeTarget(self, action: #selector(handlePinchGesture(_:)))
                webView.scrollView.pinchGestureRecognizer?.addTarget(
                    self,
                    action: #selector(handlePinchGesture(_:))
                )
                observedPinchGesture = webView.scrollView.pinchGestureRecognizer
            }
            #else
            webView.allowsMagnification = true
            if let webView = webView as? PlatformWKWebView {
                webView.magnifyEventHandler = { [weak self] webView, event in
                    self?.handleMagnifyEvent(event, in: webView) ?? false
                }
                webView.layoutHandler = { [weak self] webView in
                    self?.handlePlatformLayout(in: webView)
                }
            }
            observeMagnification(on: webView)
            #endif
        }

        func teardown(from webView: WKWebView) {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "webViewportMetrics")
            #if os(iOS)
            observedPinchGesture?.removeTarget(self, action: #selector(handlePinchGesture(_:)))
            observedPinchGesture = nil
            #else
            if let webView = webView as? PlatformWKWebView {
                webView.magnifyEventHandler = nil
                webView.layoutHandler = nil
            }
            observedMagnification?.invalidate()
            observedMagnification = nil
            pendingMagnificationCommit?.cancel()
            pendingMagnificationCommit = nil
            pendingAlignmentWorkItem?.cancel()
            pendingAlignmentWorkItem = nil
            #endif
            self.webView = nil
        }

        func loadIfNeeded(_ url: URL, in webView: WKWebView) {
            configure(webView)
            guard loadedURL != url else { return }
            loadedURL = url
            baseContentHeight.wrappedValue = 0
            hasLockedBaseHeight = false
            lockedBaseHeight = nil
            isPinching = false
            zoomScale.wrappedValue = 1
            frameScale.wrappedValue = 1
            pinchGestureScale.wrappedValue = 1
            pinchGestureState.wrappedValue = "idle"
            #if os(macOS)
            suppressMagnificationObservation = true
            webView.setMagnification(1, centeredAt: .zero)
            suppressMagnificationObservation = false
            pendingAlignmentWorkItem?.cancel()
            pendingAlignmentWorkItem = nil
            #endif
            webView.load(URLRequest(url: url))
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            enableNativePageZoom(in: webView)
            updateMetrics(in: webView)
            refreshMetrics(in: webView)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard
                let body = message.body as? [String: Any]
            else {
                return
            }

            let reportedScale = max((body["scale"] as? NSNumber).map(CGFloat.init(truncating:)) ?? 1, 1)
            let rawHeight = max((body["rawHeight"] as? NSNumber).map(CGFloat.init(truncating:)) ?? 0, 1)
            let scale = currentScale(reportedScale: reportedScale, in: webView)
            applyMeasurement(rawHeight: rawHeight, fallbackHeight: 0, scale: scale)
        }

        private func updateMetrics(in webView: WKWebView) {
            let js = """
            (function() {
                var viewport = window.visualViewport;
                var scale = viewport && viewport.scale ? viewport.scale : 1;
                var root = document.scrollingElement || document.documentElement || document.body;
                var rawHeight = root ? root.scrollHeight : 0;
                return {
                    scale: scale,
                    rawHeight: rawHeight
                };
            })();
            """

            webView.evaluateJavaScript(js) { [weak self, weak webView] result, _ in
                guard let self else { return }
                let payload = result as? [String: Any]
                let reportedScale = max((payload?["scale"] as? NSNumber).map(CGFloat.init(truncating:)) ?? 1, 1)
                let rawHeight = max((payload?["rawHeight"] as? NSNumber).map(CGFloat.init(truncating:)) ?? 0, 0)
                let scale = self.currentScale(reportedScale: reportedScale, in: webView)
                #if os(iOS)
                let fallbackHeight = max(webView?.scrollView.contentSize.height ?? 0, 0)
                #else
                let fallbackHeight: CGFloat = 0
                #endif
                self.applyMeasurement(rawHeight: rawHeight, fallbackHeight: fallbackHeight, scale: scale)
            }
        }

        private func refreshMetrics(in webView: WKWebView, attemptsRemaining: Int = 20) {
            guard attemptsRemaining > 0 else { return }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self, weak webView] in
                guard let self, let webView else { return }
                guard !self.isPinching else { return }
                self.updateMetrics(in: webView)

                if self.baseContentHeight.wrappedValue <= 1 {
                    self.refreshMetrics(in: webView, attemptsRemaining: attemptsRemaining - 1)
                }
            }
        }

        private func applyMeasurement(rawHeight: CGFloat, fallbackHeight: CGFloat, scale: CGFloat) {
            let measuredHeight = rawHeight > 1 ? rawHeight : fallbackHeight
            guard measuredHeight > 1 || baseContentHeight.wrappedValue > 1 else { return }

            if let lockedBaseHeight {
                DispatchQueue.main.async {
                    if abs(self.baseContentHeight.wrappedValue - lockedBaseHeight) > 0.5 {
                        self.baseContentHeight.wrappedValue = lockedBaseHeight
                    }
                }
            } else if rawHeight > 1, !hasLockedBaseHeight, !isPinching, scale <= 1.01 {
                DispatchQueue.main.async {
                    if abs(self.baseContentHeight.wrappedValue - rawHeight) > 0.5 {
                        self.baseContentHeight.wrappedValue = rawHeight
                    }
                }
            }

            DispatchQueue.main.async {
                if abs(self.zoomScale.wrappedValue - scale) > 0.001 {
                    self.zoomScale.wrappedValue = scale
                }

                if !self.isPinching, abs(self.frameScale.wrappedValue - scale) > 0.001 {
                    self.frameScale.wrappedValue = scale
                }
            }
        }

        private func enableNativePageZoom(in webView: WKWebView) {
            #if os(iOS)
            webView.evaluateJavaScript(PlainWebView.viewportScript)
            #endif
        }

        private func currentScale(reportedScale: CGFloat, in webView: WKWebView?) -> CGFloat {
            #if os(macOS)
            if let webView {
                return max(webView.magnification, 1)
            }
            #endif
            return max(reportedScale, 1)
        }

        #if os(iOS)
        @objc
        func handlePinchGesture(_ gesture: UIPinchGestureRecognizer) {
            DispatchQueue.main.async {
                self.pinchGestureScale.wrappedValue = gesture.scale
                self.pinchGestureState.wrappedValue = switch gesture.state {
                case .possible: "possible"
                case .began: "began"
                case .changed: "changed"
                case .ended: "ended"
                case .cancelled: "cancelled"
                case .failed: "failed"
                @unknown default: "unknown"
                }
            }

            switch gesture.state {
            case .began:
                isPinching = true
                lockBaseHeightIfNeeded()
            case .changed:
                isPinching = true
            case .ended, .cancelled, .failed:
                isPinching = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak webView] in
                    guard let self, let webView else { return }
                    self.alignContentToTop(in: webView)
                    self.updateMetrics(in: webView)
                    self.refreshMetrics(in: webView, attemptsRemaining: 4)
                }
            default:
                break
            }
        }
        #else
        private func handleMagnifyEvent(_ event: NSEvent, in webView: PlatformWKWebView) -> Bool {
            switch event.phase {
            case .mayBegin, .began, .changed:
                isPinching = true
                lockBaseHeightIfNeeded()
                return false
            case .ended, .cancelled:
                isPinching = false
                return false
            default:
                return false
            }
        }

        private func observeMagnification(on webView: WKWebView) {
            guard observedMagnification == nil else { return }
            observedMagnification = webView.observe(\.magnification, options: [.new]) { [weak self, weak webView] view, _ in
                guard let self, let webView, !self.suppressMagnificationObservation else { return }
                self.handleMagnificationChange(in: webView, scale: max(view.magnification, 1))
            }
        }

        private func handleMagnificationChange(in webView: WKWebView, scale: CGFloat) {
            isPinching = true
            lockBaseHeightIfNeeded()

            DispatchQueue.main.async {
                if abs(self.zoomScale.wrappedValue - scale) > 0.001 {
                    self.zoomScale.wrappedValue = scale
                }
                self.pinchGestureScale.wrappedValue = scale
                self.pinchGestureState.wrappedValue = "changed"
            }

            pendingMagnificationCommit?.cancel()

            let workItem = DispatchWorkItem { [weak self, weak webView] in
                guard let self, let webView else { return }
                self.isPinching = false
                DispatchQueue.main.async {
                    if abs(self.frameScale.wrappedValue - scale) > 0.001 {
                        self.frameScale.wrappedValue = scale
                    }
                    self.pinchGestureScale.wrappedValue = scale
                    self.pinchGestureState.wrappedValue = scale > 1.001 ? "ended" : "idle"
                }
                self.alignContentToTop(in: webView)
                self.scheduleMacAlignmentRefresh(in: webView)
                self.updateMetrics(in: webView)
                self.refreshMetrics(in: webView, attemptsRemaining: 4)
            }

            pendingMagnificationCommit = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
        }

        private func handlePlatformLayout(in webView: PlatformWKWebView) {
            guard !isPinching else { return }
            guard max(webView.magnification, frameScale.wrappedValue) > 1.001 else { return }

            DispatchQueue.main.async { [weak self, weak webView] in
                guard let self, let webView else { return }
                self.alignContentToTop(in: webView)
            }
        }

        private func scheduleMacAlignmentRefresh(
            in webView: WKWebView,
            attemptsRemaining: Int = 8
        ) {
            guard attemptsRemaining > 0 else { return }

            pendingAlignmentWorkItem?.cancel()

            let workItem = DispatchWorkItem { [weak self, weak webView] in
                guard let self, let webView else { return }
                self.alignContentToTop(in: webView)
                self.scheduleMacAlignmentRefresh(
                    in: webView,
                    attemptsRemaining: attemptsRemaining - 1
                )
            }

            pendingAlignmentWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
        }
        #endif

        private func alignContentToTop(in webView: WKWebView) {
            #if os(iOS)
            let topOffset = -webView.scrollView.adjustedContentInset.top
            let currentOffset = webView.scrollView.contentOffset
            guard abs(currentOffset.y - topOffset) > 0.5 else { return }
            webView.scrollView.setContentOffset(
                CGPoint(x: currentOffset.x, y: topOffset),
                animated: false
            )
            #else
            (webView as? PlatformWKWebView)?.alignMagnifiedContentToTop()
            webView.evaluateJavaScript("window.scrollTo(window.scrollX, 0);")
            #endif
        }

        private func lockBaseHeightIfNeeded() {
            guard !hasLockedBaseHeight else { return }

            let snapshotHeight = max(baseContentHeight.wrappedValue, 1)
            if snapshotHeight > 1 {
                lockedBaseHeight = snapshotHeight
            }

            hasLockedBaseHeight = true
        }
    }
}

struct WebZoomView: View {
    @State private var zoomScale: CGFloat = 1
    @State private var frameScale: CGFloat = 1
    @State private var baseContentHeight: CGFloat = 1
    @State private var pinchGestureScale: CGFloat = 1
    @State private var pinchGestureState: String = "idle"

    private let blockHeight: CGFloat = 150
    private let placeholderHeight: CGFloat = 320

    private var resolvedWebHeight: CGFloat {
        let baseHeight = baseContentHeight > 1 ? baseContentHeight : placeholderHeight
        return baseHeight * max(frameScale, 1)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.blue)
                    .frame(height: blockHeight)
                    .overlay {
                        Text("Top Block")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }

                PlainWebView(
                    url: URL(string: "https://evan6seven.github.io/Test-Zooming/")!,
                    zoomScale: $zoomScale,
                    frameScale: $frameScale,
                    baseContentHeight: $baseContentHeight,
                    pinchGestureScale: $pinchGestureScale,
                    pinchGestureState: $pinchGestureState
                )
                    .frame(maxWidth: .infinity)
                    .frame(height: resolvedWebHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(.secondary, lineWidth: 1)
                    }
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("zoom \(zoomScale, format: .number.precision(.fractionLength(2)))")
                            Text("frame \(frameScale, format: .number.precision(.fractionLength(2)))")
                            Text("base \(baseContentHeight, format: .number.precision(.fractionLength(0)))")
                            Text("height \(resolvedWebHeight, format: .number.precision(.fractionLength(0)))")
                            Text("pinch \(pinchGestureState)")
                            Text("gesture \(pinchGestureScale, format: .number.precision(.fractionLength(2)))")
                        }
                        .font(.caption.monospacedDigit())
                        .padding(8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .padding(12)
                    }

                RoundedRectangle(cornerRadius: 16)
                    .fill(.orange)
                    .frame(height: blockHeight)
                    .overlay {
                        Text("Bottom Block")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(.background)
        #if os(iOS)
        .animation(.interactiveSpring(), value: zoomScale)
        .animation(.interactiveSpring(), value: frameScale)
        .animation(.interactiveSpring(), value: baseContentHeight)
        #endif
    }
}

struct ContentView: View {
    var body: some View {
        WebZoomView()
    }
}

#Preview {
    ContentView()
}
