# HANDOFF: Bot Automation Label (Bot Badge)

## Overview

Bluesky added an "Automation Label" feature that allows bot accounts to self-label. When enabled, a robot icon appears next to the account's display name on profiles and posts. This document describes the API details and implementation guide for kazahana-ios.

The desktop version (kazahana) has already implemented this feature as a reference.

---

## API Details

### Data Structure

The bot label uses AT Protocol's existing **self-label system**. It is stored in the `labels` field of the `app.bsky.actor.profile` record.

**Profile record with bot label:**
```json
{
  "$type": "app.bsky.actor.profile",
  "displayName": "My Bot",
  "labels": {
    "$type": "com.atproto.label.defs#selfLabels",
    "values": [{ "val": "bot" }]
  }
}
```

### Detection via API

When fetching a profile via `app.bsky.actor.getProfile`, the `labels` array in the response contains expanded label objects:

```json
{
  "src": "did:plc:xxxxx",
  "uri": "at://did:plc:xxxxx/app.bsky.actor.profile/self",
  "cid": "bafyrei...",
  "val": "bot",
  "cts": "2025-01-01T00:00:00.000Z"
}
```

**Critical: The detection logic must verify TWO conditions:**
1. `label.val == "bot"` — the label value is "bot"
2. `label.src == profile.did` — the label was self-applied (not by an external labeler)

### Label Model

```swift
struct ATProtoLabel: Decodable {
    let src: String       // DID of label creator
    let val: String       // Label value (e.g., "bot")
    let uri: String       // URI of labeled resource
    let cid: String?      // CID of specific version
    let neg: Bool?        // Negation flag
    let cts: String       // Creation timestamp
    let exp: String?      // Expiration timestamp
}
```

All profile types (`ProfileViewBasic`, `ProfileView`, `ProfileViewDetailed`) include an optional `labels: [ATProtoLabel]?` array.

---

## Implementation Guide

### 1. Utility Function

```swift
func isBotAccount(did: String, labels: [ATProtoLabel]?) -> Bool {
    labels?.contains(where: { $0.val == "bot" && $0.src == did }) ?? false
}
```

### 2. BotBadge View

```swift
struct BotBadge: View {
    var size: CGFloat = 14

    var body: some View {
        Image(systemName: "gear.badge")  // or custom robot icon
            .font(.system(size: size))
            .foregroundColor(.gray)
    }
}
```

**SF Symbol options for robot icon:**
- `"desktopcomputer"` — generic computer
- `"cpu"` — processor chip
- Custom SVG asset recommended (Material Symbols `smart_toy` equivalent)

The official Bluesky iOS app uses a custom `bot_filled` SVG icon. Consider importing a similar asset.

### 3. Badge Sizes by Context

| Context | Size (pt) |
|---------|-----------|
| Quote embed / reply context | 12 |
| Post card / user list | 14 |
| Notification item | 13 |
| Profile header | 18 |

### 4. Views to Update

When building each phase, add `BotBadge` next to the display name:

**Phase 1-2 (Timeline):**
- `PostCardView` — author display name
- `ThreadView` — author display name in thread posts
- `QuoteEmbedView` — quoted post author

**Phase 3 (Profile/Notifications):**
- `ProfileHeaderView` — main profile display name
- `NotificationItemView` — notification author name
- `FollowerListView` / `FollowingListView` — user list items
- `SearchView` — user search results

**Phase 4+ (DM/Other):**
- `ConversationItemView` — DM partner display name

### 5. Tooltip / Accessibility

On tap or long-press of the badge, show an explanation:
- For other users: "This account has been marked as automated by its owner."
- For the account owner: "You have marked this account as automated."

Use `accessibilityLabel` for VoiceOver support.

### 6. Localization

| Locale | Key: `bot.label` |
|--------|-------------------|
| en | This account is automated |
| ja | このアカウントは自動化されています |
| de | Dieses Konto ist automatisiert |
| es | Esta cuenta está automatizada |
| fr | Ce compte est automatisé |
| id | Akun ini otomatis |
| ko | 이 계정은 자동화되어 있습니다 |
| pt | Esta conta é automatizada |
| ru | Этот аккаунт автоматизирован |
| zh-CN | 此账户已自动化 |
| zh-TW | 此帳戶已自動化 |

---

## Desktop Reference Implementation

The following files in `kazahana/` (desktop) serve as reference:

| File | Role |
|------|------|
| `src/components/common/BotBadge.tsx` | Badge component + `isBotAccount()` utility |
| `src/components/timeline/PostCard.tsx` | Post card usage (line 139) |
| `src/components/profile/ProfileHeader.tsx` | Profile header usage (line 210) |
| `src/components/profile/UserListItem.tsx` | User list usage (line 24) |
| `src/components/notification/NotificationItem.tsx` | Notification usage (line 127) |
| `src/components/common/QuoteEmbed.tsx` | Quote embed usage (line 86) |

---

## Official References

- [AT Protocol Bot Tutorial](https://atproto.com/guides/bot-tutorial)
- [Bluesky social-app BotBadge.tsx](https://github.com/bluesky-social/social-app/blob/main/src/components/BotBadge.tsx)
- [Label definitions lexicon](https://github.com/bluesky-social/atproto/blob/main/lexicons/com/atproto/label/defs.json)
- [Profile lexicon](https://github.com/bluesky-social/atproto/blob/main/lexicons/app/bsky/actor/profile.json)
