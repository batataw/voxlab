# CLAUDE.md — VoxLab (nom de travail)

App macOS perso, **hors prod**, 100 % gratuite et locale :
**source audio (fichier ou URL YouTube) → isolation voix → transcription → correction LLM → traduction**, avec historique des jobs.

## Contraintes non négociables

- **Gratuit** : aucune API payante, aucun service cloud. Tout tourne en local sur le Mac.
- **Pas de prod** : pas de Mac App Store, **App Sandbox désactivé**. On lance des binaires externes via `Process`.
- **Plateforme** : macOS 26+, Apple Silicon uniquement.
- **Machine cible** : Mac Studio M1 Max, 64 Go de RAM, macOS 26.6. Les modèles par défaut ci-dessous sont dimensionnés pour cette machine.
- **Langues** : langues européennes courantes (fr, en, es, it, de, pt, nl…), en source comme en cible.
- **Sortie** : texte brut. **Pas de sous-titres**, pas d'horodatage exposé à l'utilisateur.

## Stack

| Couche | Choix |
|---|---|
| UI | SwiftUI (macOS), `NavigationSplitView` avec l'historique à gauche et le détail du job à droite |
| Persistance | SwiftData (métadonnées et textes) ; fichiers audio sur disque |
| Concurrence | Swift Concurrency (`async/await`, `actor`), Swift 6 strict concurrency |
| Import YouTube | `yt-dlp` + `ffmpeg` (CLI, Homebrew) |
| Isolation voix | Demucs `htdemucs_ft` par défaut (meilleure qualité, environ 4× plus lent), `htdemucs` en mode rapide ; `--two-stems vocals` (CLI Python, venv dédié) |
| Transcription | WhisperKit (Swift Package, CoreML), `large-v3` par défaut, `large-v3-turbo` en mode rapide |
| Correction | Apple Foundation Models par défaut ; Ollama (localhost) en provider alternatif |
| Traduction | Apple Translation framework ; fallback via le même `LLMProvider` |

## Prérequis machine (hors app)

```bash
brew install ffmpeg yt-dlp uv ollama   # ollama optionnel
uv venv ~/.voxlab/venv && source ~/.voxlab/venv/bin/activate
uv pip install demucs
```

- L'app ne gère pas l'installation de ces outils. Elle **détecte leur présence** au lancement et affiche un écran de diagnostic s'il en manque un.
- Les chemins des binaires sont configurables dans Réglages. Valeurs par défaut : `/opt/homebrew/bin/...` et `~/.voxlab/venv/bin/demucs`.
- Demucs : tester `-d mps`, avec repli automatique sur `-d cpu` en cas d'échec.

## Pipeline

```
Import ──► Separate ──► Transcribe ──► Correct ──► Translate
```

Chaque étape :
- lit l'artefact de l'étape précédente et écrit le sien dans `~/Library/Application Support/VoxLab/jobs/<jobID>/` ;
- met à jour son statut (`pending | running | done | failed | cancelled`) et sa progression dans SwiftData ;
- est **relançable seule**. On peut par exemple re-corriger sans re-séparer. En cas d'échec, le job reprend à l'étape échouée.

| Étape | Entrée | Sortie |
|---|---|---|
| Import | fichier (mp3, m4a, wav, flac, aiff) ou URL YouTube | `source.wav` (44,1 kHz, stéréo) |
| Separate | `source.wav` | `vocals.wav` |
| Transcribe | `vocals.wav` (rééchantillonné à 16 kHz mono pour Whisper) | `transcript_raw.txt` et la langue détectée |
| Correct | `transcript_raw.txt` | `transcript_corrected.txt` |
| Translate | `transcript_corrected.txt`, langue cible | `translation_<lang>.txt` |

Commandes de référence :
```bash
yt-dlp -x --audio-format wav -o "<dir>/source.%(ext)s" "<url>"
ffmpeg -i <input> -ar 44100 -ac 2 <dir>/source.wav
demucs -n htdemucs_ft --two-stems vocals -d mps -o <tmp> <dir>/source.wav
```

## Architecture

```
VoxLab/
├── App/                  # VoxLabApp, injection des dépendances
├── Models/               # @Model Job, StepRun ; enums Step, StepStatus
├── Pipeline/
│   ├── PipelineRunner.swift      # actor, orchestre les étapes, annulation
│   └── Steps/                    # une struct par étape, conforme à PipelineStep
├── Services/
│   ├── Protocols/        # SourceImporter, VocalSeparator, Transcriber,
│   │                     # TranscriptCorrector, Translator, LLMProvider
│   ├── CLI/              # ProcessRunner (async, stdout/stderr streamés, cancel)
│   ├── YtDlpImporter.swift, FileImporter.swift
│   ├── DemucsSeparator.swift
│   ├── WhisperKitTranscriber.swift
│   ├── LLM/              # FoundationModelsProvider, OllamaProvider
│   ├── LLMCorrector.swift
│   └── AppleTranslator.swift
├── Features/
│   ├── History/          # liste des jobs, recherche, suppression
│   ├── JobDetail/        # timeline des étapes, textes, actions par étape
│   ├── NewJob/           # drag & drop fichier, champ URL, langue cible
│   └── Settings/         # chemins binaires, modèle Whisper, provider LLM
└── Diagnostics/          # check des dépendances externes
```

Règles :
- **Tout service passe par un protocole**. Les implémentations concrètes ne sont injectées qu'à un seul endroit (`App/`).
- `ProcessRunner` est l'unique point d'appel à `Process`. Il gère le timeout, l'annulation (`terminate`) et le parsing de progression (pourcentage Demucs, sortie `yt-dlp`).
- Pas de logique métier dans les vues. Les ViewModels sont des `@Observable`, sur `@MainActor`.
- Les textes (brut, corrigé, traduit) sont stockés **à la fois** en fichier et dans SwiftData, pour l'affichage et la recherche.

## Correction LLM

- Le `LLMProvider` expose `func complete(system: String, user: String) async throws -> String`.
- Le prompt de correction est stocké dans `Resources/Prompts/correction.md` et non en dur dans le code. Il doit :
  - corriger l'orthographe, les mots mal reconnus et la ponctuation ;
  - **préserver** le sens, la structure en vers et les répétitions (refrains) ;
  - ne rien inventer ni réécrire : en cas de doute, garder l'original ;
  - répondre uniquement par le texte corrigé.
- Foundation Models : contexte limité. Si le texte dépasse la limite, on découpe par blocs de couplets en gardant un recouvrement.
- Ollama : modèle configurable, appelé via `POST http://localhost:11434/api/generate` avec `stream: false`.
  - Défaut : `mistral-small` (24B, bon en langues européennes, environ 15 Go en Q4).
  - Alternative : `qwen2.5:32b`. Les 64 Go le permettent, mais il est plus lent.
- Réglage « Qualité » : `rapide` (htdemucs, large-v3-turbo, Foundation Models) ou `max` (htdemucs_ft, large-v3, Ollama). Défaut : `max`.

## Traduction

- Apple Translation : vérifier les paires de langues installées. Si une paire manque, proposer le téléchargement système.
- Vérifier quelle API de `TranslationSession` est disponible sur la cible. Si l'init direct n'existe pas, passer par le modifier SwiftUI `.translationTask`.
- On traduit le texte **corrigé**, ligne à ligne pour conserver la structure.
- Option Réglages : « traduire via LLM » (meilleur sur le registre familier et l'argot des paroles).

## UI

- Nouveau job : zone de drag & drop **ou** champ URL, choix de la langue cible, bouton Lancer.
- Détail du job : timeline des 5 étapes avec statut, progression, durée et bouton « relancer cette étape ».
- Lecteur audio minimal (AVFoundation) pour `source.wav` et `vocals.wav`.
- Trois onglets texte (brut, corrigé, traduit), éditables à la main, avec bouton Copier.
- Le texte corrigé est éditable : une édition manuelle marque la traduction comme obsolète.

## Tests

- Swift Testing (`@Test`).
- Mocks pour chaque protocole de service. `PipelineRunner` est testé sans aucun binaire réel : ordre des étapes, reprise après échec, annulation.
- `ProcessRunner` est testé avec `/bin/echo` et `/bin/sleep` (annulation, timeout).
- Pas de tests UI.

## Conventions

- Code et identifiants en anglais ; textes UI et commentaires en français.
- Pas de dépendance SPM hors WhisperKit sans validation.
- Erreurs typées par service (`enum DemucsError: LocalizedError`…), avec un message lisible affiché dans la timeline.
- Logs via `os.Logger` (sous-système `com.voxlab`, une catégorie par service).

## Hors scope

Sous-titres et horodatage, iOS, distribution, multi-utilisateur, API cloud, traitement par lots (pour l'instant).

## Ordre d'implémentation

1. Squelette app, modèles SwiftData, `ProcessRunner` et écran Diagnostics.
2. Import fichier, Separate (Demucs). Valider tôt les temps de traitement et la RAM.
3. Transcribe (WhisperKit).
4. Correct (Foundation Models, puis Ollama).
5. Translate.
6. Import YouTube.
7. Finitions UI de l'historique (recherche, suppression des fichiers d'un job).
