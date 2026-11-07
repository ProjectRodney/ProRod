# PRod (dépôt ProRod) : application d'un client, réalisée par DZOFT

Roland Dzoagbe (DZOFT) parle français ; répondre dans la langue de son message. Il valide tout ce
qui touche aux comptes (Supabase, GitHub, Brevo, hébergement) ; toi, tu fais le code et tu le guides.

## Le projet
- Projet client (le nom du client et le devis restent hors du dépôt, qui est public). Produit : **PRod**, application web installable (PWA)
  qui permet aux personnes présentes dans un même lieu de faire connaissance, avec consentement.
  Nom défini dans `src/brand.js` (anciens noms de travail : Zélo, Mêla).
- Documents de référence (hors dépôt, chez Roland) : feuille de route « PRod » du 5 novembre 2026
  (9 pages, phases 1 à 6) et compte rendu de cadrage du 4 novembre 2026.
- Parcours produit de référence, étape par étape avec l'état d'avancement : `docs/product-flow.md`.
- Hébergement : dépôt public **ProjectRodney/ProRod** (compte GitHub du client depuis le 7 novembre 2026 ; l’ancienne adresse rdzoagbe est morte pour GitHub Pages), GitHub Pages via `.github/workflows/deploy.yml` (build + tests, puis
  publication de `dist/`) → https://projectrodney.github.io/ProRod/ . Sources, schéma et scripts sont
  donc visibles : rien de confidentiel ne doit entrer dans le dépôt.
- Quatre principes : accès limité au lieu rejoint ; aucun droit à une réponse ; parcours simple
  sans selfie obligatoire ; mêmes protections pour tous (fermer, bloquer, signaler), avant tout paiement.
- Décisions encore ouvertes (côté client) : durées de session par type de lieu, preuve de présence
  au-delà du QR, prix du pass, modèle de paiement (hommes payants / femmes gratuites : à valider
  juridiquement avant activation, et cas non binaires), responsables de la modération, propriété
  des comptes de production.

## Le code
- Site statique sans framework : `public/` (sources servies). `index.html` = page d'accueil / installeur
  (`pwa-install.js` : invite d'installation native ou guide iPhone), `account.html` = application
  (`src/account.js` bundlé en `account.bundle.js`), `admin.html` = administration (`src/admin.js`),
  `demo.html` + `app.js` = démo fictive de consentement, clairement étiquetée, pas un backend.
  Le produit s'affiche « P.Rod » (`src/brand.js`).
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
- Comptes : trois types (`profiles.account_type` personal | pro | venue). Les comptes établissement ne participent jamais aux rencontres (`private.require_person()`), gèrent leur lieu (candidature approuvée par l’admin, QR générés sur le téléphone, annonces, durée ≤ 3 h en test). Réglages serveur dans `private.app_settings` : `simulation`, `max_session_minutes`, `pass_rule` (everyone | none, jamais selon le genre), `feedback_email` / `feedback_sender` (jamais dans Git). Clé Brevo pour les e-mails de retours : Vault, nom `brevo_api_key`.
- Connexion par téléphone : hook Supabase « Send SMS » → fonction Edge `supabase/functions/send-sms` (Brevo SMS transactionnel ; secrets `SEND_SMS_HOOK_SECRET` et `BREVO_API_KEY` côté Edge Functions). Boutons Google / téléphone activés par `providers` dans `src/public-config.js` une fois le fournisseur configuré dans Supabase.
- Traduction du chat : fonction Edge `supabase/functions/translate` (DeepL, secret `DEEPL_API_KEY` dans Supabase → Edge Functions → Secrets), appelée seulement à la demande du membre ; jamais de clé côté client.
- Paiements : uniquement simulés (`passes.simulated`, 0 €) tant que le modèle tarifaire n’est pas validé juridiquement ; aucune règle liée au genre dans le code.
- Règles de rencontre décidées le 6 novembre 2026 : un refus (ou une absence de réponse) vaut pour toujours, dans tous les lieux, sauf si la personne écrit la première ; on n’écrit dans une conversation que lorsque les deux sont présents dans le lieu (l’historique reste lisible).
- Données : e-mail dans Auth uniquement, date de naissance privée et verrouillée, 18 ans minimum,
  jamais de genre déduit d'une adresse, jamais de données privées dans le service worker.

## Règles
- Dépôt public, destiné à être transféré au client : pas de secret, pas de donnée réelle, pas de nom de client,
  pas d'adresse privée dans le code ou l'historique.
- Toute fonction livrée doit marcher avec de vrais comptes et des contrôles côté serveur ;
  la démo ne vaut pas livraison. Ajouter un test pour chaque règle de sécurité.
- Textes FR/EN partout ; on pousse directement sur `main` après build + tests verts.
