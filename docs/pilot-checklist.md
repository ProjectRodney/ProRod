# P.Rod — Test pilote / Pilot test checklist

Version du 7 novembre 2026. Adresse de l’application / App address : https://projectrodney.github.io/ProRod/

**But / Goal.** Vérifier, sur de vrais téléphones et avec de vrais comptes, tout le parcours de P.Rod. Chaque ligne a un résultat attendu ; cochez **OK** ou décrivez le **problème** (capture d’écran bienvenue).
*Check the whole P.Rod journey on real phones with real accounts. Each line has an expected result; tick **OK** or describe the **problem** (a screenshot helps).*

## Préparation / Before you start

| Rôle / Role | Appareil / Device | Qui / Who |
|---|---|---|
| **A** — membre 1 / member 1 | téléphone / phone (iPhone ou Android) | |
| **B** — membre 2 / member 2 | un autre téléphone / another phone | |
| **V** — compte établissement / venue account | téléphone ou tablette du lieu / venue phone or tablet | |
| **Admin** — équipe / team | ordinateur / computer (`admin.html`) | |

- A, B et V utilisent chacun **une adresse e-mail différente**, réelle et consultable pendant le test. Ne jamais partager de mot de passe.
  *A, B and V each use a **different, real e-mail address** they can read during the test. Never share passwords.*
- A et B restent dans le même lieu physique. Prévoir environ 1 h 30. Noter l’heure de début : ……
  *A and B stay in the same physical place. Allow about 1 h 30. Start time: ……*
- Les paiements sont **simulés** (0 €, mention « SIMULATION ») : rien n’est jamais débité.
  *Payments are **simulated** (€0, labelled “SIMULATION”): nothing is ever charged.*
- Pendant le test, vérifier les spams si un e-mail n’arrive pas (l’expéditeur peut apparaître en `…brevosend.com`).
  *If an e-mail does not arrive, check spam (the sender may show as `…brevosend.com`).*

Légende / Key : ☐ OK · ☐ Problème / Problem → décrire / describe.

---

## 1. Installer / Install (A, B, V)

| # | Qui | Action | Attendu / Expected | OK | Problème / Problem |
|---|---|---|---|---|---|
| 1.1 | A, B, V | Ouvrir l’adresse de l’application dans le navigateur. *Open the app address in the browser.* | Page d’accueil P.Rod, choix FR / EN. *P.Rod welcome page, FR / EN choice.* | ☐ | |
| 1.2 | A, B, V | « Installer l’application » (Android : invite d’installation ; iPhone : suivre le guide Partager → Sur l’écran d’accueil). *“Install the app” (Android prompt; iPhone: follow the Share → Add to Home Screen guide).* | Icône P.Rod sur l’écran d’accueil ; l’application s’ouvre en plein écran. *P.Rod icon on the home screen; the app opens full screen.* | ☐ | |

## 2. Créer un compte / Create an account (A, B, V)

| # | Qui | Action | Attendu / Expected | OK | Problème / Problem |
|---|---|---|---|---|---|
| 2.1 | A, B | Créer un compte avec e-mail + mot de passe (12 caractères minimum), accepter les conditions. *Create an account with e-mail + password (12+ characters), accept the terms.* | Message demandant de confirmer l’adresse. *Message asking to confirm the address.* | ☐ | |
| 2.2 | A, B | Ouvrir l’e-mail de confirmation et cliquer le lien. Heure de réception : …… *Open the confirmation e-mail and click the link. Time received: ……* | E-mail reçu en moins de 5 min ; le lien ramène dans P.Rod, connecté. *E-mail within 5 min; the link brings you back into P.Rod, signed in.* | ☐ | |
| 2.3 | A, B | Choisir « compte personnel », compléter le profil : prénom, date de naissance, photo, bio, accepter les règles de communauté. *Choose “personal account”, complete the profile: name, birth date, photo, bio, accept the community rules.* | Écran d’accueil « Scanner le QR code du lieu ». *Home screen “Scan the venue’s QR code”.* | ☐ | |
| 2.4 | A | Essayer une date de naissance de moins de 18 ans (puis corriger). *Try a birth date under 18 (then correct it).* | Refusé : 18 ans minimum. *Refused: 18 minimum.* | ☐ | |
| 2.5 | V | Créer un compte, choisir « Compte établissement », décrire le lieu et envoyer la demande. *Create an account, choose “Venue account”, describe the venue and submit.* | Demande en attente de validation. *Application pending approval.* | ☐ | |

## 3. Administration (Admin)

| # | Qui | Action | Attendu / Expected | OK | Problème / Problem |
|---|---|---|---|---|---|
| 3.1 | Admin | Se connecter à `admin.html` (le rôle admin est posé dans Supabase par l’opérateur). *Sign in to `admin.html` (the admin role is set in Supabase by the operator).* | Enrôlement de la validation en deux étapes à la 1re connexion, puis code demandé à chaque connexion. *Two-step verification enrolment on first sign-in, then a code at every sign-in.* | ☐ | |
| 3.2 | Admin | Onglet des candidatures d’établissement : approuver la demande de V. *Venue applications tab: approve V’s application.* | Statut « approuvé » ; l’action apparaît dans le journal. *Status “approved”; the action appears in the audit log.* | ☐ | |

## 4. Le lieu / The venue (V)

| # | Qui | Action | Attendu / Expected | OK | Problème / Problem |
|---|---|---|---|---|---|
| 4.1 | V | Ouvrir « Votre compte établissement », régler la durée de session sur **30 minutes** pour le test (pour voir une fin de visite à l’étape 9.4). *Open “Your venue account”, set the session length to **30 minutes** for the test (so a visit ends during step 9.4).* | Réglage enregistré. *Setting saved.* | ☐ | |
| 4.2 | V | « QR code et invitations » → « Nouveau QR code », l’afficher à l’écran. *“QR code & invitations” → “New QR code”, show it on screen.* | QR code affiché, téléchargeable. *QR code shown, downloadable.* | ☐ | |
| 4.3 | V | Publier une annonce courte. *Post a short announcement.* | L’annonce apparaît pour les membres présents (étape 5). *The announcement shows to checked-in members (step 5).* | ☐ | |

## 5. Rejoindre le lieu / Join the venue (A, B)

| # | Qui | Action | Attendu / Expected | OK | Problème / Problem |
|---|---|---|---|---|---|
| 5.1 | A, B | « Scanner le QR code » et viser le QR de V (sinon « Saisir le code d’invitation à la place »). *“Scan the QR code” on V’s screen (or “Enter the invitation code instead”).* | « Lieu rejoint », nom du lieu, temps restant, annonce de V. *“Checked in”, venue name, time remaining, V’s announcement.* | ☐ | |
| 5.2 | A | « Voir qui est là ». *“See who is here”.* | B apparaît (prénom, âge, bio, photo) ; jamais V ; jamais la date de naissance. *B appears (name, age, bio, photo); never V; never the birth date.* | ☐ | |
| 5.3 | V | Regarder le tableau de bord du lieu. *Look at the venue dashboard.* | Nombre de présents = 2, sans liste de personnes. *Present count = 2, no list of people.* | ☐ | |

## 6. Présentation et consentement / Introduction and consent (A, B)

| # | Qui | Action | Attendu / Expected | OK | Problème / Problem |
|---|---|---|---|---|---|
| 6.1 | A | Sur le profil de B : « Envoyer une présentation » (un message court). *On B’s profile: “Send an introduction” (one short message).* | Avertissement « cette personne n’est pas obligée de répondre », puis envoi ; statut « en attente ». *Warning “this person is not obliged to respond”, then sent; status “waiting”.* | ☐ | |
| 6.2 | A | Essayer d’en envoyer une deuxième à B. *Try to send B a second one.* | Refusé. *Refused.* | ☐ | |
| 6.3 | B | Notification ; ouvrir « Présentations reçues ». *Notification; open “Introductions received”.* | La présentation de A, avec Répondre et accepter / Décliner / Bloquer / Signaler. La notification ne montre pas le texte. *A’s introduction with Reply & accept / Decline / Block / Report. The notification does not show the text.* | ☐ | |
| 6.4 | B | « Répondre et accepter » avec une réponse. *“Reply & accept” with a reply.* | Une conversation s’ouvre. *A conversation opens.* | ☐ | |

## 7. Pass et discussion / Pass and chat (A, B)

| # | Qui | Action | Attendu / Expected | OK | Problème / Problem |
|---|---|---|---|---|---|
| 7.1 | A | Ouvrir la conversation et la liste « Messages ». *Open the conversation and the “Messages” list.* | Réponse de B masquée : « Réponse masquée tant que vous n’avez pas de pass », aussi dans la liste. Écrire est refusé. *B’s reply hidden: “Reply hidden until you have a pass”, in the list too. Writing is refused.* | ☐ | |
| 7.2 | A | « Obtenir mon pass (simulation) ». *“Get my pass (simulation)”.* | « Pass activé (simulation, rien n’est débité) » ; la réponse de B devient lisible. *“Pass activated (simulation, nothing charged)”; B’s reply becomes readable.* | ☐ | |
| 7.3 | B | Obtenir aussi son pass, puis A et B échangent au moins deux messages chacun. *Also get a pass, then A and B exchange at least two messages each.* | Messages reçus en direct ; badge de non-lus. *Messages arrive live; unread badge.* | ☐ | |
| 7.4 | A | « Traduire » sur un message de B ; puis « Traduire mon message » sur un brouillon. *“Translate” on one of B’s messages; then translate a draft.* | Traduction FR ⇄ EN affichée ; le brouillon traduit est relu avant envoi. *FR ⇄ EN translation shown; the translated draft is reviewed before sending.* | ☐ | |
| 7.5 | A, B | « Proposer de se rencontrer » ; A dit oui, B dit oui. *“Propose to meet”; A says yes, B says yes.* | Suggestion d’un point de rencontre public (le comptoir). *A public meeting point is suggested (the counter).* | ☐ | |

## 8. Protections / Safety tools

| # | Qui | Action | Attendu / Expected | OK | Problème / Problem |
|---|---|---|---|---|---|
| 8.1 | B | Dans la conversation : « Signaler » (catégorie au choix, texte « TEST »). *In the conversation: “Report” (any category, text “TEST”).* | « Merci. Votre signalement a été envoyé. » A n’en voit rien. *“Thank you. Your report has been sent.” A sees nothing.* | ☐ | |
| 8.2 | Admin | Ouvrir le signalement, le classer (sans suspension). *Open the report, close it (no suspension).* | B reçoit « Votre signalement a été examiné ». *B gets “Your report has been reviewed”.* | ☐ | |
| 8.3 | A | « Terminer la conversation ». *“End the conversation”.* | B voit « Cette conversation est terminée », sans plus de détail ; plus personne ne peut écrire. *B sees “This conversation has ended”, nothing more; nobody can write.* | ☐ | |

## 9. Départ et nouvelle visite / Leaving and coming back (A, B)

| # | Qui | Action | Attendu / Expected | OK | Problème / Problem |
|---|---|---|---|---|---|
| 9.1 | — | Refaire 6.1–6.4 et 7.2–7.3 avec une **nouvelle** conversation (B se présente à A, par exemple). *Repeat 6.1–6.4 and 7.2–7.3 with a **new** conversation (B introduces themself to A, for example).* | Conversation ouverte, passes valides. *Conversation open, passes valid.* | ☐ | |
| 9.2 | B | « Quitter ce lieu ». *“Leave this place”.* | B disparaît de « Voir qui est là » chez A ; A peut relire l’historique mais ne peut plus écrire. *B disappears from A’s “See who is here”; A can read the history but cannot write.* | ☐ | |
| 9.3 | B | Rescanner le QR. *Scan the QR again.* | B est de retour ; si le pass de B est encore valide, l’écriture reprend des deux côtés. *B is back; if B’s pass is still valid, writing resumes on both sides.* | ☐ | |
| 9.4 | A | Attendre la fin du temps restant affiché chez A (30 min après son entrée), puis rescanner. Rescanner avant la fin garde la même visite et le même pass. *Wait until A’s time remaining runs out (30 min after checking in), then scan again. Scanning again before that keeps the same visit and pass.* | Nouvelle visite : l’ancien pass ne suffit plus ; A doit reprendre un pass pour écrire et lire les nouvelles réponses ; les anciennes restent lisibles. *New visit: the old pass no longer counts; A needs a new pass to write and read new replies; old ones stay readable.* | ☐ | |
| 9.5 | V | « Révoquer (termine les sessions en cours) » le QR. *“Revoke (ends current sessions)” on the QR.* | A et B sont sortis du lieu ; l’ancien QR ne fonctionne plus. *A and B are checked out; the old QR no longer works.* | ☐ | |

## 10. Refus et blocage / Refusal and block (A, B)

| # | Qui | Action | Attendu / Expected | OK | Problème / Problem |
|---|---|---|---|---|---|
| 10.1 | — | Nouveau QR (V), A et B rejoignent. Un 3e testeur **C** (facultatif) se présente à B ; B « Décliner ». *New QR (V), A and B join. An optional 3rd tester **C** introduces themself to B; B “Decline”.* | C voit seulement « en attente » ; C ne peut plus se présenter à B, ni ici ni ailleurs, sauf si B écrit en premier. *C only sees “waiting”; C can never introduce themself to B again, anywhere, unless B writes first.* | ☐ | |
| 10.2 | B | Sur le profil de A : « Bloquer ». *On A’s profile: “Block”.* | « Personne bloquée. » A et B ne se voient plus, dans aucun lieu ; leurs conversations disparaissent. *“Person blocked.” A and B no longer see each other, in any venue; their conversations disappear.* | ☐ | |

## 11. Connexion par téléphone, données, retours / Phone sign-in, data, feedback

| # | Qui | Action | Attendu / Expected | OK | Problème / Problem |
|---|---|---|---|---|---|
| 11.1 | A | Se déconnecter ; « Mot de passe oublié ? » ; suivre l’e-mail. *Sign out; “Forgot password?”; follow the e-mail.* | E-mail reçu ; nouveau mot de passe enregistré. *E-mail received; new password saved.* | ☐ | |
| 11.2 | B | Se déconnecter ; « Continuer avec mon numéro de téléphone » ; « M’envoyer un code ». *Sign out; “Continue with my phone number”; “Send me a code”.* | SMS de « PRod » avec un code à 6 chiffres en moins de 2 min ; connexion réussie. *SMS from “PRod” with a 6-digit code within 2 min; signed in.* | ☐ | |
| 11.3 | A | « Compte et réglages » → « Télécharger mes données ». *“Account & settings” → “Download my data”.* | Fichier avec ses propres données, seulement les prénoms des autres. *File with own data, only other people’s display names.* | ☐ | |
| 11.4 | A, B | « Donner mon avis sur le test ». *“Give feedback on the test”.* | « Merci ! Votre avis a été envoyé… » ; visible dans l’admin (Retours) ; e-mail à l’opérateur dans les 5 min. *“Thank you! Your feedback has been sent…”; visible in admin (Feedback); e-mail to the operator within 5 min.* | ☐ | |

---

## Bilan / Summary

| | |
|---|---|
| Date, lieu / Date, place | |
| Téléphones (modèle, système) / Phones (model, OS) | A : …… B : …… V : …… |
| Lignes OK / Lines OK | …… / 38 |
| Problèmes bloquants / Blocking problems | |
| Remarques de Rodney / Rodney’s remarks | |
| Fonctions acceptées par Rodney / Features accepted by Rodney | |

Après le test, les résultats sont reportés dans `docs/verification-log.md` et les fonctions acceptées passent en **ACCEPTED** dans `docs/product-flow.md`. Les comptes de test peuvent être supprimés depuis « Compte et réglages ».
*After the test, results go into `docs/verification-log.md` and accepted features become **ACCEPTED** in `docs/product-flow.md`. Test accounts can be deleted from “Account & settings”.*
