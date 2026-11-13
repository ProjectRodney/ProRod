# UPZONE (dépôt ProRod) : application d'un client, réalisée par DZOFT

Roland Dzoagbe (DZOFT) parle français ; répondre dans la langue de son message. Il valide tout ce
qui touche aux comptes (Supabase, GitHub, Brevo, hébergement) ; toi, tu fais le code et tu le guides.

## Le projet
- Projet client (le nom du client et le devis restent hors du dépôt, qui est public). Produit : **UPZONE** (nom choisi par le client le 10 novembre 2026, exploité par sa société ; marque et domaine à déposer à ce nom, voir plus bas), application web installable (PWA)
  qui permet aux personnes présentes dans un même lieu de faire connaissance, avec consentement.
  Nom défini dans `src/brand.js` (anciens noms : Zélo, Mêla, PRod / P.Rod, ANZIAK).
- Documents de référence (hors dépôt, chez Roland) : feuille de route « PRod » du 5 novembre 2026
  (9 pages, phases 1 à 6) et compte rendu de cadrage du 4 novembre 2026.
- Parcours produit de référence, étape par étape avec l'état d'avancement : `docs/product-flow.md`.
- Mise en service du pilote : `docs/deploy-checklist-pilot.md` (avant, pendant, après, retour arrière).
- Hébergement : dépôt public **ProjectRodney/ProRod** (compte GitHub du client depuis le 7 novembre 2026 ; l’ancienne adresse rdzoagbe est morte pour GitHub Pages), GitHub Pages via `.github/workflows/deploy.yml` (build + tests, puis
  publication de `dist/`) → https://projectrodney.github.io/ProRod/ . Sources, schéma et scripts sont
  donc visibles : rien de confidentiel ne doit entrer dans le dépôt.
- Quatre principes : accès limité au lieu rejoint ; aucun droit à une réponse ; parcours simple
  sans selfie obligatoire ; mêmes protections pour tous (fermer, bloquer, signaler), avant tout paiement.
- Nom UPZONE : registre INPI consulté le 7 novembre 2026 (marques FR, UE et internationales valables en France) : seule une ancienne demande UE « UPZONE » retirée ; recherche d’antériorité complète par un conseil en propriété industrielle et dépôt au nom du client (classes 9, 38, 42, 45) à faire par lui, ainsi que le nom de domaine.
- Décisions encore ouvertes (côté client) : durées de session par type de lieu, preuve de présence
  au-delà du QR, prix du pass, modèle de paiement (hommes payants / femmes gratuites : à valider
  juridiquement avant activation, et cas non binaires), responsables de la modération, propriété
  des comptes de production.

## Le code
- Site statique sans framework : `public/` (sources servies). `index.html` = page d'accueil / installeur
  (`pwa-install.js` : invite d'installation native ou guide iPhone), `account.html` = application
  (`src/account.js` bundlé en `account.bundle.js`), `admin.html` = administration (`src/admin.js`),
  `demo.html` + `app.js` = démo fictive de consentement, clairement étiquetée, pas un backend.
  Le produit s'affiche « UPZONE » (`src/brand.js`). Icône originale : `design/upzone-icon.svg` → PNG dans `public/assets/` (192, 512, 1024, apple-touch 180) ; pastille rouge du nombre de non-lus sur l’icône via l’API Badging (iPhone 16.4+ installé avec notifications autorisées, Chrome/Edge ordinateur ; pas Android), jamais de contenu.
- `npm ci`, `npm run build`, `npm test` (node:test). Build : copie `public/` → `dist/`.
- `src/public-config.js` : URL et clé publiable Supabase, `siteUrl` = adresse publique de l'app
  (sert aux liens des e-mails de confirmation et de récupération). Jamais de clé secrète ici.

## Supabase (projet `blqcmpqctetmjqsfdvsq` « ProRod », Paris) — jamais un autre projet Supabase
- Schéma : `db/accounts-and-venues.sql` (tables, RLS, stockage) + `db/functions.sql` (toutes les fonctions, exportées du projet, à régénérer après chaque migration : `docs/verification-log.md`) ; tests transactionnels `db/verify-accounts-and-venues.sql` (tout est annulé en fin de script), résultats consignés dans `docs/verification-log.md`.
- Modèle : tables publiques `profiles` et `venue_sessions` en lecture seule pour l'utilisateur
  (RLS) ; schéma `private` (lieux, invitations hachées, restrictions) inaccessible aux clients ;
  toute écriture passe par des fonctions `private.*` SECURITY DEFINER exposées par des
  wrappers `public.*`. Ne jamais autoriser depuis des métadonnées modifiables par l'utilisateur.
- Administration : `admin.html` (bundle `src/admin.js`), rôle = claim Auth `app_metadata.prod_admin = true`
  posé par l'opérateur dans Supabase (jamais `user_metadata`) ; validation en deux étapes obligatoire (le portail l’enrôle à la première connexion) ; journal
  `private.admin_actions`. Invitations (QR) depuis le portail, ou `db/create-invite.sql` en secours.
- E-mails Auth : le service intégré de Supabase n'envoie qu'aux membres de l'organisation ;
  configurer le SMTP Brevo du projet + Site URL + redirections avant tout test avec le client.
- Comptes : trois types (`profiles.account_type` personal | pro | venue). Depuis le 13 nov. 2026 (demande du client), le type `venue` s’affiche « événement » / « event » partout dans l’app (le nom interne ne change pas), et un lieu peut être de type `event` (`db/2026-11-13-event-category.sql`). Les comptes établissement ne participent jamais aux rencontres (`private.require_person()`), gèrent leur lieu (candidature approuvée par l’admin, QR générés sur le téléphone, annonces, durée ≤ 3 h en test). Réglages serveur dans `private.app_settings` : `simulation`, `max_session_minutes`, `pass_rule` (everyone | none, jamais selon le genre), `feedback_email` / `feedback_sender` (jamais dans Git). Clé Brevo pour les e-mails de retours : Vault, nom `brevo_api_key`.
- Connexion par téléphone : hook Supabase « Send SMS » → fonction Edge `supabase/functions/send-sms` (Brevo SMS transactionnel ; secrets `SEND_SMS_HOOK_SECRET` et `BREVO_API_KEY` côté Edge Functions). Boutons Google / téléphone activés par `providers` dans `src/public-config.js` une fois le fournisseur configuré dans Supabase.
- Notifications push (Web Push, VAPID) : table privée `push_subscriptions`, déclencheur `push_after_notification` → pg_net → fonction Edge `supabase/functions/send-push` (secrets `PUSH_HOOK_SECRET` = Vault `push_hook_secret`, `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT` ; JWT désactivé). Clé publique dans `src/public-config.js` (`vapidPublicKey`), clé privée jamais dans Git. Contenu : phrase générique selon le type + nombre de non-lus, jamais de nom ni de message ; abonnement supprimé à la déconnexion.
- Comptes confirmés par téléphone seulement = membres (`require_member` accepte e-mail OU téléphone confirmé) ; « Moyens de connexion » relie téléphone et e-mail au même compte.
- Clés d’accès (passkeys, Supabase Auth bêta) : `signInWithPasskey` / `registerPasskey` / `auth.passkey.*`, désactivées par `providers.passkey=false` tant que le domaine final n’est pas choisi (une clé est liée à l’identifiant RP = domaine ; le changer invalide toutes les clés). SMS et e-mail restent la solution de secours.
- Traduction du chat : fonction Edge `supabase/functions/translate` (DeepL, secret `DEEPL_API_KEY` dans Supabase → Edge Functions → Secrets), appelée seulement à la demande du membre ; jamais de clé côté client.
- Paiements : uniquement simulés (`passes.simulated`, 0 €) tant que le modèle tarifaire n’est pas validé juridiquement ; aucune règle liée au genre dans le code.
- Règles de rencontre décidées le 6 novembre 2026 : un refus (ou une absence de réponse) vaut pour toujours, dans tous les lieux, sauf si la personne écrit la première ; on n’écrit dans une conversation que lorsque les deux sont présents dans le lieu (l’historique reste lisible).
- « Qui souhaitez-vous voir ? » (femmes / hommes / tout le monde, 10 nov. 2026) : avec le genre, révèle l’orientation sexuelle = donnée sensible (art. 9 RGPD) → facultatif, consentement explicite obligatoire (`interest_consent_at`, refus serveur sinon), privé, sert uniquement à filtrer `venue_members` côté serveur, jamais renvoyé à un autre membre, jamais pour la tarification, retrait = effacement du consentement.
- Sécurité (réunion du 10 nov. 2026) : un signalement bloque automatiquement la personne signalée pour celui qui signale (`report_member` → `block_member`) ; l’admin peut avertir (`admin_warn_member`, notification `account_warned`) ou suspendre ; fin de conversation avec raison (`end_conversation`, `closed_reason`), montrée en termes neutres. Taille facultative (`height_cm`, 120–230) affichée sur le profil. Photo de profil dans une épingle de localisation (`pinPhoto`).
- Lieu voilé jusqu’au pass (11 nov. 2026, `db/2026-11-11-veiled-venue.sql`) : sans pass actif pour le lieu, `venue_members` ne renvoie que silhouette + département (saisi par le membre) + tranche d’âge (18-20 puis par 5), jamais id, nom, photo, bio, âge exact ; photos refusées aussi côté stockage (`private.photo_visible`) ; se présenter exige le pass. Même règle pour tous ; le membre ne peut pas se masquer (annoncé à l’inscription et dans la politique de confidentialité). Depuis le 13 nov. 2026 (`db/2026-11-13-blurred-preview.sql`) : avant le pass, on montre une version floutée de la photo = fichier séparé de 20 px créé sur le téléphone du membre (`u/<id>/blur-….jpg`, `avatar_blur_path`), seul fichier lisible sans pass (`avatars_blur_select`) ; jamais de flou côté client sur la vraie photo.
- Données : e-mail dans Auth uniquement, date de naissance privée et verrouillée, 18 ans minimum,
  jamais de genre déduit d'une adresse, jamais de données privées dans le service worker.

## Règles
- Dépôt public, destiné à être transféré au client : pas de secret, pas de donnée réelle, pas de nom de client,
  pas d'adresse privée dans le code ou l'historique.
- Toute fonction livrée doit marcher avec de vrais comptes et des contrôles côté serveur ;
  la démo ne vaut pas livraison. Ajouter un test pour chaque règle de sécurité.
- Textes FR/EN partout ; on pousse directement sur `main` après build + tests verts.
- Tutoiement (décision du client, 13 nov. 2026) : « tu » pour les comptes personnels et les visiteurs, « vous » pour les comptes professionnels et événement. Les textes français s’écrivent avec « vous » dans `src/account.js` ; la version « tu » de chaque phrase qui s’adresse au lecteur va dans `src/tu.js` (toute nouvelle phrase avec vous/votre/vos doit y être ajoutée). Conditions et politique de confidentialité : « vous ».
