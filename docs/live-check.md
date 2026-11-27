# Checking that the live site works

Two tools: an automatic check that runs by itself, and a ten-minute check on two real phones for what a machine cannot see.

## 1. The automatic check

`scripts/live-check.mjs`, run by the workflow « Live site check » after every publication of the site, every morning, and
on demand (GitHub → Actions → Live site check → Run workflow). The result is a short list at the top of the run; a red
run means something is broken, and GitHub e-mails the account that owns the repository.

What it does, on https://upzoneapp.fr/ :

- opens every public page as an Android phone, an iPhone and a computer, and reports any script error, missing file or server error;
- follows every link and file those pages point to;
- on the sign-in screen: « Connexion » leads to the e-mail field, the server answers, a wrong password shows a message;
- with test accounts: signs in, opens every screen their buttons lead to, signs out.

It only looks. The single form it sends is the sign-in form. It never scans a QR code, writes a message, says hello,
pays, reports, blocks or deletes.

What it cannot see: the installed phone app, a notification arriving on a phone, the camera, the administration behind
its sign-in (an administrator password does not belong in an automatic check).

### Test accounts (optional, done once by the operator)

Without them the check still covers the public pages and the sign-in screen.

1. In the app, create three accounts with **fictitious** people and addresses the operator controls: one personal account
   (profile completed), one professional account, one event account. Use long passwords used nowhere else.
2. GitHub → repository → Settings → Secrets and variables → Actions → New repository secret, six times:
   `LIVE_CHECK_MEMBER_EMAIL`, `LIVE_CHECK_MEMBER_PASSWORD`, `LIVE_CHECK_PRO_EMAIL`, `LIVE_CHECK_PRO_PASSWORD`,
   `LIVE_CHECK_EVENT_EMAIL`, `LIVE_CHECK_EVENT_PASSWORD`.
3. Never write these in a file, a chat or a message: a GitHub secret cannot be read back, even though the repository is public.
4. Do not protect these three accounts with a second step (authenticator app): the check could not get past it.
   For that reason, never give them administrator rights.

These accounts count as members in the administration figures. Delete them before the public release, or keep them and
say so in the privacy policy review.

## 2. Notifications: did they leave the server?

Administration → Plus → Notifications (installed by `db/2026-11-27-push-log.sql`). For each send: the date, the kind,
how many browsers and phones it was addressed to, and what the sending service answered. No member, no name, no text.
« Accepté » means accepted by the sending service; the phone's own settings decide whether it is shown.

## 3. Ten minutes on two real phones

Two people, each with a personal account, in the same place, both with the installed app. Tick each line.

About notifications (lines 4, 5 and 11): until push for the phone apps is switched on (`docs/app-push-setup.md`), a
notification only arrives in a browser, or in the site added to the home screen, where notifications were allowed in
« Réglages ». In the app installed from Google Play, expect lines 4 and 5 to show nothing on the lock screen for now;
the hello and the answer must still appear inside the app.

| # | Do this | Expect |
|---|---------|--------|
| 1 | Both close the app completely and open it again | The app opens; no error message |
| 2 | Both scan the QR code of the place | Each arrives on « Ici en ce moment » |
| 3 | A takes the pass (simulation) | A sees photos and first names instead of silhouettes |
| 4 | A opens B's profile and says hello | B gets a notification within about a minute; the phone shows no name and no text |
| 5 | B accepts and answers | The conversation opens on both phones; A gets a notification |
| 6 | Each sends two messages | They arrive in order on the other phone |
| 7 | A closes the app completely and opens it again | A lands directly on « Ici en ce moment » |
| 8 | B ends the conversation with a reason | A sees it ended, in neutral words; nobody can write any more |
| 9 | A blocks B (from the profile) | B disappears from A's list, and A from B's |
| 10 | Réglages → Notifications → « Envoyer un test » on each phone | A notification about 5 seconds later |
| 11 | Administration → Plus → Notifications | The sends of steps 4 and 5 are listed, « accepté » |

With a professional account on a third phone (or after « Passer à … »), in the same place:

| # | Do this | Expect |
|---|---------|--------|
| 12 | The pro scans, opens « Ma fiche pro », taps « Être visible ce soir (simulation) » | The pro appears under « Talents ici » for A |
| 13 | A sends a request to the pro | The pro sees it under « Demandes reçues » and can answer |
| 14 | The pro tries to answer four times in a row | The fourth message is refused until A answers |
| 15 | The pro's visit ends (or the pro leaves the place) | The pro is no longer listed under « Talents ici » |

Write down, for any line that fails: the phone (brand and model), what was tapped, what the screen showed, and a screenshot.
