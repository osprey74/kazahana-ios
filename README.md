[日本語](README.ja.md)

# Kazahana for iOS

**A lightweight Bluesky client for iOS**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## Overview

Kazahana for iOS is a native Bluesky client built with Swift and SwiftUI.
It brings the same lightweight, fast, and simple experience as the [desktop version](https://github.com/osprey74/kazahana) to iPhone (including iPhone Duo), iPad, and Mac (Mac Catalyst).

## Philosophy

Kazahana is designed as a **lightweight companion app** — not a full-featured standalone replacement for the official Bluesky web client.

- **Daily essentials in Kazahana** — Timeline browsing, posting, notifications, search, DMs, and other frequently used operations.
- **Configuration via Bluesky web** — Account management, block/mute list management, and other administrative tasks are left to [bsky.app](https://bsky.app/).

## Features

- **Timeline** — Home timeline with custom feed switching (swipe to switch on iOS), auto-refresh (configurable interval), pull-to-refresh, reload button, and infinite scroll
- **Posts** — Rich text display (mentions, links, hashtags), images (up to 10 with gallery carousel), animated GIFs, video (up to 300 MB) with ALT text, external link cards, quote posts (with embedded media), OP thread position badges (e.g. 2/3)
- **Interactions** — Like, repost, quote post, reply with optimistic UI updates
- **Thread view** — Parent chain, focused post with stats, replies list; stats tap to show user lists
- **Notifications** — All notification types including like-via-repost, repost-via-repost, and verified/unverified
- **Verification Badges** — Bluesky verification marks and trusted verifier badges displayed next to display names
- **Profile** — Author feed (posts/replies/media/likes tabs), pinned post, follow/unfollow, followers/following lists, in-profile search, clickable links in bio, "Follows you" badge
- **Search** — Actor search and post search with search history
- **Compose** — New post, reply, and quote post; up to 10 images (crop + ALT text) with gallery embed auto-promotion and video attachment (300 MB, server limit check, ALT text); upload progress indicator; mention autocomplete; threadgate (reply restrictions) and postgate (quote restrictions); draft saving on cancel
- **Direct Messages & Group Chat** — 1:1 conversations and group chat (up to 50 members); group creation, invite link management, join request approval, member management, lock/unlock; sender names in group chats; emoji reactions, new conversation creation with search history
- **Profile QR Code** — Generate and share a QR code for your Bluesky profile; copy link, share via system sheet, or save to Photos
- **Content Moderation** — Label-based filtering (hide/warn/ignore), adult content toggle, post reporting
- **Settings** — Theme, font size (4 levels), post language, auto-refresh interval, via attribution, Claude API key for ALT text generation
- **Sharing** — Share any post via the iOS share sheet; post from other apps via the Share Extension (crop + ALT text); open `kazahana://` deep links from other apps
- **Evacuation Assist** — Nearest shelter search based on JMA hazard level information (bsaf-kikikuru-bot), compass-based offline navigation, alert banner with auto-detection via BSAF
- **Background Refresh** — Periodic background notification polling with local push notifications (iOS); foreground polling with macOS notifications (Mac Catalyst)
- **iPhone Duo** — Adapts to both the outer and inner displays in every orientation; toolbars and tab bars move to the side of the display
- **Keyboard Shortcuts (macOS)** — Cmd+N (new post), Cmd+Return (submit post), Cmd+R (reload), Cmd+1–5 (switch tabs)

## Tech Stack

| Technology | Purpose |
|------------|---------|
| [Swift](https://www.swift.org/) | Programming language |
| [SwiftUI](https://developer.apple.com/xcode/swiftui/) | UI framework |
| [AT Protocol](https://atproto.com/) | Bluesky API |

## Requirements

- iOS 18.0+
- Xcode 27.0+ (Xcode 27.1+ to test on iPhone Duo)

## Development

```bash
# Clone the repository
git clone https://github.com/osprey74/kazahana-ios.git

# Open in Xcode
open kazahana-ios.xcodeproj

# Run unit tests
xcodebuild test -project kazahana-ios.xcodeproj -scheme kazahana-ios \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -only-testing:kazahana-iosTests
```

### Project Structure

| Path | Contents |
|------|----------|
| `kazahana-ios/` | Main app (iOS / Mac Catalyst) |
| `ShareExtension/` | Share Extension (post from other apps) |
| `kazahana-iosTests/` | Unit tests (Swift Testing) |
| `kazahana-iosUITests/` | UI tests |
| `Documentation/` | Development tasks and progress (`tasks.md`) |

## Related Projects

- [kazahana](https://github.com/osprey74/kazahana) — Desktop version (Windows)
- [kazahana-android](https://github.com/osprey74/kazahana-android) — Android version
- [BSAF Protocol](https://github.com/osprey74/bsaf-protocol) — Bluesky Structured Alert Feed specification

## License

[MIT License](LICENSE)

## Support

If you enjoy Kazahana, please consider supporting its development ☕

[![GitHub Sponsors](https://img.shields.io/badge/Sponsor-GitHub-ea4aaa?logo=github)](https://github.com/sponsors/osprey74)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support-ff5e5b?logo=ko-fi)](https://ko-fi.com/osprey74)
