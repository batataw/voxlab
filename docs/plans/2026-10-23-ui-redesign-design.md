# Refonte de l'interface — design

Date : 2026-10-23. Validé avec l'utilisateur à partir de captures de référence (app macOS en barre latérale de sections et contenu en cartes).

## Structure

- `NavigationSplitView` à deux colonnes : barre latérale de **sections**, contenu à droite.
- Sections : **Nouveau** (orange), **Historique** (rouge), **Diagnostics** (vert, orange si un outil obligatoire manque), **Réglages** (gris, épinglé en bas).
- Historique : `NavigationStack` ; une carte de job ouvre son détail dans la même colonne (bouton retour).
- Disparaissent : la feuille Nouveau job, la feuille Diagnostics, la fenêtre de réglages séparée. ⌘N → Nouveau, ⌘, → Réglages. Au lancement, s'il manque un outil obligatoire, l'app ouvre Diagnostics.

## Composants communs (`Features/Shared/Design/`)

- `IconTile` : symbole blanc sur pastille colorée arrondie.
- `Card` : coins arrondis, fond clair, bordure fine, bande inférieure optionnelle (plus sombre) pour les étiquettes.
- `Chip` : étiquette en pilule (icône + texte).
- `PageHeader` : grand titre + boutons ronds (`RoundIconButton`).
- `StatusPill` : statut coloré d'un job ou d'une étape.

## Historique

- Cartes de job : pastille (fichier ou YouTube), titre, date et origine, statut à droite (étape en cours et pourcentage pendant un traitement, barre de progression).
- Bande : paire de langues, qualité, durée totale, nombre de lignes, « Traduction obsolète ».
- Recherche dans le titre et les trois textes (couvre l'étape 7 du CLAUDE.md).
- Menu contextuel : supprimer (job + fichiers), afficher dans le Finder.

## Détail du job

- Carte d'en-tête : boutons ronds Reprendre/Annuler, Finder, Supprimer (confirmation dans l'app) ; bande langue détectée, langue cible, état des langues Apple.
- Cartes Pipeline (pastille colorée par étape), Audio, Textes (onglets et Copier dans l'en-tête).

## Modèle

- `Job.qualityRaw` : qualité figée à la création (étiquette de la carte, et une étape relancée garde la qualité d'origine). Valeur par défaut `max` pour la migration des jobs existants.

## Hors scope

- Pas de nouvelle fonction (pas de section Modèles). La logique (pipeline, services, `JobController`) ne change pas, hormis la qualité par job.
