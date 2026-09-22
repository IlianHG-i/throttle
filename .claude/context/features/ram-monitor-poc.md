# Feature: ram-monitor-poc

## Objectif
POC d'app macOS native (SwiftUI, buildee en 100% CLI, sans Xcode) qui affiche
la conso RAM/CPU du systeme et liste les applications (avec Dock icon), avec
un bouton pause/reprise par app pour liberer de la RAM.

## Fichiers concernes
- `Package.swift` — target executable `RAMBrider` + target systemLibrary `CLibProc`
- `Sources/CLibProc/` — shim module exposant `<libproc.h>` (pas dans le module Darwin par defaut)
- `Sources/RAMBrider/SystemMonitor.swift` — coeur : sampling CPU/RAM systeme (Mach host_statistics)
  et par-app (proc_pid_rusage), detection etat suspendu (sysctl KERN_PROC / p_stat == SSTOP),
  pause/reprise via kill(SIGSTOP/SIGCONT)
- `Sources/RAMBrider/AppInfo.swift` — modele + liste d'apps protegees (non suspendables)
- `Sources/RAMBrider/ContentView.swift`, `AppRowView.swift` — UI SwiftUI
- `Scripts/build_app.sh` — build release, bundling `.app`, signature

## Decisions
- **`NSRunningApplication.suspend()/resume()` ont ete retires du SDK macOS 26** (ne compilent plus).
  Remplace par `kill(pid, SIGSTOP)` / `kill(pid, SIGCONT)` — c'est le mecanisme sous-jacent que ces
  methodes utilisaient de toute facon. Valide manuellement sur Calculator (S -> T -> S).
- `proc_pid_rusage` n'est pas expose par le module Darwin de Swift par defaut : necessite un
  target `systemLibrary` maison (`CLibProc`) avec un `module.modulemap` a la racine du target
  (pas dans `include/`, SPM l'exige a cet endroit precis).
- Utilise `ri_phys_footprint` (empreinte memoire reelle, comme Activity Monitor) plutot que
  `ri_resident_size` pour la RAM par app.
- Signature : utilise l'identite "Apple Development" locale si presente (`security find-identity`),
  sinon fallback signature ad-hoc (`codesign --sign -`). Pas de compte Developer payant necessaire
  pour un usage local uniquement.
- Seules les apps avec `activationPolicy == .regular` sont listees (apps avec icone Dock), pas les
  processus/daemons en arriere-plan — conforme a la demande "l'application entiere, pas les processus".
- Liste d'exclusion (non suspendables) : Finder, Dock, SystemUIServer, WindowManager, loginwindow,
  et l'app elle-meme.

## TODOs / suite possible
- Style/UI plus pousse (icone d'app, dark mode fin, animations) — demande explicitement remise a plus tard.
- Eventuel tri/filtre (par RAM, par CPU, recherche par nom).
- Icone .icns dediee pour le bundle (actuellement pas d'icone custom).
- Si publication en dehors de cette machine : passer a une vraie signature Developer ID + notarization.
