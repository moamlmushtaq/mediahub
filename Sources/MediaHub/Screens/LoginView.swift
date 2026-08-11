import SwiftUI
import MediaHubKit

/// The front door.
///
/// A single centred card on the app's own ground rather than a form filling the
/// window. There are two fields; stretching them across 1360 points would make
/// the first screen of the app look like a database tool.
struct LoginView: View {
    @Environment(AppModel.self) private var app

    @State private var username = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var error: String?

    /// Carries the reason a session ended, so a viewer who was signed out
    /// mid-session is told why rather than simply finding themselves here.
    let notice: String?

    @FocusState private var focus: Field?
    private enum Field { case username, password }

    private var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
            && !isWorking
    }

    var body: some View {
        ZStack {
            Theme.Palette.ink.ignoresSafeArea()

            VStack(spacing: Theme.space(7)) {
                mark

                VStack(spacing: Theme.space(4)) {
                    fields
                    messages
                    submit
                }
                .frame(width: 320)
            }
            .padding(Theme.space(10))
        }
        .onAppear { focus = .username }
    }

    private var mark: some View {
        VStack(spacing: Theme.space(3)) {
            MediaHubMark()
                .frame(width: 76, height: 76)

            Text("ميديا هَب")
                .font(Theme.Type.title)
                .foregroundStyle(Theme.Palette.bone)

            Text("مكتبة خاصة")
                .font(Theme.Type.label)
                .foregroundStyle(Theme.Palette.dim)
        }
    }

    private var fields: some View {
        VStack(spacing: Theme.space(2.5)) {
            LoginField(
                title: "اسم المستخدم",
                text: $username,
                isSecure: false
            )
            .focused($focus, equals: .username)
            .onSubmit { focus = .password }

            LoginField(
                title: "كلمة المرور",
                text: $password,
                isSecure: true
            )
            .focused($focus, equals: .password)
            .onSubmit { attempt() }
        }
    }

    @ViewBuilder
    private var messages: some View {
        // The two messages are different things and must not share a slot: one
        // is why the last session ended, the other is why this attempt failed.
        if let error {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(Theme.Type.label)
                .foregroundStyle(Theme.Palette.rose)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
        } else if let notice {
            Text(notice)
                .font(Theme.Type.label)
                .foregroundStyle(Theme.Palette.ash)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var submit: some View {
        Button(action: attempt) {
            ZStack {
                // The label stays in the layout while working, so the button
                // does not change size and jump the card.
                Text("دخول").opacity(isWorking ? 0 : 1)
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.Palette.ink)
                }
            }
            .font(Theme.Type.heading)
            .foregroundStyle(Theme.Palette.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.space(2.5))
            .background(canSubmit ? Theme.Palette.gold : Theme.Palette.gold.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
        // Return submits from anywhere on the card, which is what every login
        // screen on this platform does.
        .keyboardShortcut(.defaultAction)
    }

    private func attempt() {
        guard canSubmit else { return }
        isWorking = true
        error = nil

        Task {
            do {
                try await app.signIn(
                    username: username.trimmingCharacters(in: .whitespaces),
                    password: password
                )
            } catch let failure as MediaHubError {
                // The server writes these for the viewer, in Arabic. Replacing
                // them with our own wording would turn a specific reason
                // ("الحساب موقوف") into a generic one.
                withAnimation { error = failure.message }
                password = ""
                focus = .password
            } catch {
                withAnimation { self.error = "تعذّر تسجيل الدخول." }
            }
            isWorking = false
        }
    }
}

/// A text field that looks like it belongs to this app rather than to a form.
private struct LoginField: View {
    let title: String
    @Binding var text: String
    let isSecure: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space(1.5)) {
            Text(title)
                .font(Theme.Type.caption)
                .foregroundStyle(Theme.Palette.dim)

            Group {
                if isSecure {
                    SecureField("", text: $text)
                } else {
                    TextField("", text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(Theme.Type.body)
            .foregroundStyle(Theme.Palette.bone)
            .padding(.horizontal, Theme.space(3))
            .padding(.vertical, Theme.space(2.5))
            .background(Theme.Palette.inkRaised)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            .hairlineBorder()
        }
    }
}

/// The mark, drawn rather than shipped as an asset.
///
/// A SwiftUI shape scales to any size with no bitmap and no asset catalogue —
/// and a SwiftPM executable has no asset catalogue to put one in.
struct MediaHubMark: View {
    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let stroke = side * 0.043

            ZStack {
                // Four arcs with gaps on the diagonals: a film reel implied
                // rather than drawn, which survives being 24 points wide.
                ForEach(0..<4, id: \.self) { quarter in
                    Circle()
                        .trim(from: 0.02, to: 0.23)
                        .stroke(
                            LinearGradient(
                                colors: [Theme.Palette.goldBright, Theme.Palette.gold],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            style: StrokeStyle(lineWidth: stroke, lineCap: .round)
                        )
                        .rotationEffect(.degrees(Double(quarter) * 90))
                }
                .padding(side * 0.16)

                Triangle()
                    .fill(
                        LinearGradient(
                            colors: [Theme.Palette.goldBright, Theme.Palette.gold],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: side * 0.26, height: side * 0.30)
                    // Optically centred: a triangle balanced on its bounding
                    // box always reads as pushed toward its flat edge.
                    .offset(x: side * 0.025)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
