# kazahana iOS Supplement Guide

This guide covers features specific to the iOS version of kazahana. For common features shared across all platforms (timeline, posts, search, notifications, DM, profile, settings, BSAF, etc.), see the [Desktop User Guide](https://github.com/osprey74/kazahana/blob/main/docs/en/guide/index.md).

---

## Table of Contents

- [Shelter Navigator (Evacuation Assist)](#shelter-navigator-evacuation-assist)
- [Push Notifications](#push-notifications)
- [Share Extension](#share-extension)
- [Supporter Badge (In-App Purchase)](#supporter-badge)
- [iOS-Specific Navigation](#ios-specific-navigation)
- [Deep Links](#deep-links)
- [Differences from Desktop](#differences-from-desktop)

---

## Shelter Navigator (Evacuation Assist)

Added in v3.2.0. This Japan-specific feature detects weather hazard information from the Japan Meteorological Agency (via bsaf-kikikuru-bot) and guides you to the nearest designated evacuation shelter. Shelter data (from the Geospatial Information Authority of Japan) is bundled with the app, so **it works even without an internet connection**.

> **Important:** This feature provides supplementary information based on JMA hazard levels. It does not represent official municipal evacuation orders. Always check official evacuation instructions from your local municipality.

### Enabling the Feature

Shelter Navigator is off by default. To enable it:

1. Go to the **Profile** tab → tap the **Settings** icon.
2. Scroll to the **Evacuation Assist** section.
3. Turn on the **Enable Evacuation Assist** toggle.
4. If bsaf-kikikuru-bot is not yet registered, a confirmation dialog appears. Tap **Enable** to automatically register and follow bsaf-kikikuru-bot via BSAF.

You can optionally select your **Prefecture (manual)** to specify your area. Leaving it on "Auto (from location)" uses your current location. Manual selection is recommended for offline use.

### Warning Banner

When Evacuation Assist is enabled and a weather warning is received for your configured prefecture (or current location), a banner appears at the bottom of the screen.

![Warning banner display](./images/iOS_evacuation_001.png)

- **Level 3 (yellow):** Weather warning level information issued
- **Level 4 (red):** Check evacuation information
- **Level 5 (pink):** Secure safety immediately

Tap **View Shelters** on the banner to open the nearest shelters list. The banner clears automatically when the alert is cancelled or after 6 hours.

### Nearest Shelters List

Shelters are listed in order of distance from your current location. Each entry shows the straight-line distance and supported hazard types (flood, landslide, earthquake, etc.) as tags.

![Nearest shelters list](./images/iOS_evacuation_002.png)

Use the **Hazard Type** picker to filter shelters. The filter is automatically set based on the type of warning received.

Tap a shelter to view its details, where you can choose **Navigate with Maps** (walking directions in Apple Maps) or **Simple Nav (Compass)**.

### Simple Nav (Compass)

A compass-based navigator that works without an internet connection. It uses the device's magnetic sensor to show an arrow pointing toward the selected shelter and displays the straight-line distance in real time.

![Simple Nav (Compass)](./images/iOS_evacuation_003.png)

- Walk in the direction of the arrow — the distance decreases as you get closer.
- If compass accuracy is low, move your device in a figure-8 pattern to calibrate.
- When offline, Apple Maps navigation is unavailable, making this the primary navigation method.

### Offline Use

Shelter data is bundled with the app, so the following features work even in airplane mode:

| Feature | Offline |
|---------|---------|
| Nearest shelters list | Available |
| Simple Nav (Compass) | Available |
| Navigate with Maps | Unavailable (requires internet) |
| Auto prefecture detection | Unavailable (use manual setting) |

> **Note:** Shelter data is sourced from the Geospatial Information Authority of Japan (GSI) Designated Emergency Evacuation Sites. Data may not be fully up to date. Check with your local municipality for the latest information.

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
| Shelter Navigator | Guides to nearest evacuation shelters during weather warnings (works offline) |
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
