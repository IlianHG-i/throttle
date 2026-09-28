# Throttle

App macOS native (SwiftUI) qui affiche la consommation RAM/CPU du Mac **par application** et permet de mettre en pause les applis gourmandes sans les fermer. Pensée pour les petites configs (8 Go).

> L'app est pour l'instant buildée sous le nom `RAMBrider.app` (nom de code du POC).

## Fonctionnalités

- Icône dans la barre de menus avec le pourcentage de RAM utilisée ; un clic ouvre le panneau (pas d'icône dans le Dock). Le bouton power du panneau quitte l'app.
- Jauges RAM et CPU système en direct (rafraîchies chaque seconde).
- Liste façon gestionnaire des tâches Windows : une ligne par **application** (pas par processus), triée de la plus gourmande à la moins gourmande.
- CPU et RAM agrégés sur tout l'arbre de processus de l'appli (les applis Electron/Chromium comme Discord ou Firefox comptent leurs processus auxiliaires).
- **Pause / reprise** par appli, et bouton **Reprendre tout** en secours.
- **Quitter** une appli en un clic (l'appli est d'abord reprise si elle était en pause). Fermeture normale en priorité, puis forcée automatiquement si l'appli traîne des pieds ou ignore la demande (certains agents comme Microsoft AutoUpdate le font).
- Applis critiques protégées (Finder, Dock, SystemUIServer...).
- Lancement automatique à la connexion (LaunchAgent).

## Ce que fait vraiment la pause

La pause envoie `SIGSTOP` à tout l'arbre de processus de l'appli, la reprise envoie `SIGCONT`.

- Le **CPU tombe à 0 % immédiatement**.
- La **RAM ne baisse pas immédiatement**. macOS ne compresse la mémoire d'un processus que sous pression mémoire, selon son propre calendrier. La pause rend la mémoire candidate à la récupération et l'empêche de grossir, mais ne la libère pas d'un coup. Aucune API publique ne permet de forcer ça sur un autre processus (testé : forcer 3 Go de pression mémoire n'a rien changé).
- Pour récupérer la RAM tout de suite, il faut **quitter** l'appli.

Une appli en pause apparaît figée : c'est normal. Reprends-la depuis Throttle plutôt que de la relancer depuis le Dock.

## Installation

Aucun besoin d'ouvrir Xcode, tout se fait en ligne de commande (Swift 5.10+, macOS 13+) :

```bash
git clone https://github.com/IlianHG-i/throttle.git
cd throttle
./Scripts/install.sh
```

`install.sh` compile, signe, copie l'app dans `/Applications` et l'enregistre comme item de démarrage. La signature utilise l'identité « Apple Development » de la machine si elle existe, sinon une signature ad-hoc.

Pour builder sans installer :

```bash
./Scripts/build_app.sh
open dist/RAMBrider.app
```

Pour désactiver le démarrage automatique :

```bash
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.ilianhg.RAMBrider.plist
rm ~/Library/LaunchAgents/com.ilianhg.RAMBrider.plist
```

## Développement

```bash
swift build           # compilation debug
swift run RAMBrider   # lance sans passer par le bundle .app
```

## Structure

- `Sources/RAMBrider/` : app SwiftUI (vues, modèle, monitoring système)
- `Sources/CLibProc/` : module système exposant `libproc.h` à Swift (`proc_pid_rusage`, `proc_listchildpids`)
- `Scripts/build_app.sh` : build, bundle `.app`, signature
- `Scripts/install.sh` : build + installation + démarrage auto

## Limites

- Seules les applis avec une icône Dock sont listées. Le CPU total de la jauge inclut aussi les processus système (WindowServer, kernel_task...) non listés.
- Pas de sandbox : l'app envoie des signaux à d'autres processus, ce qui ne marche que sur ceux de l'utilisateur courant.
