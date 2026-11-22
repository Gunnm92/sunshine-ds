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
- script d'ouverture de `/sys/devices/platform/vhci_hcd.0/attach` et
  `detach` au groupe de l'utilisateur de Sunshine (à venir).

## Prérequis côté hôte et conteneur

- modules `vhci-hcd` et `snd-usb-audio` chargés **avant** le démarrage du
  conteneur ;
- `/sys/devices/platform/vhci_hcd.0` monté en écriture dans le conteneur ;
- accès ALSA (`c 116:*`) et création des nœuds `/dev/snd/*` et
  `/dev/hidraw*` pour les périphériques branchés à chaud.

Utilisation prévue : [SteamBox](https://github.com/Gunnm92/SteamBox) récupère
la release à la place de son étape `sunshine-usb`.

## État

Projet créé le 22/11/2026, rien de compilé pour l'instant. Plan et
avancement : phase 2 de
[ds5-usbip/docs/plan.md](https://github.com/Gunnm92/ds5-usbip/blob/main/docs/plan.md).

## Licences

Sunshine est sous GPL v3 : ce dépôt publie le code et les correctifs qui
produisent les binaires distribués. libvirtualhid et ds5-usbip : voir leurs
dépôts.
