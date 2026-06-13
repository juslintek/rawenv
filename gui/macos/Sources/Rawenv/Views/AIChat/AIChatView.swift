import SwiftUI

struct AIChatView: View {
    @StateObject var viewModel: AIChatViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Proactive suggestion banner
            HStack(spacing: 8) {
                Text("🤖")
                Text("I detected PostgreSQL with 100 max_connections but only 3 active. Reduce to 20 to save ~40MB RAM?")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Button("Apply") { Task { viewModel.inputText = "optimize memory"; await viewModel.sendMessage() } }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                Button("Dismiss") {}.buttonStyle(.bordered).controlSize(.small)
            }
            .padding(10)
            .background(Color.accent.opacity(0.1))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accent.opacity(0.3)))
            .padding(.horizontal, 16).padding(.top, 12)
            .accessibilityIdentifier("ai_proactive_banner")

            // Header with provider selector
            HStack {
                Text("🤖 AI Assistant").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.textPrimary)
                Spacer()
                Picker("", selection: $viewModel.selectedProvider) {
                    ForEach(viewModel.providers, id: \.self) { p in Text(p).tag(p) }
                }
                .frame(width: 200)
                .accessibilityIdentifier("ai_provider_picker")
            }
            .padding(.horizontal, 16).padding(.vertical, 8)

            Divider().background(Color.border)

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    if !viewModel.messages.isEmpty {
                        messagesList
                    } else if viewModel.phase.isLoading {
                        LoadingStateView("Loading conversation…", idPrefix: "ai")
                    } else if let errorMessage = viewModel.phase.errorMessage {
                        ErrorStateView(
                            title: "Couldn't load conversation",
                            message: errorMessage,
                            idPrefix: "ai") {
                                Task { await viewModel.load() }
                            }
                    } else {
                        EmptyStateView(
                            icon: "bubble.left.and.bubble.right",
                            title: "Ask the AI assistant",
                            guidance: "No messages yet. Ask about your services, configuration, or deployment to get started.",
                            idPrefix: "ai")
                    }
                }
                .onChange(of: viewModel.messages.count) {
                    withAnimation { proxy.scrollTo(viewModel.messages.count - 1, anchor: .bottom) }
                }
            }
            .accessibilityIdentifier("ai_messages_list")

            Divider().background(Color.border)

            // Input
            HStack(spacing: 8) {
                TextField("Ask anything about your environment...", text: $viewModel.inputText)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color.bgTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .accessibilityIdentifier("ai_input")
                    .onSubmit { Task { await viewModel.sendMessage() } }
                Button("Send") { Task { await viewModel.sendMessage() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("ai_send_button")
            }
            .padding(12)
        }
        .background(Color.bgPrimary)
        .task { await viewModel.load() }
        .accessibilityIdentifier("ai_chat_view")
    }

    private var messagesList: some View {
        LazyVStack(spacing: 10) {
            ForEach(Array(viewModel.messages.enumerated()), id: \.offset) { idx, msg in
                MessageBubble(message: msg)
                    .id(idx)
                    .accessibilityIdentifier("message_\(msg.role)_\(idx)")
            }
            if viewModel.isLoading {
                HStack {
                    TypingIndicator()
                    Spacer()
                }.padding(.horizontal, 16)
                .accessibilityIdentifier("ai_typing")
            }
        }
        .padding(.vertical, 12)
    }
}

private struct MessageBubble: View {
    let message: AIMessage
    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }
            Text(message.text)
                .font(.system(size: 13))
                .foregroundStyle(Color.textPrimary)
                .padding(10)
                .background(isUser ? Color.accent.opacity(0.25) : Color.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.border, lineWidth: 0.5))
            if !isUser { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 16)
    }
}

private struct TypingIndicator: View {
    @State private var phase = 0.0
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(Color.textMuted).frame(width: 6, height: 6)
                    .offset(y: phase == Double(i) ? -3 : 0)
            }
        }
        .padding(10)
        .background(Color.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.4).repeatForever()) { phase = 2 }
        }
    }
}
