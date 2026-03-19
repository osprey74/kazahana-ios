[日本語](README.ja.md)

# Kazahana for iOS

**A lightweight Bluesky client for iOS**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## Overview

Kazahana for iOS is a native Bluesky client built with Swift and SwiftUI.
It brings the same lightweight, fast, and simple experience as the [desktop version](https://github.com/osprey74/kazahana) to iPhone and iPad.

## Philosophy

Kazahana is designed as a **lightweight companion app** — not a full-featured standalone replacement for the official Bluesky web client.

- **Daily essentials in Kazahana** — Timeline browsing, posting, notifications, search, DMs, and other frequently used operations.
- **Configuration via Bluesky web** — Account management, block/mute list management, and other administrative tasks are left to [bsky.app](https://bsky.app/).

## Features

- **Timeline** — Home timeline with custom feed switching, auto-refresh (configurable interval), pull-to-refresh, and infinite scroll
- **Posts** — Rich text display (mentions, links, hashtags), images, video, external link cards, quote posts
- **Interactions** — Like, repost, quote post, reply with optimistic UI updates
- **Thread view** — Parent chain, focused post with stats, replies list; stats tap to show user lists
- **Notifications** — All notification types including like-via-repost and repost-via-repost
- **Profile** — Author feed (posts/replies/media/likes tabs), pinned post, follow/unfollow, followers/following lists, in-profile search
- **Search** — Actor search and post search with search history
- **Compose** — New post, reply, and quote post; image (crop + ALT text) and video attachment; mention autocomplete; threadgate (reply restrictions) and postgate (quote restrictions)
- **Direct Messages** — Conversation list, message thread, emoji reactions, new conversation creation with search history
- **Content Moderation** — Label-based filtering (hide/warn/ignore), adult content toggle, post reporting
- **Settings** — Theme, post language, auto-refresh interval, via attribution, Claude API key for ALT text generation

## Tech Stack

| Technology | Purpose |
|------------|---------|
| [Swift](https://www.swift.org/) | Programming language |
| [SwiftUI](https://developer.apple.com/xcode/swiftui/) | UI framework |
| [AT Protocol](https://atproto.com/) | Bluesky API |

## Requirements

- iOS 17.0+
- Xcode 16.0+

## Development

```bash
# Clone the repository
git clone https://github.com/osprey74/kazahana-ios.git

# Open in Xcode
open kazahana-ios.xcodeproj
```

## Related Projects

- [kazahana](https://github.com/osprey74/kazahana) — Desktop version (Windows / macOS)
- [kazahana-android](https://github.com/osprey74/kazahana-android) — Android version
- [BSAF Protocol](https://github.com/osprey74/bsaf-protocol) — Bluesky Structured Alert Feed specification

## License

[MIT License](LICENSE)

## Support

If you enjoy Kazahana, please consider supporting its development ☕

[![GitHub Sponsors](https://img.shields.io/badge/Sponsor-GitHub-ea4aaa?logo=github)](https://github.com/sponsors/osprey74)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-Support-ff5e5b?logo=ko-fi)](https://ko-fi.com/osprey74)
