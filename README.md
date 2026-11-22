# sunshine-ds

Sunshine compilé avec une **DualSense USB/IP** : la manette virtuelle que
Sunshine crée pour un client Moonlight PlayStation devient une vraie
DualSense USB pour l'hôte (HID + carte son 4 canaux), branchée par
`vhci-hcd`. Les jeux y envoient leurs **haptiques HD**, transmises au PC
client en RTP.

Le backend USB/IP vient de [ds5-usbip](https://github.com/Gunnm92/ds5-usbip)
(modèle de DualSense, session USB/IP, haptiques RTP). Ce dépôt l'intègre à
[libvirtualhid](https://github.com/LizardByte/libvirtualhid), compile
[Sunshine](https://github.com/LizardByte/Sunshine) avec cette version, et
publie le résultat en release.

## Contenu d'une release

Une archive à décompresser à la racine du système cible :

- `usr/bin/sunshine` et `usr/share/sunshine/` : Sunshine avec le backend
  USB/IP (repli automatique sur `uhid` si `vhci-hcd` est absent) ;
- `etc/wireplumber/wireplumber.conf.d/52-ds5-usbip.conf` : sortie son de la
  DualSense à 100 % (sinon ses haptiques sont atténuées) et jamais sortie par
  défaut ;
- `usr/lib/sunshine-ds/vhci-permissions` : script qui ouvre
  `/sys/devices/platform/vhci_hcd.0/attach` et `detach` au groupe `input`
  (mode 0220), en sortant sans erreur si `vhci-hcd` est absent ou en lecture
  seule ;
- `etc/s6-overlay/s6-rc.d/init-sunshine-ds-vhci/` : oneshot s6 qui lance ce
  script au démarrage, et son entrée dans `user-bundles.d/user/contents.d/`.

Les archives portent le nom `sunshine-ds.tar.zst`, avec `sunshine-ds.version`
(une ligne : tag Sunshine, sha7 de libvirtualhid et de ds5-usbip) et
`versions.txt` (détail des versions, sert de notes de release).

## Build

```sh
make build                          # dernier tag Sunshine, ds5-usbip sur main
make build SUNSHINE_TAG=v2026.1122.155624
make build DS5_USBIP_REF=<branche|tag|commit> LVH_COMMIT=<commit>
make build REQUIRE_USBIP=0          # sans le contrôle du backend USB/IP
make clean                          # supprime out/
```

Arguments (variables `make`, transmises comme `--build-arg`) :

- `SUNSHINE_TAG` : tag Sunshine ; vide = dernier tag `v*` ;
- `DS5_USBIP_REF` : ref ds5-usbip (défaut `main` dans le Dockerfile) ;
- `LVH_COMMIT` : commit libvirtualhid ; vide = celui de `package-lock.cmake`
  de Sunshine ;
- `REQUIRE_USBIP` : 1 par défaut. Le contrôle final exige alors que le binaire
  contienne `LIBVIRTUALHID_DUALSENSE_USBIP` (patch 0002 de libvirtualhid, pas
  encore prêt) : passer `REQUIRE_USBIP=0` jusqu'à sa sortie ;
- `ARGS` : options `docker buildx build` supplémentaires, brutes.

Le build compile Sunshine avec CUDA : compter plusieurs dizaines de minutes
hors cache. Les sorties vont dans `out/` :
`sunshine-ds.tar.zst`, `sunshine-ds.version`, `versions.txt`.

Étapes : `src` (sources figées, patches), `test` (tests de libvirtualhid, un
échec casse le build), `build` (Sunshine), `check` (archive installée sur une
image fraîche : `ldd` sans bibliothèque manquante, backend USB/IP, web UI).

Docker : `make` appelle `docker-socket-proxy:2375` sans TLS. Les variables
`DOCKER_TLS_VERIFY` et `DOCKER_CERT_PATH` de la session sont retirées de
l'appel. Pour un autre démon, changer la variable `DOCKER` du Makefile.

## Release

```sh
make publish
```

Crée la release `sunshine-ds-<tag Sunshine>-<AAAAMMJJ-HHMM UTC>` sur
`Gunnm92/sunshine-ds` (`--latest`), avec les archives de `out/` et
`versions.txt` en notes. Il faut `gh` authentifié et un `out/` issu de
`make build`.

## Variables d'environnement (runtime)

Lues par la libvirtualhid patchée :

- `LIBVIRTUALHID_DUALSENSE_USBIP=1` : active le backend USB/IP pour la
  DualSense virtuelle (sinon uhid) ;
- `LIBVIRTUALHID_DUALSENSE_HAPTICS_RTP=ip:port` : destination RTP des
  haptiques (canaux 3-4, L16 stéréo 48 kHz, PT 127) ;
- `LIBVIRTUALHID_DUALSENSE_HAPTICS_GAIN` : gain appliqué aux haptiques avant
  envoi (écrêtage doux au-dessus de la demi-échelle) ;
- `LIBVIRTUALHID_DUALSENSE_HAPTICS_GAIN_FILE` : fichier contenant le gain
- `LIBVIRTUALHID_DUALSENSE_RTP_CHANNELS` : `4` envoie aussi le haut-parleur de la manette (canaux 1-2) ; défaut 2 (haptiques seules).
  (ex. `2.5`), relu toutes les secondes pour le changer en cours de route ;
- `LIBVIRTUALHID_VHCI_SYSFS` : racine sysfs de `vhci-hcd` utilisée par les
  tests (défaut `/sys/devices/platform/vhci_hcd.0`).

## Prérequis côté hôte et conteneur

- modules `vhci-hcd` et `snd-usb-audio` chargés **avant** le démarrage du
  conteneur ;
- `/sys/devices/platform/vhci_hcd.0` monté en écriture dans le conteneur ;
- accès ALSA (`c 116:*`) et création des nœuds `/dev/snd/*` et
  `/dev/hidraw*` pour les périphériques branchés à chaud.

Utilisation prévue : [SteamBox](https://github.com/Gunnm92/SteamBox) récupère
la release à la place de son étape `sunshine-usb`.

## État

Projet créé le 22/11/2026. Pipeline de build et de release en place ; le
backend USB/IP complet attend le patch 0002 de libvirtualhid (`REQUIRE_USBIP=0`
d'ici là). Plan et avancement : phase 2 de
[ds5-usbip/docs/plan.md](https://github.com/Gunnm92/ds5-usbip/blob/main/docs/plan.md).

## Licences

Sunshine est sous GPL v3 : ce dépôt publie le code et les correctifs qui
produisent les binaires distribués. libvirtualhid et ds5-usbip : voir leurs
dépôts.
