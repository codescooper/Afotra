# AFOTRA - Rapport de tests complet

- **Date** : 2026-06-01 17:55:43
- **Machine** : DESKTOP-7K20H38 / utilisateur USER
- **Resultat** : **TOUS LES TESTS PASSENT** (35/35)
- **Couverture** : configuration, classification (categories + priorites + casse), gestion des regles (round-trip), journalisation, reporting (+ cas limites), bout-en-bout (CLI, tracker live, daily-report, dashboard WPF, XAML)


## A. Configuration & regles

| Statut | Cas d'usage | Detail |
|:------:|-------------|--------|
| PASS | config.json valide et coherent | interval=5s, focus=480min |
| PASS | rules.json : categories + regles presentes | 5 cats / 38 proc / 98 titre |
| PASS | toutes les regles referencent une categorie connue | 0 categorie orpheline |

## B. Classification - categories

| Statut | Cas d'usage | Detail |
|:------:|-------------|--------|
| PASS | process travail (Code) -> travail | travail |
| PASS | process communication (Teams) -> communication | communication |
| PASS | process communication (slack) -> communication | communication |
| PASS | process distraction (Spotify) -> distraction | distraction |
| PASS | process non mappe + titre sans regle -> inconnu | inconnu |

## B. Classification - priorites (navigateur / process / titre)

| Statut | Cas d'usage | Detail |
|:------:|-------------|--------|
| PASS | navigateur : titre YouTube bat process chrome -> distraction | distraction |
| PASS | navigateur : titre Udemy -> etude | etude |
| PASS | navigateur : titre Gmail -> communication | communication |
| PASS | navigateur : titre GitHub -> travail | travail |
| PASS | navigateur : aucun titre connu -> fallback process (travail) | travail |
| PASS | non-navigateur : process prioritaire sur titre (Code + 'YouTube' -> travail) | travail |
| PASS | non-navigateur non mappe : regle de titre s'applique (Udemy -> etude) | etude |
| PASS | correspondance titre insensible a la casse ('youtube' -> distraction) | distraction |

## C. Gestion des regles (round-trip)

| Statut | Cas d'usage | Detail |
|:------:|-------------|--------|
| PASS | Get-Categories renvoie la liste | 5 categories |
| PASS | Add-Category : nouvelle=true, doublon=false | ajout=True, doublon=False |
| PASS | Add-ProcessRule / Add-TitleRule augmentent les compteurs | proc 38->39, title 98->99 |
| PASS | Save-Rules + Load-Rules : persistance fidele | round-trip OK + regle active |

## D. Journalisation (logging)

| Statut | Cas d'usage | Detail |
|:------:|-------------|--------|
| PASS | Get-TodayLogFile : format activity-YYYY-MM-DD.csv | activity-2026-06-01.csv |
| PASS | Initialize-LogFile : entete ecrite une seule fois (idempotent) | 1 ligne d'entete |
| PASS | Write-ActivityLog : 10 colonnes dans le bon ordre | colonnes & valeurs OK |

## E. Reporting (math + cas limites)

| Statut | Cas d'usage | Detail |
|:------:|-------------|--------|
| PASS | Get-ReportData : focus score, total, switches, categories | total=100s focus=70% switches=8 |
| PASS | Get-ReportData : agrege les 'inconnu' (Unknowns) | inconnu agrege: 4 occ / 20s |
| PASS | Get-ReportData : fichier inexistant -> null | null OK |
| PASS | Get-ReportData : fichier vide (entete seule) -> null | null OK |
| PASS | Export-ReportToJSON : fichier + champs cles | json: focus=75% distraction=0.33min |
| PASS | Export-ReportToJSON : TopProcesses limite a 5 | TopProcesses=5 (<=5 sur 8 process) |
| PASS | Get-UnknownActivities : regroupe par process inconnu | weird x3 detecte, travail exclu |

## F. Bout-en-bout (CLI / live / dashboard)

| Statut | Cas d'usage | Detail |
|:------:|-------------|--------|
| PASS | tracker.ps1 -Check : exit 1 quand non lance | exit=1 (correct : aucun tracker actif) |
| PASS | tracker.ps1 : ecrit reellement des lignes en cours d'execution | ajout de 1 ligne(s) en 13s |
| PASS | daily-report.ps1 : genere le summary JSON du jour | rapport genere (focus=97.87%) |
| PASS | dashboard-wpf.ps1 : XAML (fenetre principale + overlay) parse | 2/2 fenetres XAML valides |
| PASS | dashboard-wpf.ps1 : se lance et affiche sa fenetre WPF | fenetre: 'AFOTRA Live' |

---

**Total : 35/35 reussis.** Genere par `Run-Full-Tests.ps1`.

