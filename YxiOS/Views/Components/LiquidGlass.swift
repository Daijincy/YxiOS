//
//  LiquidGlass.swift
//  YxiOS
//
//  YxiOS — iOS port of YunX (https://github.com/CYQawa/YunX)
//  Copyright (C) 2026 CYQawa
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Global iOS 27 "Liquid Glass" style components: translucent cards, material
//  buttons, glass text fields, dark gradient background and soft spring motion.
//  Compiles on iOS 17 SDK: uses Material-based approximation (no reliance on
//  the newer glassEffect API, to guarantee a clean first build).
//

import SwiftUI

// MARK: - Global dark glass background

/// Full-screen dark gradient with a subtle blue/violet top glow.
/// Place behind transparent Lists / ScrollViews.
public struct LiquidGlassBackground: View {
    public init() {}

    public var body: some View {
        ZStack {
            Color(red: 0.045, green: 0.05, blue: 0.085)
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color(red: 0.36, green: 0.28, blue: 0.75).opacity(0.45),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .center
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color(red: 0.20, green: 0.42, blue: 0.85).opacity(0.35),
                    Color.clear
                ],
                startPoint: .topTrailing,
                endPoint: .center
            )
            .ignoresSafeArea()
        }
    }
}

// MARK: - Glass card modifier

public struct GlassCardModifier: ViewModifier {
    public var cornerRadius: CGFloat
    public init(cornerRadius: CGFloat = 24) {
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.20), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.35), radius: 14, x: 0, y: 8)
    }
}

extension View {
    /// Applies the frosted-glass card look: ultra-thin material, thin white
    /// highlight border and a soft drop shadow.
    public func glassCardStyle(cornerRadius: CGFloat = 24) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - GlassCard container

public struct GlassCard<Content: View>: View {
    private let cornerRadius: CGFloat
    private let content: Content

    public init(cornerRadius: CGFloat = 24, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    public var body: some View {
        content
            .padding(16)
            .glassCardStyle(cornerRadius: cornerRadius)
    }
}

// MARK: - Glass button

public struct GlassButton: View {
    public enum Style {
        case primary
        case secondary
    }

    private let title: String
    private let systemImage: String?
    private let style: Style
    private let action: () -> Void
    @State private var pressed = false

    public init(_ title: String,
                systemImage: String? = nil,
                style: Style = .primary,
                action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.style = style
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.headline)
                }
                Text(title)
                    .font(.headline)
            }
            .foregroundStyle(style == .primary ? .white : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(style == .primary ? 0.28 : 0.12), lineWidth: 0.5))
            .scaleEffect(pressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: pressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
    }
}

// MARK: - Glass text field

public struct GlassTextField: View {
    private let placeholder: String
    @Binding private var text: String
    private let systemImage: String?
    private let isSecure: Bool

    public init(_ placeholder: String,
                text: Binding<String>,
                systemImage: String? = nil,
                isSecure: Bool = false) {
        self.placeholder = placeholder
        self._text = text
        self.systemImage = systemImage
        self.isSecure = isSecure
    }

    public var body: some View {
        HStack(spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
            }
            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .foregroundStyle(.white)
            .autocorrectionDisabled(true)
            .textInputAutocapitalization(.never)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
        )
    }
}

// MARK: - Platform badge

public struct PlatformBadge: View {
    private let name: String
    public init(_ name: String) { self.name = name }

    public var body: some View {
        Text(name)
            .font(.caption.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.45, green: 0.4, blue: 0.9),
                             Color(red: 0.3, green: 0.55, blue: 0.95)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Capsule()
            )
    }
}
