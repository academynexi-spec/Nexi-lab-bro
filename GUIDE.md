# NEXI LAB PRO — Guide complet pas à pas

Ce guide part de zéro : tu n'as besoin d'aucune connaissance technique. Fais **une étape à la fois**, dans l'ordre, et vérifie « Tu dois voir… » avant de passer à la suivante.

**Les 3 outils (tous gratuits) :** **Supabase** (la base de données), **GitHub** (stocker tes fichiers), **Vercel** (mettre l'application en ligne).

**Important :** je n'ai pas pu tester le SQL sur un vrai Supabase (pas d'accès réseau depuis mon environnement). L'application, elle, a été testée de bout en bout dans un navigateur avec une base simulée. Si une étape affiche une erreur rouge, recopie le message exact : c'est la seule façon de la corriger vite.

---

## PARTIE A — Préparer les fichiers

1. Extrais le zip (clic droit > **Extraire tout**). Tu obtiens le dossier `nexi-lab-pro`.
2. Installe **VS Code** (code.visualstudio.com) si ce n'est pas fait. Ouvre-le, puis *Fichier > Ouvrir le dossier* et choisis `nexi-lab-pro`.
3. Dans VS Code, onglet **Extensions** (carrés à gauche), cherche **Live Server** et installe-le.

Tu dois voir dans la colonne de gauche : `index.html`, `config.js`, `js`, `css`, `supabase`, `GUIDE.md`…

## PARTIE B — Créer la base de données (Supabase)

> Tu fais une **PWA à part** : crée un **nouveau projet Supabase** pour elle (le plan gratuit permet 2 projets actifs). Ne réutilise pas la base de l'ancienne version.

4. Va sur **supabase.com**, connecte-toi, clique **New project**. Nom : `nexi-lab-pro`. Invente un mot de passe de base de données (note-le). Région : la plus proche (Europe). Clique **Create new project** et attends 1 à 2 minutes.
5. Menu de gauche : **Authentication**, puis **Sign In / Providers**, puis **Email**. **Désactive « Confirm email »**, clique **Save**. *(Sans cela, la création des Nexians échoue.)*
6. Menu de gauche : **SQL Editor**, puis **New query**.
7. Dans VS Code, ouvre `supabase/schema.sql`, **Ctrl+A** puis **Ctrl+C**. Colle dans Supabase (**Ctrl+V**) et clique **Run**.
   *Tu dois voir : « Success. No rows returned ».* Si tu vois une erreur rouge, envoie-moi le texte exact sans rien modifier.
8. Vérifie : menu **Table Editor**. Tu dois voir une liste de tables (profiles, items, categories, sectors, plan_cfg, history, hats, user_stats…). Dans **sectors**, tu dois voir les 15 génies.

## PARTIE C — Créer ton compte administrateur

9. **Authentication > Users > Add user > Create new user** :
   - Email : `admin@nexilab.app`
   - Mot de passe : celui que tu veux (**note-le, mets-en un solide**)
   - Coche **Auto Confirm User**, puis **Create user**.
10. **SQL Editor > New query**. Colle **exactement** cette ligne, puis **Run** :
```
insert into profiles(id,login,full_name,pseudo,role) select id,'admin','Administrateur','admin','admin' from auth.users where email='admin@nexilab.app';
```
*Tu dois voir : Success.*

## PARTIE D — Relier l'application à Supabase

11. Supabase : roue dentée **Project Settings** (en bas à gauche) > **API**. Copie **Project URL** et la clé **anon public**. **Jamais la clé `service_role`** (elle ouvre tout : ne la mets nulle part dans l'application).
12. VS Code : ouvre `config.js`. Remplace `https://VOTRE-PROJET.supabase.co` par ton Project URL et `VOTRE_CLE_ANON` par ta clé. Garde les guillemets simples. **Ctrl+S**.

## PARTIE E — Tester sur ton ordinateur

13. Clic droit sur `index.html` > **Open with Live Server**. L'accueil s'affiche (logo, « À propos », « Se connecter »). Si la page est vide : **Ctrl+F5**, puis F12 > Console et envoie-moi la ligne rouge.
14. Clique **Se connecter**, puis **tape 5 fois vite sur le logo** : le titre change de couleur (mode admin).
15. Identifiant `admin`, mot de passe de l'étape 9. Tu arrives sur le panel admin.

## PARTIE F — Premier contenu et premier test joueur

16. **Nexians > + Créer un Nexian** : nom, pseudo, identifiant (ex. `test1`), mot de passe (6 caractères minimum), secteur (ex. Génie Chimique), formule **full** (pour tout tester), NX 100. Enregistre.
17. **Donjons** : choisis le même secteur, écris un nom dans « nouvelle catégorie », palier `1`, et colle :
```
Quelle est la formule de l'eau ? | H2O;CO2;O2 (1) [20;10;5]
Combien de protons a l'hydrogène ? | 1;2;3 (1) [20;10;5]
```
Clique **Importer** (« 2 ajoutée(s) »). Les lignes sont **visibles** (bouton vert « 👁 Visible »).
18. **Déconnexion**. Reconnecte-toi **sans** taper 5 fois sur le logo, avec `test1`. **Donjons > ta catégorie > Palier 1** : vert + son si juste, rouge + vibration sinon.
19. Teste aussi **Nexify** (avec une carte importée dans Nexify, formule standard minimum), les **Cartes de révision** et un **schéma** (voir partie H).

## PARTIE G — Mettre en ligne (GitHub puis Vercel)

20. **github.com** > **New repository** (nom `nexi-lab-pro`, **Private**) > **Create**. Clique **uploading an existing file**.
21. Glisse **tout le contenu** du dossier `nexi-lab-pro` (fichiers et sous-dossiers, pas le dossier lui-même). **Commit changes**. *(Ton `config.js` contient seulement l'URL et la clé « anon » : c'est prévu pour être public, la sécurité est dans la base.)*
22. **vercel.com** > connexion avec GitHub > **Add New > Project** > **Import** sur `nexi-lab-pro`. Ne change aucun réglage (pas de commande de build) > **Deploy**.
23. Après ~30 s : lien `https://nexi-lab-pro-xxx.vercel.app`. Ouvre-le sur ton téléphone, refais le test. Chrome mobile propose **Installer l'application**.
24. **Mises à jour futures :** remplace les fichiers modifiés sur GitHub : Vercel redéploie tout seul, **le lien ne change pas**. Les Nexians gardent leur installation (fermer/rouvrir l'appli suffit).

**Anti-pause (important sur le plan gratuit)** : Supabase met un projet gratuit **en veille après 7 jours sans activité**. Avec des joueurs actifs, ce n'est pas un souci. Pendant les vacances, crée une tâche gratuite sur **cron-job.org** : adresse `https://TON-PROJET.supabase.co/rest/v1/rpc/ping`, méthode GET, en-têtes `apikey` et `Authorization: Bearer` = ta clé anon, une fois par jour.

## PARTIE H — Utiliser NEXI LAB

### Importer des questions (une ligne par question)
| Rubrique | Format d'une ligne |
|---|---|
| Donjon | `Question | Option A;Option B;Option C (2) [secondes;NX;bonus rapidité]` |
| Nexify | `Question | A;B;C;D (3) [facteur;secondes]` — ex. `[3;30]` |
| Carte | `Question | Réponse détaillée et exemple` |

`(2)` = numéro de la bonne réponse. Le bonus rapidité est accordé si on répond en moins de la moitié du temps.

### Schémas (flowsheet, schéma électrique, dessin industriel)
- **Une question** : dans la liste du contenu, bouton 🖼 (recto / verso pour les cartes), 🧹 pour retirer.
- **En masse** : choisis un **schéma commun** à toutes les lignes, ou plusieurs fichiers dans « Schémas du lot » et termine chaque ligne par `@nom.png` (ex. `Que régule LIC-201 ? @pid2.png | Le niveau @pid2-corrige.png`).
- Formats PNG / JPEG / WebP. L'application les réduit et les compresse. Garde un texte lisible à ~1500 px de large.
- Côté Nexian : toucher le schéma = plein écran, pincer / molette / double-toucher pour zoomer. À Nexify, il n'apparaît qu'après la mise. Chaque schéma n'est téléchargé **qu'une fois par appareil** (économie de bande passante).

### Formules et tickets
Admin > **Réglages** : tickets/jour, parties possibles par question, accès Nexify, cumul, par formule. Tickets renouvelés à minuit (heure de Lubumbashi, calculée **par le serveur** : changer l'heure du téléphone ne sert à rien). Dans la fiche d'un Nexian, tu peux fixer un nombre de tickets particulier et une date de fin d'abonnement.

### Cycle hebdomadaire (équité anciens / nouveaux)
- **NX total** = permanent (rang, solde Nexify). **NX de la semaine** = repart à 0 à chaque clôture.
- Seules les questions marquées **⭐ Défi de la semaine** comptent pour la semaine (case cochée par défaut à l'import ; bouton ⭐ sur une ligne existante).
- Mise Nexify plafonnée : 25 % du solde, 500 NX maximum (modifiable dans Réglages).
- **Chaque lundi** : Admin > **Classement** > **Clôturer le cycle**. Il archive les classements, attribue Or/Argent/Bronze, Progression, Assiduité, Précision, Révélation, fait monter/descendre les ligues et remet les NX de la semaine à 0. Les archives et les vrais noms sont dans l'onglet **Archives**.
- Les contenus existants ne sont pas ⭐ au départ : marque-les, sinon ils ne rapportent pas de NX de la semaine.

### Ligues
Admin > **Réglages > Ligues par secteur** : activation secteur par secteur. **Promotion** (Bronze → Diamant ; le quart supérieur monte, le quart inférieur descend à chaque clôture) ou **Par rang** (Novice, Confirmé, Expert, Élite). **N'active une ligue qu'avec ~10 joueurs ou plus dans le secteur** (le nombre est affiché). Pour caser quelqu'un à la main : fiche du Nexian > champ **Ligue**.

### Badges
20 badges permanents, attribués par le serveur (Premier pas, Centurion, Sans faute, Semaine de feu, Parieur, un badge par rang…). Le Nexian les voit dans **Badges** ; toi, dans la fiche du Nexian.

### Chapeaux (mini-concours)
Admin > **Chapeaux** > **+ Créer** : nom, description, secteur, catégorie optionnelle. Coche les membres (recherche, tout cocher, ou toute une ligue), enregistre. Le classement s'affiche en direct (vrais noms pour toi, pseudos pour eux). **Clôturer** fige le classement et donne le badge **Champion de chapeau** au vainqueur. Seuls les membres voient l'onglet 🎩 Concours.

### Texte « À propos »
Ouvre `js/app.js`, **Ctrl+F** : `MODIFIE CE TEXTE`. Écris ton texte, enregistre, remplace le fichier sur GitHub.

## PARTIE I — Santé du stockage et archivage (plan gratuit)

### Ce que le plan gratuit permet (vérifié en octobre 2026)
**500 Mo de base de données**, **1 Go de fichiers**, **5 Go de transfert/mois**, 50 000 utilisateurs actifs, mise en veille après 7 jours sans activité. **Quand la base dépasse 500 Mo, Supabase la passe en lecture seule** : plus aucune réponse ne s'enregistre. C'est ce que ce système empêche.

### Ce qui grossit, et ce que fait NEXI LAB
| Donnée | Taille | Traitement |
|---|---|---|
| Détail de chaque réponse (`history`) | ~200 octets/réponse, **c'est le gros poste** | archivé puis résumé après X jours (90 par défaut) |
| Tickets du jour (`tlog`) | minuscule | purgés automatiquement (> 3 jours) |
| Tentatives, badges, archives hebdo, totaux | très petit | conservés pour toujours |
| Schémas | ~100–400 Ko chacun | compressés ; cache sur l'appareil ; fichiers inutiles nettoyables |
| Photos de profil | ~15 Ko | réduites à 256 px à l'envoi |

**Rien d'important n'est supprimé** : les totaux de chaque joueur (réponses, réussites, meilleur gain), les scores, rangs, badges et classements ne dépendent **pas** du détail archivé. Le détail brut part dans un **fichier compressé** conservé dans ton stockage, avec un **résumé mensuel** gardé dans la base.

### Page Admin > 💾 Santé & archives
- **Jauges** de la base et des fichiers (vert / orange dès 70 % / rouge dès 90 %). Un **bandeau d'alerte** apparaît sur l'accueil admin à partir de 70 %.
- **Archiver maintenant** : pour chaque mois entièrement plus vieux que X jours, l'application lit les lignes, écrit un fichier `.csv.gz`, l'envoie dans le bucket privé `archives`, puis demande au serveur de **vérifier le nombre de lignes** avant de supprimer. Si le compte ne correspond pas, **rien n'est supprimé**.
- **Archives conservées** : tu peux retélécharger chaque fichier (ouvrable dans Excel / Google Sheets après décompression).
- **Nettoyer maintenant** : supprime les fichiers inutilisés (schémas de questions supprimées, photos de comptes supprimés) et les tickets périmés.
- **Sauvegarde** : un fichier `.json` complet, ou des `.csv` (profils, archives hebdo, totaux) à ouvrir dans Google Sheets.
- **Réglages** : durée de conservation (14 jours minimum) et limites (change-les si tu passes à un plan payant).

### Routine conseillée
**1 fois par mois**, 2 minutes : ouvre Santé & archives > **Archiver maintenant** > **Nettoyer maintenant** > **Sauvegarde complète**. L'accueil admin lance aussi une maintenance automatique si elle n'a pas tourné depuis 7 jours.

### Si la base approche des 500 Mo : le mode économie automatique
À **90 %**, la maintenance résume et retire le détail de plus de 30 jours, puis passe en **mode économie** : le détail des donjons n'est plus enregistré, mais **tout continue de fonctionner** (réponses, NX, tickets, classements, badges, Nexify). Un bandeau rouge te prévient. Le mode se coupe seul sous 80 %, ou avec le bouton **Désactiver le mode économie**.
*Précision technique :* après une grosse suppression, Postgres réutilise l'espace mais la taille affichée sur le disque ne baisse pas toujours tout de suite. Pour la faire redescendre, tu peux lancer **une seule instruction, seule dans une nouvelle requête** du SQL Editor : `cluster public.history using history_pkey;` (rapide quand la table est petite). Facultatif.

### Maintenance 100 % automatique (facultatif)
Supabase > **Database > Extensions** : active **pg_cron**, puis dans le SQL Editor : `select cron.schedule('nexi-maintenance','0 2 * * 1','select maintenance()');` (chaque lundi à 02h).

### Combien de joueurs ? (ordre de grandeur sur 90 jours de détail)
| Joueurs | Réponses/jour/joueur | Détail conservé | Verdict |
|---|---|---|---|
| 100 | 20 | ~36 Mo | très large |
| 300 | 30 | ~160 Mo | confortable |
| 1000 | 30 | ~540 Mo | mets la conservation à **30 jours** (~180 Mo) |

### Et le Google Sheet ?
Je ne l'ai **pas** branché en direct, volontairement : un lien live ajouterait un aller-retour vers Google à chaque réponse (plus lent), des quotas Google qui peuvent bloquer, et des risques de désynchronisation entre appareils. Ici, **le jeu ne parle qu'à Supabase** ; l'archivage est une action séparée (toi, ou la maintenance planifiée) qui ne touche jamais le chemin d'une réponse : **aucun impact sur la vitesse ni sur la synchro multi-appareil**. Tes données restent exploitables dans Google Sheets via les **exports .csv** (importer : Sheets > Fichier > Importer).

## PARTIE J — Sécurité et bonnes habitudes
- Ne mets **jamais** la clé `service_role` dans l'application ou sur GitHub.
- **Mot de passe admin** : Supabase > Authentication > Users > `admin@nexilab.app` > modifier. Mots de passe des Nexians : fiche du Nexian dans l'admin.
- Les réponses, NX, tickets, ligues et badges sont calculés **par le serveur** : un joueur ne peut pas les modifier depuis son navigateur. Chaque Nexian ne voit que son secteur ; les vrais noms ne sont visibles que de l'admin.
- Les schémas et archives sont dans des espaces **privés** (accès par liens temporaires).

## PARTIE K — Dépannage
| Symptôme | Cause probable | Solution |
|---|---|---|
| Accueil vide / message rouge | Pas d'internet au premier chargement, cache ancien, mauvais dossier | Ctrl+F5 ; F12 > Application > Service Workers > Unregister + Clear site data ; ouvre bien le dossier `nexi-lab-pro` |
| « Identifiants incorrects » | Mauvais code, ou étape 10 oubliée (admin) | Vérifie l'e-mail `admin@nexilab.app` et la ligne SQL de l'étape 10 |
| Création de Nexian refusée | « Confirm email » encore activé | Étape 5 |
| Le Nexian ne voit rien dans Donjons | Secteur différent du contenu, contenu masqué (🚫), abonnement expiré | Même secteur ? bouton **👁 Visible** (vert) ? date de fin ? |
| Nexify verrouillé 🔒 | Formule freemium | Passe en standard ou plus |
| « Plus de tickets » | Quota du jour épuisé | Se renouvelle à minuit, ou augmente-le dans Réglages / fiche du Nexian |
| Palier « redevenu disponible » | Formule full (2 parties), questions ajoutées au palier, question réimportée, ♻ utilisé | Voir le détail ci-dessus ; mets les nouvelles séries dans un **nouveau palier** |
| Plus aucune réponse ne s'enregistre | Base pleine (lecture seule) | Santé & archives ; à défaut passe au plan Pro de Supabase |

## PARTIE L — Mettre à jour une ancienne installation
Dossier `supabase/mises-a-jour/` : lis `LISEZ-MOI.txt`. Lance uniquement les fichiers qui te manquent, dans l'ordre, puis remplace les fichiers du site sur GitHub.
