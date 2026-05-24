/*
 * TurboMeta Home View
 * 主页 - Dual-mode: Iris Live (Red) / Agent (Blue)
 */

import SwiftUI

// MARK: - App Mode

enum AppMode {
    case idle, live, agent
}

// MARK: - TurboMeta Home View

struct TurboMetaHomeView: View {
    @ObservedObject var streamViewModel: StreamSessionViewModel
    @ObservedObject var wearablesViewModel: WearablesViewModel
    @State private var quickVisionManager = QuickVisionManager.shared
    @StateObject private var liveAIManager = LiveAIManager.shared
    let apiKey: String

    @State private var appMode: AppMode = .idle
    @State private var isPulsing = false
    @ObservedObject private var openClawService = OpenClawNodeService.shared

    private var backgroundGradient: [Color] {
        switch appMode {
        case .idle:
            return [Color(white: 0.06), Color(white: 0.02)]
        case .live:
            return [Color(red: 0.55, green: 0.04, blue: 0.04), Color(red: 0.18, green: 0.01, blue: 0.01)]
        case .agent:
            return [Color(red: 0.04, green: 0.08, blue: 0.45), Color(red: 0.02, green: 0.04, blue: 0.25)]
        }
    }

    var body: some View {
        ZStack {
            // Animated background
            LinearGradient(colors: backgroundGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.7), value: appMode)

            // Pulse ring — live mode only
            if appMode == .live {
                Circle()
                    .stroke(Color.red.opacity(0.35), lineWidth: 1.5)
                    .frame(width: 160, height: 160)
                    .scaleEffect(isPulsing ? 2.8 : 1.0)
                    .opacity(isPulsing ? 0 : 0.9)
                    .animation(.easeOut(duration: 1.8).repeatForever(autoreverses: false), value: isPulsing)
            }

            VStack(spacing: 0) {
                // Header
                VStack(spacing: AppSpacing.sm) {
                    Text("app.name".localized)
                        .font(AppTypography.largeTitle)
                        .foregroundColor(.white)
                    Text("app.subtitle".localized)
                        .font(AppTypography.callout)
                        .foregroundColor(.white.opacity(0.55))
                }
                .padding(.top, 64)

                Spacer()

                // Mode buttons
                HStack(spacing: 40) {
                    ModeButton(
                        icon: "mic.fill",
                        label: "Live",
                        accentColor: .red,
                        isActive: appMode == .live
                    ) {
                        activateLive()
                    }

                    ModeButton(
                        icon: "sparkles",
                        label: "에이전트",
                        accentColor: AppColors.primary,
                        isActive: appMode == .agent
                    ) {
                        activateAgent()
                    }
                }

                Spacer()

                // Status + Stop button
                Group {
                    if appMode != .idle {
                        VStack(spacing: AppSpacing.md) {
                            Text(appMode == .live ? "Live AI 실행 중..." : "에이전트 연결 중...")
                                .font(AppTypography.subheadline)
                                .foregroundColor(.white.opacity(0.75))

                            Button {
                                deactivate()
                            } label: {
                                Text("중지")
                                    .font(AppTypography.headline)
                                    .foregroundColor(.white)
                                    .frame(width: 160)
                                    .padding(.vertical, 14)
                                    .background(Color.white.opacity(0.15))
                                    .cornerRadius(30)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 30)
                                            .stroke(Color.white.opacity(0.25), lineWidth: 1)
                                    )
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .padding(.bottom, 64)
                    } else {
                        Color.clear.frame(height: 164)
                    }
                }
                .animation(.easeInOut(duration: 0.4), value: appMode)
            }
        }
        .onAppear {
            quickVisionManager.setStreamViewModel(streamViewModel)
            liveAIManager.setStreamViewModel(streamViewModel)
            if openClawService.connectionState == .disconnected,
               openClawService.loadGatewayToken() != nil {
                openClawService.connect()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .liveAITriggered)) { _ in
            activateLive()
        }
        .onChange(of: liveAIManager.isRunning) { isRunning in
            if !isRunning && appMode == .live {
                withAnimation(.easeInOut(duration: 0.7)) { appMode = .idle }
                isPulsing = false
            }
        }
    }

    private func activateLive() {
        guard appMode != .live else { return }
        withAnimation(.easeInOut(duration: 0.7)) { appMode = .live }
        isPulsing = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { isPulsing = true }
        Task { await liveAIManager.startLiveAISession() }
    }

    private func activateAgent() {
        guard appMode != .agent else { return }
        withAnimation(.easeInOut(duration: 0.7)) { appMode = .agent }
        openClawService.connect()
    }

    private func deactivate() {
        withAnimation(.easeInOut(duration: 0.7)) { appMode = .idle }
        isPulsing = false
        if liveAIManager.isRunning { liveAIManager.triggerStop() }
    }
}

// MARK: - Mode Button

private struct ModeButton: View {
    let icon: String
    let label: String
    let accentColor: Color
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(isActive ? accentColor : accentColor.opacity(0.18))
                        .frame(width: 110, height: 110)
                        .shadow(color: isActive ? accentColor.opacity(0.55) : .clear, radius: 22)

                    Image(systemName: icon)
                        .font(.system(size: 44, weight: .medium))
                        .foregroundColor(.white)
                }

                Text(label)
                    .font(AppTypography.headline)
                    .foregroundColor(.white.opacity(isActive ? 1.0 : 0.7))
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .animation(.spring(response: 0.4, dampingFraction: 0.65), value: isActive)
    }
}

// MARK: - Feature Card

struct FeatureCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let gradient: [Color]
    var isPlaceholder: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: AppSpacing.md) {
                Spacer()

                // Icon
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.2))
                        .frame(width: 56, height: 56)

                    Image(systemName: icon)
                        .font(.system(size: 26, weight: .medium))
                        .foregroundColor(.white)
                }

                // Text
                VStack(spacing: AppSpacing.xs) {
                    Text(title)
                        .font(AppTypography.headline)
                        .foregroundColor(.white)

                    Text(subtitle)
                        .font(AppTypography.caption)
                        .foregroundColor(.white.opacity(0.8))
                }

                if isPlaceholder {
                    Text("home.comingsoon".localized)
                        .font(AppTypography.caption)
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.xs)
                        .background(.white.opacity(0.2))
                        .cornerRadius(AppCornerRadius.sm)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .background(
                LinearGradient(
                    colors: gradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(AppCornerRadius.lg)
            .shadow(color: AppShadow.medium(), radius: 10, x: 0, y: 5)
        }
        .disabled(isPlaceholder)
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Feature Card Wide

struct FeatureCardWide: View {
    let title: String
    let subtitle: String
    let icon: String
    let gradient: [Color]
    var badge: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.lg) {
                // Icon
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.2))
                        .frame(width: 64, height: 64)

                    Image(systemName: icon)
                        .font(.system(size: 30, weight: .medium))
                        .foregroundColor(.white)
                }

                // Text
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    HStack(spacing: AppSpacing.sm) {
                        Text(title)
                            .font(AppTypography.title2)
                            .foregroundColor(.white)

                        if let badge = badge {
                            Text(badge)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.25))
                                .cornerRadius(4)
                        }
                    }

                    Text(subtitle)
                        .font(AppTypography.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(AppSpacing.lg)
            .background(
                LinearGradient(
                    colors: gradient,
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(AppCornerRadius.lg)
            .shadow(color: AppShadow.medium(), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Scale Button Style

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}
