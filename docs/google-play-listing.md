# Google Play: store page and forms (prepared 20 November 2026)

Package `fr.upzoneapp.app`, created in Google Play Console on 20 November 2026 (free app, default language French).
Everything below is a draft to copy into Play Console → « Terminer la configuration de votre appli ». The account
holder (the operator) is the one who declares it to Google: read each answer before saving, and correct anything that
is no longer true on the day. Answers describe the app as it is in the repository on this date.

Not in this file, on purpose (the repository is public): the reviewer's test account and password, the operator's
legal name and address, the support e-mail until the operator has chosen it.

## Links to give
- Privacy policy: https://upzoneapp.fr/confidentialite.html
- Account deletion: https://upzoneapp.fr/supprimer-mon-compte.html
- Website: https://upzoneapp.fr/
- Support e-mail: to be chosen by the operator (it is shown publicly on Google Play).

## Store listing (Fiche Play Store principale)

**App name** (30 max): `UPZONE`

**Short description** (80 max), French:
`Rencontre les personnes présentes dans ton lieu. Scanne, dis bonjour.`

English:
`Meet the people in the same venue as you. Scan the QR code and say hello.`

**Full description**, French:

```
UPZONE te permet de faire connaissance avec les personnes présentes dans le même lieu que toi : un bar, un club, un restaurant, un événement.

COMMENT ÇA MARCHE
1. Scanne le QR code affiché dans le lieu.
2. Dis bonjour à une personne présente.
3. Si elle accepte, la conversation s’ouvre. Vous discutez tant que vous êtes tous les deux sur place.

LE RESPECT D’ABORD
• Tu n’es visible que dans le lieu où tu as scanné, et seulement pendant ta visite.
• Personne ne doit de réponse à personne. Un refus ou un silence est une réponse.
• Avant le pass, les autres ne voient qu’une photo floutée, ton département et ta tranche d’âge.
• Fermer une conversation, bloquer et signaler sont disponibles pour tout le monde, gratuitement, à tout moment.
• Aucun selfie obligatoire. Ta date de naissance reste privée.

POUR LES PROFESSIONNELS ET LES ÉVÉNEMENTS
• Professionnels (DJ, photographe, coach, coiffeur…) : une fiche visible par les personnes présentes dans le même lieu que vous.
• Événements et lieux : un QR code à l’entrée, des annonces pour les personnes présentes. Vous ne voyez que des chiffres, jamais les profils.

À SAVOIR
• Réservé aux adultes (18 ans et plus).
• Pendant la phase de test, les pass sont simulés : rien n’est débité.
• UPZONE ne remplace ni le personnel du lieu ni les secours. En cas d’urgence en France, appelle le 112.
```

English:

```
UPZONE lets you meet the people who are in the same venue as you: a bar, a club, a restaurant, an event.

HOW IT WORKS
1. Scan the QR code displayed in the venue.
2. Say hello to someone who is there.
3. If they accept, the conversation opens. You chat for as long as you are both there.

RESPECT FIRST
• You are only visible in the venue where you scanned, and only during your visit.
• Nobody owes anyone a reply. A refusal or a silence is an answer.
• Before the pass, others only see a blurred photo, your département and your age range.
• Ending a conversation, blocking and reporting are available to everyone, free of charge, at any time.
• No selfie required. Your date of birth stays private.

FOR PROFESSIONALS AND EVENTS
• Professionals (DJ, photographer, coach, hairdresser…): a sheet seen by the people in the same venue as you.
• Events and venues: a QR code at the entrance, announcements for the people present. You only see numbers, never profiles.

GOOD TO KNOW
• Adults only (18 and over).
• During the test phase, passes are simulated: nothing is charged.
• UPZONE does not replace venue staff or the emergency services. In an emergency in France, call 112.
```

Before the public release: remove the « phase de test / passes are simulated » line if payments have become real.

**Graphics**
- Icon 512 × 512: `public/assets/upzone-icon-512.png`.
- Feature graphic 1024 × 500: to make (logo on the cream background with « Un même lieu. De nouvelles rencontres. »).
- Phone screenshots (2 minimum, 4 to 6 advised), taken on a real phone with test accounts only, no real person:
  the welcome screen, « Le lieu » during a visit, the veiled list of people, a conversation, « Profil », « Mes lieux ».

**Category**: Application → `Rencontres` (Dating). Tags: leave Google's suggestions that fit.

## App content (Contenu de l'appli)

**Privacy policy**: the link above.

**App access (Accès à l'appli)**: « Tout ou partie des fonctionnalités sont limitées ». Give Google a test account
(e-mail and password, without two-step verification) and say in the instructions:
« Sign in with e-mail and password. To join a venue without being on site, open this link in the app: <test venue link>. »
Create a test venue and a long-lived QR link for the review. Keep the credentials out of the repository.

**Ads (Annonces)**: No, the app contains no ads.

**Content rating (Classification du contenu)**: category « Réseau social / communication » (or « Rencontres » if
offered). Answer truthfully:
- Users can interact and exchange messages: yes.
- Users can share user-generated content (profile photo, text): yes; reporting and blocking exist: yes; moderation: yes.
- Shares the user's precise location with other users: no (presence comes from the QR code scanned, not from GPS).
- Violence, sexual content, drugs, gambling, profanity provided by the app itself: no.
- Digital purchases: no for now (passes are simulated).

**Target audience (Audience cible)**: 18 and over only. The app is not designed for children.

**News app**: no. **Health**, **Financial features**, **Government**: no.

**Data safety (Sécurité des données)**
- Does the app collect or share user data: yes (collects). Shared with third parties: no (hosting, e-mail/SMS sending and
  on-request translation are service providers working for the operator).
- Encrypted in transit: yes. Users can request deletion: yes (link above).
- Data collected, all for « App functionality » and « Account management »; safety items also for « Fraud prevention,
  security and compliance »:

| Google category | Data | Required | Notes |
|---|---|---|---|
| Personal info · Name | display name | required | shown to people in the same venue |
| Personal info · Email address | sign-in e-mail | required unless phone sign-in | never shown to members |
| Personal info · Phone number | sign-in phone | optional | only if phone sign-in is used |
| Personal info · Other info | date of birth (age), département, height | date of birth required, height optional | birth date private; age shown |
| Personal info · Sexual orientation | « Qui souhaites-tu voir ? » with gender | optional, explicit consent | private, only filters the member's own list |
| Photos and videos · Photos | profile photo | required for person accounts | visible in the venue after the pass; blurred before |
| Messages · Other in-app messages | hellos and conversations | when used | readable by the two members; moderation sees a conversation only with a report |
| App activity · Other user-generated content | bio, reports, feedback, pro sheet, announcements | when used | |
| App activity · App interactions | venue visits (place, start, end) | required to use a venue | « Mes lieux », safety |
| Device or other IDs | notification subscription of the phone | optional | only if notifications are turned on; removed at sign-out |

- Not collected: precise or approximate device location, contacts, calendar, financial info (payments are simulated),
  health, audio, files, web browsing, advertising ID.
- If Google asks about « Advertising or marketing »: the optional « Alertes talents » tell a member, who turned them on,
  that a professional is in the venue. No data is given to advertisers. Declare it only if the form's wording covers
  in-app promotional messages; when in doubt, declare it.

**Government ID / age verification**: the app asks for the date of birth and refuses under 18; it does not check an
identity document.

## Dating apps: points Google looks at
- Adults only, stated in the listing and enforced at sign-up (date of birth).
- User-generated content: in-app reporting, blocking, and moderation with a way to remove users. All exist.
- Child safety standards: Google asks social and dating apps for published standards against child sexual abuse and
  exploitation, an in-app way to report, and a contact person. The terms of use forbid minors and the app has
  reporting; the operator still has to name the contact and publish the standards page if the console asks for it.
- Account deletion link: the page above.

## Closed test (Tests fermés)
- 12 testers at least, opted in for 14 days in a row, before « Demander à publier en production ».
- Each tester needs a Google account and an Android phone, and must accept the invitation link and install the app.
- Keep a short note of what testers reported and what was fixed: Google asks about it in the production request.
