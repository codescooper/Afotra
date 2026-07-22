# AFOTRA - Awema Focus Tracker

**Derniere MAJ : 2026-07-16**
> Statut apres stabilisation des sessions actives, du live tracking et des rapports.

## Phase
Stabilisation fonctionnelle de la v2.1 : dashboard WPF, taches, sessions Pomodoro, rapports, tracking live et assistant focus guard.

## Etat actuel
- [x] Le dashboard WPF se lance avec la fenetre principale declaree explicitement comme `Application.MainWindow`.
- [x] Les exceptions WPF et evenements critiques de session sont traces dans `logs/dashboard-runtime.log`.
- [x] Le live tracking demarre automatiquement avec une session de tache et ecrit `logs/activity-YYYY-MM-DD.csv`.
- [x] Le bouton overlay affiche maintenant `Live ON/OFF` au lieu d'un ambigu `Start`.
- [x] Les sessions actives sont sauvegardees chaque seconde dans `logs/session-current.json` et recuperees au redemarrage.
- [x] Le passage Pomodoro ne force plus une pause automatique : il suggere une pause et laisse la session continuer en depassement.
- [x] Le dashboard et l'overlay utilisent la meme source de temps (`SessionReadout`) pour eviter les compteurs divergents.
- [x] Les jalons temps affichent une bulle mascotte : 10 min ecoulees, puis 5 min restantes.
- [x] Les rapports filtrent maintenant les vraies sessions au lieu d'inclure des taches sans session.
- [x] Le rapport du jour `summary-2026-07-16.json` a ete genere avec les donnees live et les sessions de taches.
- [x] Suite complete relancee le 2026-07-16 : **81/81 tests reussis**, **4 tests live/bureau sautes** (`TEST_REPORT.md`).
- [x] Parser PowerShell : **18 fichiers OK**.

## Ce qui reste a valider
- [ ] Validation live longue : laisser tourner une session complete 25+ min, confirmer que la fenetre reste ouverte, que le checkpoint disparait apres arret propre et que la session est persistee une seule fois.
- [ ] Validation visuelle reelle : boutons grises, selection de tache, scrollbars, taille min/max, overlay et bulles sur plusieurs tailles d'ecran.
- [ ] Validation focus guard/orbe : pendant une session, ouvrir un outil non autorise, tester Oui / Non / Ignorer et verifier l'escalade.
- [ ] Validation rappels du soir et notifications hors app via `afotra-notify.ps1` / Task Scheduler.
- [ ] Ajouter des tests automatises pour les nouveaux helpers dashboard : session active incluse dans rapports, filtre de sessions reelles, libelle overlay `Live ON/OFF`.
- [ ] Nettoyer les docs v1 restantes (`Readme.md`, `QUICK_START.md`, `DELIVERY_REPORT.md`) et les mentions `ExecutionPolicy Bypass` dans les tests/docs.

## Risques connus
- Les 4 tests live/bureau sont volontairement sautes en automatique : ils demandent un vrai bureau interactif.
- `dashboard-wpf.ps1` contient un gros changement non commit : risque principal = regression UI observee seulement a l'usage.
- Le script `daily-report.ps1` n'inclut pas une session active en memoire ; le bouton dashboard le fait. Une session doit etre arretee ou recuperee depuis checkpoint pour apparaitre dans le rapport CLI.
- La logique WPF reste concentree dans un tres gros fichier, ce qui rend les regressions UI plus probables.
- Plusieurs fichiers sont modifies dans le working tree ; il faut committer par lots propres avant de considerer la version stabilisee.

## Prochaine etape recommandee
Faire une validation live guidee : demarrer une session courte, verifier `Live ON`, laisser 2-3 minutes, generer un rapport depuis le dashboard, arreter la session, puis verifier que la colonne `Passe`, le rapport de tache et `summary-YYYY-MM-DD.json` racontent la meme histoire.

## Stack & structure
PowerShell 5.1+ sur Windows, dashboard WPF principal (`dashboard-wpf.ps1`), helper WinForms legacy (`modules/UI.Core.psm1`), modules purs sous `modules/`, stockage local `logs/`, `logs/reports/`, `tasks.json` gitignore, CI Windows via GitHub Actions.
