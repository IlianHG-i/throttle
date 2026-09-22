# RAM Brider

App macOS native (SwiftUI) pour surveiller la RAM/CPU du systeme et mettre en pause des applications pour liberer de la memoire, sans jamais ouvrir Xcode.

## Fonctionnement

- Liste les applications avec interface (Dock) via `NSWorkspace.runningApplications`, pas les processus systeme.
- Memoire/CPU par application lues via `proc_pid_rusage` (libproc), RAM/CPU systeme via les API Mach (`host_statistics`/`host_statistics64`).
- Mettre en pause une application envoie `SIGSTOP` (comme le fait le systeme quand il compresse la memoire des apps en arriere-plan) ; reprendre envoie `SIGCONT`.
- Quelques applications critiques (Finder, Dock, SystemUIServer, RAM Brider elle-meme) sont protegees et ne peuvent pas etre mises en pause.

## Build & run

Tout se fait en ligne de commande, aucun besoin d'Xcode :

```bash
./Scripts/build_app.sh
open dist/RAMBrider.app
```

Le script compile en release, assemble `dist/RAMBrider.app` et le signe : avec l'identite "Apple Development" installee sur la machine si elle existe, sinon en signature ad-hoc.

## Developpement

```bash
swift build          # compilation debug rapide
swift run RAMBrider   # lance directement sans passer par le bundle .app
```

## Structure

- `Sources/RAMBrider/` : app SwiftUI (vue, modele, monitoring systeme)
- `Sources/CLibProc/` : shim de module systeme exposant `libproc.h` (pour `proc_pid_rusage`) a Swift
- `Scripts/build_app.sh` : build + bundling `.app` + signature
