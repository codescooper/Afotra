# AFOTRA - Rapport de tests complet

- **Date** : 2026-07-09 10:32:04
- **Machine** : DESKTOP-5PCC35H / utilisateur BEJ technologie
- **Resultat** : **TOUS LES TESTS PASSENT (4 sautes : live/bureau)** (76/76)
- **Couverture** : configuration, classification (categories + priorites + casse), gestion des regles (round-trip), journalisation, reporting (+ cas limites), bout-en-bout (CLI, tracker live, daily-report, dashboard WPF, XAML)


## A. Configuration & regles

| Statut | Cas d'usage | Detail |
|:------:|-------------|--------|
| PASS | config.json valide et coherent | interval=5s, focus=480min |
| PASS | rules.json : categories + regles presentes | 6 cats / 38 proc / 98 titre |
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
| PASS | Get-Categories renvoie la liste | 6 categories |
| PASS | Add-Category : nouvelle=true, doublon=false | ajout=True, doublon=False |
| PASS | Add-ProcessRule / Add-TitleRule augmentent les compteurs | proc 38->39, title 98->99 |
| PASS | Save-Rules + Load-Rules : persistance fidele | round-trip OK + regle active |

## D. Journalisation (logging)

| Statut | Cas d'usage | Detail |
|:------:|-------------|--------|
| PASS | Get-TodayLogFile : format activity-YYYY-MM-DD.csv | activity-2026-07-09.csv |
| PASS | Initialize-LogFile : entete ecrite une seule fois (idempotent) | 1 ligne d'entete |
| PASS | Write-ActivityLog : 10 colonnes dans le bon ordre | colonnes & valeurs OK |

## E. Reporting (math + cas limites)

| Statut | Cas d'usage | Detail |
|:------:|-------------|--------|
| PASS | Get-ReportData : focus score, total, switches, categories | total=100s focus=70% switches=7 |
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
| SKIP | tracker.ps1 : ecrit reellement des lignes en cours d'execution | requiert un bureau interactif (fenetre active) |
| SKIP | daily-report.ps1 : genere le summary JSON du jour | depend de donnees live du jour (saute avec tracker live) |
| PASS | dashboard-wpf.ps1 : XAML (fenetre principale + overlay) parse | 2/2 fenetres XAML valides |
| SKIP | dashboard-wpf.ps1 : se lance et affiche sa fenetre WPF | requiert un bureau interactif (fenetre WPF) |

## G. Ameliorations (AFK / verrou PID / focus configurable)

| Statut | Cas d'usage | Detail |
|:------:|-------------|--------|
| PASS | config.json : idleThresholdSeconds + focusCategories presents | idle=180s, focus=[travail] |
| PASS | rules.json : categorie 'inactif' presente | inactif present |
| PASS | Get-IdleSeconds renvoie un entier >= 0 | 306 s d'inactivite |
| PASS | Get-IsSessionLocked : LockApp -> verrouille, Code -> non | detection verrou OK |
| PASS | Measure-ContextSwitches : compte les transitions (A,A,B,A -> 2) | 2 transitions |
| PASS | Verrou PID : Set/Test/Remove (PID courant=actif, PID mort=inactif) | cycle verrou OK |
| PASS | Reporting : focusCategories inclut 'etude' | travail+etude = 100% focus |
| PASS | Reporting : 'inactif' exclu du temps actif (focus sur actif) | total=100s actif=50s focus=100% |
| SKIP | tracker.ps1 -Check : exit 0 quand lance (via verrou PID) | demarre un process tracker live |

## H. Taches (module de gestion & suivi)

| Statut | Cas d'usage | Detail |
|:------:|-------------|--------|
| PASS | New-Task : GUID + defauts (Statut A_faire, Priorite Normale, CreeLe) | Id=GUID statut=A_faire priorite=Normale |
| PASS | Save/Get : ecriture atomique + round-trip fidele | 2 taches, champs preserves |
| PASS | Save-Tasks : 1 seule tache reste un TABLEAU JSON | tableau JSON meme a 1 element |
| PASS | Get-Tasks : fichier absent -> tableau vide | absent -> @() |
| PASS | Get-Tasks : JSON corrompu -> @() + sauvegarde .bak | corrompu -> @() + .bak |
| PASS | Complete-Task : Statut=Termine + TermineLe | Termine + TermineLe pose |
| PASS | Archive-Task : Statut=Archive | Archive |
| PASS | Get-DueReminders : due & non-termine inclus, termine exclu | 1 due (termine/futur/sans rappel exclus) |
| PASS | Get-DueReminders : recurrence quotidienne via garde NotifieLe | gate aujourd'hui=0, hier=1 (recurrence) |
| PASS | Get-DueReminders : rappel date dans le futur ne se declenche pas avant | futur: 0 avant, 1 le jour J |
| PASS | Get-DueReminders : recurrence le soir, pas au matin | matin=0, soir=1 (timing du soir respecte) |
| PASS | Get-TaskSummary : compte a faire / en cours / termine auj / retard | AFaire=3 EnCours=1 TermAuj=1 Retard=1 |
| PASS | Get-TaskSummary : DateEcheance null ne plante pas | null echeance gere -> retard=0 |
| PASS | Initialize-TaskSeed : 8 taches + RappelSoir converti en datetime | 8 taches, 2 rappels a 20:00 |
| PASS | Initialize-TaskSeed : idempotent (ne re-seed pas) | 2e appel = no-op |
| PASS | Notify : Test-BurntToast renvoie un booleen (sans exception) | bool=False |
| PASS | Notify : Show-AfotraNotification -NoShow renvoie le backend | backend=NotifyIcon (aucune UI affichee) |
| PASS | Report : Export-ReportToJSON inclut la section Tasks quand fournie | section Tasks presente (AFaire=1) |

## I. Sessions & Pomodoro

| Statut | Cas d'usage | Detail |
|:------:|-------------|--------|
| PASS | Get-CountdownState : sous budget, depassement, sans cible | reste 180 / +60 / sans cible |
| PASS | Get-PomodoroBreakType : longue toutes les 4, courte sinon | 1=Short(5), 4=Long(15), 8=Long |
| PASS | Get-PomodoroConfig : defauts + surcharge partielle | defauts=25, surcharge=50 (repli conserve le reste) |
| PASS | Step-Session : accumulation travail + BreakDue au bout de workMinutes | work=30 a t30, BreakDue a t60 |
| PASS | Suspend/Resume : temps travail gele, temps global continue | travail=60, global=80, pause=20 (double comptage) |
| PASS | Cycle complet : travail hors pause vs global mur (Get-SessionResult) | travail=120, global=420, pause=300, 1 pomodoro |
| PASS | Add-TaskSession : accumule les totaux + journal + round-trip | 2 sessions, travail cumule=5400s |
| PASS | Get-TaskEfficiency : sous budget (ratio>1) et depassement (ratio<1) | sous budget ratio=2 / depassement ratio=0.67 |
| PASS | Get-TaskSummary : temps travaille du jour + nb depassements | 12 min aujourd'hui, 1 depassement |
| PASS | Retro-compat : tache sans champs de session toleree | vieille tache: session ajoutee sans crash |

## J. Assistant orbe & garde-focus

| Statut | Cas d'usage | Detail |
|:------:|-------------|--------|
| PASS | Get-OrbMood : humeur selon session + garde | Idle/Focus/Overrun/Break/Ask/Resume OK |
| PASS | Get-OrbVisual : humeur Resume distincte (appelle a reprendre) | Resume: vert, plus gros, pulse rapide |
| PASS | Get-OrbVisual : tailles Ask > Overrun > Focus > Idle + recentrage Ask | idle=92 focus=112 over=126 ask=420, recentre Ask |
| PASS | Get-OrbVisual : Ask grossit avec l'intensite | 180 -> 420 |
| PASS | Test-ProcessAllowed : liste, casse, AFOTRA tolere | non-liste bloque, casse OK, AFOTRA/powershell tolere |
| PASS | Add-TaskTool : ajout + dedup (casse) + round-trip | 2 outils (Code, figma), dedup casse OK |
| PASS | Add-TaskDigression : incremente le compteur | digressions=2 |
| PASS | Add-TaskTool : tolere une tache sans le champ OutilsTache | vieille tache toleree |

---

**Total : 76/76 reussis.** Genere par `Run-Full-Tests.ps1`.

