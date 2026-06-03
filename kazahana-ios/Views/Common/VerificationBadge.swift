import SwiftUI

/// Bluesky verification badge displayed next to display names.
/// Shows a shield icon for trusted verifiers, or a checkmark seal for verified accounts.
struct VerificationBadge: View {
    let profile: VerifiableProfile
    var size: CGFloat = 14

    private var isTrusted: Bool {
        profile.verification?.trustedVerifierStatus == "valid"
    }
    private var isVerified: Bool {
        !isTrusted && profile.verification?.verifiedStatus == "valid"
    }

    var body: some View {
        if isTrusted {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: size))
                .foregroundStyle(Color(hex: 0x0EA5E9))
                .accessibilityLabel(String(localized: "verification.trustedVerifier"))
        } else if isVerified {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: size))
                .foregroundStyle(Color(hex: 0x0EA5E9))
                .accessibilityLabel(String(localized: "verification.verified"))
        }
    }
}

/// Protocol for any profile type that may carry verification state.
protocol VerifiableProfile {
    var verification: VerificationState? { get }
}

extension ProfileViewBasic: VerifiableProfile {}
extension ProfileView: VerifiableProfile {}

#Preview {
    VStack(spacing: 12) {
        HStack {
            Text("Verified User")
            VerificationBadge(profile: ProfileViewBasic(
                did: "did:plc:test", handle: "test.bsky.social",
                displayName: "Test", avatar: nil, viewer: nil,
                labels: nil, createdAt: nil,
                verification: VerificationState(verifiedStatus: "valid", trustedVerifierStatus: nil)
            ))
        }
        HStack {
            Text("Trusted Verifier")
            VerificationBadge(profile: ProfileViewBasic(
                did: "did:plc:test2", handle: "verifier.bsky.social",
                displayName: "Verifier", avatar: nil, viewer: nil,
                labels: nil, createdAt: nil,
                verification: VerificationState(verifiedStatus: "valid", trustedVerifierStatus: "valid")
            ))
        }
    }
    .padding()
}
