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
- Hébergement : dépôt public, GitHub Pages via `.github/workflows/deploy.yml` (build + tests, puis
  publication de `dist/`) → https://rdzoagbe.github.io/ProRod/ . Sources, schéma et scripts sont
  donc visibles : rien de confidentiel ne doit entrer dans le dépôt.
- Quatre principes : accès limité au lieu rejoint ; aucun droit à une réponse ; parcours simple
  sans selfie obligatoire ; mêmes protections pour tous (fermer, bloquer, signaler), avant tout paiement.
- Décisions encore ouvertes (côté client) : durées de session par type de lieu, preuve de présence
  au-delà du QR, prix du pass, modèle de paiement (hommes payants / femmes gratuites : à valider
  juridiquement avant activation, et cas non binaires), responsables de la modération, propriété
  des comptes de production.

## Le code
- Site statique sans framework : `public/` (sources servies), `src/account.js` (application de
  compte, bundlée par esbuild dans `public/account.bundle.js`), `public/index.html` + `app.js`
  (démo fictive de consentement, clairement étiquetée, pas un backend).
- `npm ci`, `npm run build`, `npm test` (node:test, 10 contrôles). Build : copie `public/` → `dist/`.
- `src/public-config.js` : URL et clé publiable Supabase, `siteUrl` = adresse publique de l'app
  (sert aux liens des e-mails de confirmation et de récupération). Jamais de clé secrète ici.

## Supabase (projet `blqcmpqctetmjqsfdvsq` « ProRod », Paris) — jamais un autre projet Supabase
- Schéma : `db/accounts-and-venues.sql` (instantané appliqué) ; tests transactionnels
  `db/verify-accounts-and-venues.sql` (tout est annulé en fin de script).
- Modèle : tables publiques `profiles` et `venue_sessions` en lecture seule pour l'utilisateur
  (RLS) ; schéma `private` (lieux, invitations hachées, restrictions) inaccessible aux clients ;
  toute écriture passe par des fonctions `private.*` SECURITY DEFINER exposées par des
  wrappers `public.*`. Ne jamais autoriser depuis des métadonnées modifiables par l'utilisateur.
- Invitations (QR) : `db/create-invite.sql` dans l'éditeur SQL ; le jeton n'est montré qu'une fois.
- E-mails Auth : le service intégré de Supabase n'envoie qu'aux membres de l'organisation ;
  configurer le SMTP Brevo du projet + Site URL + redirections avant tout test avec le client.
- Données : e-mail dans Auth uniquement, date de naissance privée et verrouillée, 18 ans minimum,
  jamais de genre déduit d'une adresse, jamais de données privées dans le service worker.

## Règles
- Dépôt public, destiné à être transféré au client : pas de secret, pas de donnée réelle, pas de nom de client,
  pas d'adresse privée dans le code ou l'historique.
- Toute fonction livrée doit marcher avec de vrais comptes et des contrôles côté serveur ;
  la démo ne vaut pas livraison. Ajouter un test pour chaque règle de sécurité.
- Textes FR/EN partout ; on pousse directement sur `main` après build + tests verts.
