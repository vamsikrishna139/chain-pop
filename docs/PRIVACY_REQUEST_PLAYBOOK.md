# Privacy request playbook — Unbound

How to handle access and deletion requests that arrive at
**adbkv.apps@gmail.com** with the subject `Privacy Inquiry - Unbound`.

**Deadline: reply within 30 days of receipt** (the app and policy both promise
this). Log every request below.

## What a request contains

The in-app buttons pre-fill:

```
Request type: Access / Delete / Other
Support ID: <Firebase App Instance ID, or "none">
Purchase ID: <RevenueCat App User ID, e.g. $RCAnonymousID:…, or "none">
App version: … · Platform: …
(Optional) Google Play order ID: GPA.…
```

- `Support ID: none` means the player declined analytics consent, so there is
  no Analytics data to find. A player who only turned the in-app analytics
  switch off still has an ID, and data from before the opt-out is linked to it.
- After an in-app "Delete my data", the email carries the **previous** IDs (the
  analytics ID is reset on the device). Use them as given.
- If someone writes without IDs, ask for the Support ID (Settings → Privacy &
  Ads → Privacy rights) or a Google Play order ID. Don't ask for anything else.

## Where the data lives

| Provider | Look up by | Delete how | Notes |
|---|---|---|---|
| Google Analytics 4 (Firebase `unbound-667b8`) | `app_instance_id` = Support ID | Explore → User explorer → filter *Effective user ID* = the ID → open it → **Delete user** (person-with-× icon, not the trash can) | Gone from reports in ~72 h, fully deleted in ~63 days |
| RevenueCat | App User ID (`$RCAnonymousID:…`) | Search the ID (it may match as an alias) → customer page → **Manage → Delete Customer** | Only RevenueCat's copy. Google Play keeps its order history |
| Crashlytics | — | Can't delete per user | Not linked to the Support ID; expires after ~90 days |
| Google Play Games | — | The player manages it at myaccount.google.com | We hold no copy |
| AdMob | — | The player resets or deletes their advertising ID on the device | Google is the controller for ad data |

## Access request: reply template

> Subject: Re: Privacy Inquiry - Unbound
>
> Hi,
>
> Thanks for your request. Here is the data we hold for Support ID `<ID>`:
>
> - **Gameplay analytics** (Google Analytics, kept for 2 months): `<summary or attached export from User explorer>`
> - **Purchase record** (RevenueCat): `<present: product, date / none>`
> - **Crash reports**: not linked to your Support ID, and deleted automatically after about 90 days.
> - **Game progress**: stored only on your device; we have no copy.
>
> Achievements are in your Google Play Games profile (myaccount.google.com). Ad data is handled by Google: see policies.google.com/privacy.
>
> — Unbound support

## Deletion request: reply template

Step-by-step deletion for a given ID: [DELETE_MY_DATA_RUNBOOK.md](DELETE_MY_DATA_RUNBOOK.md).

> Subject: Re: Privacy Inquiry - Unbound
>
> Hi,
>
> We've deleted the data linked to Support ID `<ID>`:
>
> - **Google Analytics**: deletion requested `<date>`. It leaves reports within about 3 days and is fully erased by Google within about 63 days.
> - **RevenueCat purchase record**: `<deleted / none found>`. If you bought the ad-free upgrade, Google Play still keeps its own order history, and "Restore purchases" will still work because it checks with Google Play.
> - **Crash reports**: not linked to you; they expire after about 90 days.
>
> If you used "Delete my data" in the app, the data on your device is already gone.
>
> — Unbound support

## Request log

| Received | Type | Support ID (first 8) | Done | Replied |
|---|---|---|---|---|
| | | | | |
