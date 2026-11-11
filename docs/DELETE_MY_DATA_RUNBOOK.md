# Runbook: deleting a player's data by ID

Use this when a **Delete** request arrives at `adbkv.apps@gmail.com` with the
subject `Privacy Inquiry - Unbound`, whether it came from the in-app "Send
deletion request" button or was written by hand.

**Deadline:** reply within **30 days** of receiving the email.
**Time needed:** about 10 minutes per request.
**Reply templates** are in [PRIVACY_REQUEST_PLAYBOOK.md](PRIVACY_REQUEST_PLAYBOOK.md).

---

## 0. What you need from the email

| Field in the email | What it is | Example |
|---|---|---|
| `Support ID` | Firebase **App Instance ID** (32 hex characters) | `7640e7a5c283234b5f0a70ec522c3e87` |
| `Purchase ID` | RevenueCat **App User ID** | `$RCAnonymousID:44d1d6a443c14c93b72aeb855242913f` |
| `Google Play order ID` (optional) | Play order number | `GPA.3312-4567-8901-23456` |

- **The email from the in-app Delete flow carries the previous IDs.** The app
  has already reset its analytics ID, so the Support ID now shown on the
  player's phone is a different one. Use the IDs in the email.
- **`Support ID: none`:** the player declined analytics consent, so there is
  no Analytics data. Skip step 2.
- **`Purchase ID: none`:** the player has no RevenueCat record. Skip step 3,
  unless they give a Play order ID (see step 3b).
- **No IDs at all** (a hand-written email): reply asking for the Support ID
  (Settings → Privacy & Ads → Privacy rights) or a Google Play order ID. Ask for
  nothing else. The 30 days run from when you have enough to act on.
- **Several requests from one sender with different IDs:** that's normal (a
  reinstall or a new phone means a new ID). Delete every ID they send.

---

## 1. Log the request

Add a row to the **Request log** in `PRIVACY_REQUEST_PLAYBOOK.md`: date
received, type `Delete`, and the first 8 characters of the Support ID. Never
write the full IDs or the sender's email into the repo.

In Gmail, label the thread `privacy` (the filter should already do this) and
star it until you've replied.

---

## 2. Google Analytics (Firebase project `unbound-667b8`)

### 2a. In the browser (default)

1. Open **analytics.google.com** and select the **Unbound** GA4 property (the one
   linked to Firebase `unbound-667b8`).
2. Go to **Explore**, then open a **User explorer** exploration. If none exists,
   create one from the **User explorer** template.
3. Set the date range to the **largest allowed** (retention is 2 months), so
   older activity isn't hidden.
4. Search for the full **Support ID** in the search box. App users are listed
   by **App-instance ID**.
5. Open the matching row. In the user's activity view, use the **Delete user**
   action (trash icon, top right) and confirm.
6. **If no row matches:** the ID has no data still within retention, or the
   player never sent any analytics. That counts as done. Write "no data
   found" in the log.

### 2b. By API (fallback, or for bulk requests)

GA's **User Deletion API** accepts an App Instance ID directly:

```
POST https://www.googleapis.com/analytics/v3/userDeletion/userDeletionRequests:upsert
Authorization: Bearer <OAuth token with analytics.user.deletion scope>
Content-Type: application/json

{
  "kind": "analytics#userDeletionRequest",
  "id": { "type": "APP_INSTANCE_ID", "userId": "<full Support ID>" },
  "firebaseProjectId": "unbound-667b8"
}
```

A `200` response with a `deletionRequestTime` means it was accepted. Check the
exact request against Google's current docs the first time you use it.

### What to expect

- The user drops out of reports within **about 72 hours**.
- Google erases the data from its systems within **about 63 days**.
- No confirmation email comes from Google. Your log entry is the record.

---

## 3. RevenueCat

### 3a. By Purchase ID (default)

1. Open **app.revenuecat.com**, select the **Unbound** project, then go to
   **Customers**.
2. Paste the full **Purchase ID** (including `$RCAnonymousID:`) into the search
   box.
3. Open the customer. Note whether they have the ad-free entitlement; you
   mention it in the reply.
4. Use **Delete customer** (in the customer page's actions menu, `⋯`) and
   confirm.

### 3b. By Play order ID (no Purchase ID given)

Search **Customers** for the `GPA.…` order ID or the purchase token. If a
customer matches, delete it as in 3a.

### 3c. By API (fallback)

```
DELETE https://api.revenuecat.com/v1/subscribers/<URL-encoded Purchase ID>
Authorization: Bearer <RevenueCat secret API key, sk_…>
```

URL-encode the ID: `$` becomes `%24` and `:` becomes `%3A`. Keep the secret key
out of the repo and out of chat.

### What to expect

- This deletes **RevenueCat's copy only**. **Google Play keeps the order
  history** under Google's own policy, and we can't delete it.
- If the player bought ad-free, "Restore purchases" still works afterwards:
  RevenueCat re-reads the purchase from Google Play and creates a new,
  anonymous customer. Say so in the reply so nobody worries about losing what
  they paid for.

---

## 4. Things you don't need to do (and why)

| Data | Why no action |
|---|---|
| **Crashlytics** | Crash reports aren't linked to the Support ID and can't be deleted per user. They expire after about 90 days. The in-app Delete already dropped unsent reports. |
| **On-device game data** | The in-app Delete already wiped it. If the request was a hand-written email, tell the player to use Delete my data, or to uninstall. |
| **AdMob** | Google is the controller for ad data. The player controls it through the device's ad ID settings (reset or delete the advertising ID). |
| **Google Play Games** | Achievements live on the player's Google account. They manage them at myaccount.google.com. We hold no copy. |
| **Our own servers** | We have none. |

---

## 5. Reply and close

1. Reply on the same Gmail thread using the **Deletion request** template in
   `PRIVACY_REQUEST_PLAYBOOK.md`. Fill in:
   - the Analytics deletion date, or "no data found";
   - the RevenueCat result (`deleted` / `none found`), plus the Restore
     purchases note if they had ad-free.
2. In the Request log, fill in **Done** (date) and **Replied** (date).
3. Remove the star from the Gmail thread.

---

## Quick checklist

```
[ ] Logged (date, type, Support ID first 8)
[ ] GA4: user deleted by Support ID, or "no data found"
[ ] RevenueCat: customer deleted by Purchase ID / order ID, or "none found"
[ ] Replied on the thread (within 30 days)
[ ] Log updated: Done + Replied
```

---

## First-time setup (once, before the first real request)

- [ ] Practise steps 2a and 3a end to end on your own Pixel's IDs.
- [ ] Confirm GA4 retention is **2 months**, Google Signals is **off**, and
      there's **no Ads link**. The privacy policy states all three.
- [ ] Create the Gmail filter: subject `Privacy Inquiry - Unbound` gets the
      label `privacy`.
- [ ] If you'll use the APIs, note where the OAuth client and RevenueCat
      secret key live, outside the repo.
