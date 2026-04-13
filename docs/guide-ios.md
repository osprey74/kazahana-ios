# kazahana iOS Supplement Guide

This guide covers features specific to the iOS version of kazahana. For common features shared across all platforms (timeline, posts, search, notifications, DM, profile, settings, BSAF, etc.), see the [Desktop User Guide](https://github.com/osprey74/kazahana/blob/main/docs/en/guide/index.md).

---

## Table of Contents

- [Push Notifications](#push-notifications)
- [Share Extension](#share-extension)
- [Supporter Badge (In-App Purchase)](#supporter-badge)
- [iOS-Specific Navigation](#ios-specific-navigation)
- [Deep Links](#deep-links)
- [Differences from Desktop](#differences-from-desktop)

---

## Push Notifications

kazahana for iOS supports push notifications via Apple Push Notification service (APNs), integrated with the [kazahana-push-backend](https://github.com/osprey74/kazahana-push-backend).

### Enabling Push Notifications

When you log in for the first time, iOS will display a permission dialog asking to allow notifications. Tap **Allow** to enable push notifications.

If you dismissed or denied the dialog, you can enable them later:

1. Open the iOS **Settings** app.
2. Scroll down and tap **kazahana**.
3. Tap **Notifications**.
4. Toggle **Allow Notifications** on.

![iOS notification settings for kazahana](./images/mobile_004.png)

> **Note:** There is no in-app toggle for push notifications. This is controlled entirely through iOS Settings.

### How It Works

- When push notifications are enabled, your device token is automatically registered with the kazahana push notification server.
- Notifications are delivered for new activity on your account (likes, replies, reposts, follows, mentions, DMs, etc.).
- If you have multiple accounts, push notifications are registered for all of them.

### Badge Count

- The app icon badge shows the number of unread notifications.
- The badge is automatically cleared when you open the app.
- Background refresh periodically checks for unread notifications (approximately every 15 minutes, managed by iOS).

### When Logging Out

When you log out or remove an account, the device token is automatically unregistered from the push notification server for that account.

---

## Share Extension

You can share content from other apps (Safari, Photos, etc.) directly to kazahana.

### How to Share

1. In any app, tap the **Share** button (↑ icon).
2. Find and tap **kazahana** in the share sheet.

   ![kazahana in the share sheet](./images/mobile_001.png)

3. The kazahana share composer opens with the shared content pre-filled.

   ![kazahana share composer with link card](./images/mobile_002.png)

4. Edit the text if needed, then tap **Post**.

### What You Can Share

| Content Type | Behavior |
|--------------|----------|
| **URL** | The page title and URL are filled in. An OGP link card preview (thumbnail, title, description) is automatically generated. |
| **Text** | Plain text is inserted into the composer. |
| **Images** | Up to 4 images can be attached. Images are automatically compressed (max 950KB, max 2048px). |
| **Text + URL + Images** | All can be combined in a single post. If images are present, the link card is not attached (Bluesky limitation). |

### Limitations

- Maximum 300 characters per post.
- Maximum 4 images per share.
- You must be logged in to the kazahana app to use the share extension.
- The post language follows your kazahana language setting.

---

## Supporter Badge

Show your support for the kazahana project with a Supporter Badge.

### What It Does

When active, a gold medal icon appears on your avatar in the app, visible on your profile.

### How to Purchase

1. Open **Settings** (tap the Profile tab → Settings icon).
2. Scroll to the **Supporter Badge** section.
3. The current status is displayed: "Not Active" or "Expires on [date]."
4. Tap the **Purchase** button (the price is displayed in your local currency).

![Supporter Badge section](./images/mobile_003.png)
5. Authenticate with Face ID / Touch ID / Apple ID password.
6. The badge activates immediately.

### Duration & Renewal

- The Supporter Badge is valid for **30 days** from the date of purchase.
- To continue displaying the badge, purchase again after it expires.

### Restore Purchases

If you previously purchased the badge on another device or after reinstalling, tap **Restore Purchases** to recover your active badge.

---

## iOS-Specific Navigation

### Tab Bar

The tab bar is at the **bottom** of the screen with 5 tabs: Home, Search, Notifications, Messages, and Profile.

- **Re-tap Home tab** to scroll the timeline back to the top.
- Unread DM count is shown as a badge on the Messages tab.

### Gestures

| Gesture | Action |
|---------|--------|
| **Swipe from left edge** | Go back to the previous screen |
| **Swipe left on account** | Delete account (in Settings) |

---

## Deep Links

kazahana for iOS responds to `kazahana://` and `https://bsky.app` URLs:

| URL Pattern | Action |
|-------------|--------|
| `kazahana://profile/{handle}` | Opens the user's profile |
| `kazahana://post/{at_uri}` | Opens the post thread |
| `kazahana://hashtag/{tag}` | Searches for the hashtag |
| `kazahana://compose?text=...` | Opens the composer with pre-filled text |

---

## Differences from Desktop

### Features Available on iOS Only

| Feature | Description |
|---------|-------------|
| Push notifications | Real-time notifications via APNs |
| Share extension | Share from other apps to kazahana |
| Supporter Badge | In-app purchase for supporter recognition |
| Background refresh | Periodic notification check while app is in background |

### Desktop Features Not Available on iOS

| Feature | Reason |
|---------|--------|
| Bookmarklet | Not applicable on iOS (no browser bookmarks bar) |
| Auto-launch on OS startup | Not applicable on iOS |
| System tray minimize | Not applicable on iOS |
| Window management | iOS apps are full-screen |
