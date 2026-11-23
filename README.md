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

Côté Sunshine, trois correctifs sont appliqués au tag (`patches/sunshine/`) :

- `0001` : destination des haptiques automatique (adresse du client Moonlight)
  et emplacement des fichiers de réglages et d'état ;
- `0002` : page **DualSense** dans la web UI et API `/api/dualsense` ;
- `0003` : manette recréée au bon type à son arrivée. Sans lui, une manette
  créée avant le paquet d'arrivée de Moonlight (type inconnu → Xbox) ou
  gardée d'une connexion précédente restait une Xbox pour un client DualSense,
  sur plusieurs reconnexions. À proposer en amont (tests unitaires inclus,
  non exécutés par ce build : `BUILD_TESTS=OFF`).

## Contenu d'une release

Une archive à décompresser à la racine du système cible :

- `usr/bin/sunshine` et `usr/share/sunshine/` : Sunshine avec le backend
  USB/IP (repli automatique sur `uhid` si `vhci-hcd` est absent) et la page
  DualSense de la web UI ;
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

Les patches `patches/sunshine/*.patch` sont appliqués dans l'ordre sur le tag
Sunshine après les deux `sed` (étape `src`). Un patch qui ne s'applique plus
arrête le build avec `FATAL: patch <nom> does not apply to Sunshine <tag>`.
Le build complet exige le patch 0003 de libvirtualhid (champ
`GamepadMetadata::haptics_destination`).

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
  haptiques (canaux 3-4, L16 stéréo 48 kHz, PT 127). Fixée, elle **force** la
  destination, quel que soit le client ; sans elle, la destination est
  automatique (voir ci-dessous) ;
- `LIBVIRTUALHID_DUALSENSE_HAPTICS_PORT` : port des haptiques quand la
  destination est automatique (défaut `46100`) ;
- `LIBVIRTUALHID_DUALSENSE_SETTINGS` : fichier de réglages lu par le pilote,
  lignes `clé=valeur` (`gain`, `channels`). Défaut au démarrage :
  `dualsense.conf` dans le dossier de `sunshine.conf` ;
- `LIBVIRTUALHID_DUALSENSE_STATUS` : fichier d'état JSON réécrit par le pilote
  (une fois par seconde). Défaut au démarrage : `dualsense-status.json` dans
  le dossier de `sunshine.conf` ;
- `LIBVIRTUALHID_DUALSENSE_HAPTICS_GAIN` : gain appliqué aux haptiques avant
  envoi (écrêtage doux au-dessus de la demi-échelle) ;
- `LIBVIRTUALHID_DUALSENSE_HAPTICS_GAIN_FILE` : fichier contenant le gain
- `LIBVIRTUALHID_DUALSENSE_RTP_CHANNELS` : `4` envoie aussi le haut-parleur de la manette (canaux 1-2) ; défaut 2 (haptiques seules). Valeur par défaut de la page DualSense, remplacée par le fichier de réglages dès qu'il existe ;
- `LIBVIRTUALHID_VHCI_SYSFS` : racine sysfs de `vhci-hcd` utilisée par les
  tests (défaut `/sys/devices/platform/vhci_hcd.0`).

### Destination automatique des haptiques

Quand `LIBVIRTUALHID_DUALSENSE_HAPTICS_RTP` n'est pas défini, la DualSense
virtuelle envoie ses haptiques à l'adresse IP du client Moonlight de la
session, sur le port `LIBVIRTUALHID_DUALSENSE_HAPTICS_PORT` (défaut `46100`).
Seules les adresses IPv4 sont retenues (`::ffff:a.b.c.d` compte comme IPv4) :
en IPv6 pur, le pilote garde sa destination par défaut. Une ligne d'information
indique la destination choisie à chaque création de manette.

### Page DualSense (web UI)

Entrée **DualSense** du menu, à côté de Configuration. Elle affiche :

- l'état du pilote : branchée ou non, port vhci, destination, canaux, gain,
  nombre de paquets (lus dans `LIBVIRTUALHID_DUALSENSE_STATUS`) ;
- les niveaux de crête des quatre canaux (haut-parleur G/D, haptiques G/D),
  rafraîchis chaque seconde ;
- le réglage des canaux (2 : haptiques seules, 4 : haut-parleur et haptiques ;
  appliqué à la prochaine connexion) et du gain (0 à 4, appliqué à chaud).

L'API sous-jacente est `GET /api/dualsense` (réglages et état) et
`POST /api/dualsense` avec `{"gain": F, "channels": 2|4}` (validation : gain
strictement supérieur à 0 et au plus 64, canaux 2 ou 4 ; écriture atomique du fichier de
réglages). Comme les autres points de l'API, elles demandent l'authentification
et le jeton CSRF.

## Prérequis côté hôte et conteneur

- modules `vhci-hcd` et `snd-usb-audio` chargés **avant** le démarrage du
  conteneur ;
- `/sys/devices/platform/vhci_hcd.0` monté en écriture dans le conteneur ;
- accès ALSA (`c 116:*`) et création des nœuds `/dev/snd/*` et
  `/dev/hidraw*` pour les périphériques branchés à chaud.

Utilisation prévue : [SteamBox](https://github.com/Gunnm92/SteamBox) récupère
la release à la place de son étape `sunshine-usb`.

## État

Validé en direct le 22/11/2026 sur SteamBox : la DualSense USB/IP est créée
à chaque connexion Moonlight, ses haptiques HD sont reçues sur le client.
Dernière release : voir les releases GitHub (`make build && make publish`).
Suivi : [ds5-usbip/docs/plan.md](https://github.com/Gunnm92/ds5-usbip/blob/main/docs/plan.md).

## Licences

Sunshine est sous GPL v3 : ce dépôt publie le code et les correctifs qui
produisent les binaires distribués. libvirtualhid et ds5-usbip : voir leurs
dépôts.
