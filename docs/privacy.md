# Privacy Policy — Unbound

**Effective date:** November 11, 2026

This policy explains what happens to data when you play **Unbound**
(package `com.adbkv.chainpop`), published on Google Play by **MindGlow Studios**
(ADBKV), an independent developer based in India. For the purposes of the EU and
UK General Data Protection Regulation (GDPR), we are the **data controller** for
the processing described here. Contact details are in §15.

Unbound has **no account system**. There is no sign-up, no login, and no profile
on our servers. You can play the entire game offline. We do not sell your data.

We do, however, use third-party services that collect data — advertising,
analytics, crash reporting, purchase management and Google Play Games. This
policy names each one. **We do not claim that we collect no data.**

---

## 1. Game data stored on your device

All game progression is stored locally on your device in a Hive database:

- Stars earned per level and the highest level unlocked, per difficulty track
- Your selected difficulty and game settings (sound, haptics, high contrast, aim
  guide, ambient motion)
- Tutorial completion state
- Daily challenge results and which past days you have unlocked
- Achievement counters and progress
- A cached flag recording whether you have purchased the ad-free upgrade

None of this is uploaded to us. We operate no game server and hold no copy of
your progress.

---

## 2. Advertising — Google AdMob (Google Mobile Ads)

Unbound shows banner, interstitial and rewarded video ads through **Google AdMob**
unless you have purchased the ad-free upgrade, which disables ads entirely.

AdMob is an **independent third party**: it uses data for its own advertising and
measurement purposes across its network, not solely on our behalf. Through AdMob,
the following may be collected and shared: your **advertising ID (AAID)**, IP
address, user agent, device and app information, coarse geographic region derived
from your IP address, and your interactions with ads.

Ad content in Unbound is capped at Google's **"G"** (general audiences) content
rating.

### Consent (GDPR / EU, UK and other consent regions)

Before the ads SDK is initialised, the app runs the **Google User Messaging
Platform (UMP)** consent flow — a Google-certified consent management platform
using the IAB Transparency & Consent Framework. In the EEA, UK and Switzerland it
shows a consent message with **Consent**, **Do not consent** and **Manage
options**. Declining does not stop you playing: you may still see
non-personalised ads, which use only limited data. If the app cannot establish
your consent status, ads are not shown for that session.

You can change your choice at any time: **Settings → Privacy & Ads → Manage ad
choices** (shown where a consent choice applies to you). The same screen offers a
**Privacy rights** summary and a link to this policy.

---

## 3. Analytics — Firebase Analytics

We use **Google Firebase Analytics** (Firebase project `unbound-667b8`) to
understand how the game is played and where players get stuck.

Firebase Analytics acts as a **service provider processing on our behalf**.
Events recorded include: session start and end, tutorial start/complete, level
start, complete, fail, retry and abandon, hint and undo use, ad offers shown,
started, completed and failed, interstitials shown and closed, purchase started,
succeeded and failed, premium restored, daily challenge opened and completed, and
achievement unlocks. Firebase also records device model, OS version, app version,
and derives approximate region from your IP address.

Identifier used: the **Firebase App Instance ID**, a random ID for this
install of the app. The app shows its first characters as your **Support ID**
(see §9). Analytics is configured not to collect your device's advertising ID
and not to use ad personalization signals. We do not enable Google Signals or
link analytics to Google advertising products.

**Analytics is off until consent is checked.** The app starts with analytics
collection disabled. In the EEA, UK and Switzerland it is switched on only if
you consented to storing and accessing information on your device in the
consent message above; elsewhere it is switched on once the consent check has
run. You can turn analytics off at any time with **Settings → Privacy & Ads →
Share usage analytics**.

---

## 4. Crash reporting — Firebase Crashlytics

We use **Firebase Crashlytics** to detect and fix crashes. When the app crashes
or hits a handled error, a report is sent containing the stack trace, device state,
OS and app version, and a **Crashlytics installation UUID**. We do not
deliberately attach names, email addresses or other direct identifiers to crash
reports. Crashlytics is a service provider processing on our behalf, and crash
data is retained by Google for roughly 90 days. Crash reports are **not linked
to your Support ID** and cannot be deleted individually; they expire on their
own after that period.

Crash collection is disabled in development builds and enabled in released builds.

---

## 5. Purchases — RevenueCat and Google Play Billing

The optional one-time **ad-free upgrade** ("Unbound Premium") is sold through
**Google Play Billing** and managed through **RevenueCat**, both acting as service
providers on our behalf.

- RevenueCat receives your purchase and receipt data and assigns an **anonymous
  App User ID**. It is not linked to a name or email by us.
- **Your payment details never reach the app.** Card and payment-method handling
  happens entirely inside Google Play's checkout.
- "Restore purchases" in Settings re-queries your entitlement from the store.

---

## 6. Achievements — Google Play Games Services

On Android, Unbound integrates **Google Play Games Services** so achievements sync
to your Google Play Games profile. This is **optional**: the app attempts sign-in
in the background at startup, and if you are not signed in the game runs entirely
locally — the full achievement catalogue still works and remains browsable
on-device.

When you are signed in, Play Games provides the app with your **Play Games player
ID and display name**, and the app sends your **achievement unlock state and step
counts** to Google, which stores them against your Google account. Google Play
Games Services is operated by Google in connection with our Play developer
account.

We do not read your friends list, we do not post on your behalf, and the game
ships no leaderboards.

---

## 7. Permissions

The app uses network access (for ads, purchases, analytics and crash reports),
**notifications** (optional daily reminders, which you can turn off in Settings
and which Android asks you to allow), and the **advertising ID** permission
used by AdMob. It also uses ordinary system permissions declared by its SDKs
(vibration for haptics, keeping reminders scheduled after a restart, and
background upload of analytics/crash data). Location, contacts, storage,
microphone, camera, phone and SMS permissions are explicitly removed from the
build. We do not collect precise location.

---

## 8. Retention

- **On your device:** local game data stays until you clear it, clear the app's
  storage, or uninstall.
- **Firebase Analytics:** 2 months.
- **Firebase Crashlytics:** approximately 90 days.
- **RevenueCat:** purchase records retained until deletion is requested.
- **AdMob and Google Play:** per Google's own policies, linked below.

---

## 9. Your controls and choices

### "Reset Game Data" (in-app)

**Settings → Reset Game Data** (also reachable by pressing and holding the Play
button on the main menu), then confirm in the dialog. It clears the local game database — all
stars, unlocks, difficulty progress and settings on this device.

Be clear about what it does and does not do:

- It clears **local device data only**.
- It does **NOT** delete data already held by Google, Firebase, AdMob, RevenueCat
  or Google Play Games. That data lives on their systems, not ours, and this
  button cannot reach it.
- Your **ad-free purchase entitlement deliberately survives the reset** — you
  should never lose something you paid for by resetting your progress. The cached
  premium flag is rewritten immediately after the local data is cleared.
- Local reset cannot be undone.

### Other controls

- **Manage ad choices** (Settings → Privacy & Ads) — revisit or withdraw your
  ads consent at any time. Withdrawing is as easy as giving it.
- **Share usage analytics** (Settings → Privacy & Ads) — turn analytics off or
  back on.
- **Privacy rights** (Settings → Privacy & Ads) — plain-language summary plus a
  direct contact link.
- **Buy the ad-free upgrade** — removes all ads, which removes the AdMob data flow.
- **Google account controls** — your Google Ads settings, and Play Games account
  and data controls, are managed by Google at
  [myaccount.google.com](https://myaccount.google.com).
- **Uninstall** — removes all locally stored game data.

### Your Support ID

**Settings → Privacy & Ads → Privacy rights** shows a short **Support ID** for
this install (the start of its Firebase App Instance ID) with a copy button. The
"Request a copy of my data" and "Other request" buttons there open an email to
us pre-filled with the full Support ID and, if you have one, your RevenueCat
purchase ID, so we can find your data at our providers. If you declined analytics
consent, there is no analytics ID and the screen says "None": we hold no
analytics data linked to this install. Turning "Share usage analytics" off
stops new collection but keeps the ID, so you can still use it to ask us to
delete data collected before you turned it off.

### "Delete my data" (in-app)

**Settings → Privacy & Ads → Privacy rights → Delete my data** (from the home
screen), then confirm. It:

- erases all local game data on this device (the same data as "Reset Game Data");
- **resets your analytics ID**, so anything collected later is not linked to
  what was collected before, and deletes unsent crash reports;
- keeps your **ad-free purchase** and your **privacy choices** (your analytics
  switch and ad consent), so deleting data never quietly turns analytics back
  on or takes back something you paid for;
- then offers to send us a **pre-filled deletion request** carrying your
  previous Support ID and purchase ID.

Copies already held by Google Analytics and RevenueCat can't be deleted from
your phone. When we receive the request we delete them at those providers:
Analytics data by App Instance ID, and your RevenueCat customer record. Google
Play keeps its own order history under Google's policies. Achievements are
managed in your Google Play Games profile at
[myaccount.google.com](https://myaccount.google.com).

### Requesting deletion by email

You can also email us at the address in §15 without using the app. Include your
**Support ID** (and purchase ID if you have one) so we can locate your records;
a Google Play order ID also helps for purchase records.

---

## 10. Legal bases (EEA / UK)

- **Advertising (AdMob):** your **consent**, collected through the UMP message.
  Non-personalised ads where you decline rely on our **legitimate interest** in
  funding a free game.
- **Analytics (Firebase Analytics):** your **consent**.
- **Crash reporting (Crashlytics):** our **legitimate interest** in keeping the
  game working. You may object by contacting us.
- **Purchases (RevenueCat, Google Play Billing):** **performance of a contract**
  — delivering the upgrade you bought.
- **Achievements (Play Games):** **performance of a contract**, only when you
  choose to sign in.

## 11. International transfers

Our service providers (Google, Firebase and RevenueCat) are based in, or
process data in, the **United States** and other countries. These transfers
rely on the European Commission's Standard Contractual Clauses and, where
applicable, the EU–US Data Privacy Framework, as set out in those providers'
own terms.

## 12. Your rights

Depending on where you live, you have the right to **access**, **correct**,
**delete** or **port** your personal data, to **restrict** or **object to**
processing, and to **withdraw consent** at any time without affecting earlier
processing. In the EEA and UK you also have the right to **complain to your
local data protection authority**.

**US residents** (including California, Virginia, Colorado and other states
with privacy laws): we do not sell personal information for money. AdMob's use
of your data for personalised ads may count as "sharing" or "targeted
advertising" under those laws. You can opt out using your device's **Delete
advertising ID / Opt out of Ads Personalization** setting, or contact us.

Because the app has no account, include your **Support ID** (Settings →
Privacy & Ads → Privacy rights) so we can locate your records. We answer
requests within 30 days.

## 13. Children

Unbound is intended for players aged **13 and over** and is not directed to
children. We do not knowingly collect personal data from children under 13. If you
believe a child under 13 has provided data through this app, contact us and we
will act on it.

---

## 14. Third-party policies

- Google (AdMob, Play Billing, Play Games): https://policies.google.com/privacy
- Firebase (Analytics, Crashlytics): https://firebase.google.com/support/privacy
- RevenueCat: https://www.revenuecat.com/privacy/

---

## 15. Contact

Privacy questions and data requests: **adbkv.apps@gmail.com**

Data controller: MindGlow Studios (ADBKV), India.

> Kept in sync with `ChainPopLegal.supportEmail` in
> `lib/config/chain_pop_legal.dart`. If that constant changes, change this line
> too. The hosted copy of this policy
> (`https://mindglowstudios.web.app/unbound-privacy-policy`) must publish the same
> address — Play cross-checks the in-app link, the Console field and the page.

---

## 16. Changes

We may update this policy. Material changes will be reflected in a revised
effective date at the top of this document and in the hosted copy.
