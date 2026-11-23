# syntax=docker/dockerfile:1
# sunshine-ds : Sunshine compilé avec la DualSense USB/IP (voir README).
#
# Chaîne (une étape par rôle, make build les enchaîne) :
#   base   toolchain CachyOS (même base que SteamBox)
#   src    Sunshine au tag, libvirtualhid au commit de Sunshine, ds5-usbip ;
#          apply.sh de ds5-usbip pose le backend USB/IP dans libvirtualhid,
#          puis les deux seds Sunshine et les patches de patches/sunshine/
#   test   tests de libvirtualhid (échec = build en échec)
#   build  Sunshine compilé avec la libvirtualhid patchée, archive
#   unit   tests unitaires de Sunshine (SUNSHINE_TEST_FILTER, échec = build en
#          échec) et clang-tidy sur les fichiers des patches (rapport out/)
#   check  archive installée sur une image fraîche : ldd, backend, web UI
#   collect / scratch : seuls /out/* sortent (make build -> out/)
#
# Arguments :
#   SUNSHINE_TAG   tag Sunshine, vide = dernier tag v*
#   DS5_USBIP_REF  branche, tag ou commit de ds5-usbip (défaut main)
#   LVH_COMMIT     commit libvirtualhid, vide = celui de package-lock.cmake
#   REQUIRE_USBIP  1 (défaut) : le binaire doit contenir le backend USB/IP
#                  (chaîne LIBVIRTUALHID_DUALSENSE_USBIP, patch 0002) ;
#                  0 tant que ce patch n'est pas prêt.
#   SUNSHINE_TEST_FILTER  filtre gtest des tests unitaires de Sunshine lancés
#                  (ceux des patches et des fichiers qu'ils touchent ; les
#                  autres demandent GPU, écran ou périphériques).
ARG CACHYOS_BASE=cachyos/cachyos-v3:latest
ARG SUNSHINE_TAG=""
ARG DS5_USBIP_REF=main
ARG LVH_COMMIT=""
ARG REQUIRE_USBIP=1
ARG SUNSHINE_TEST_FILTER="DualsenseSettingsTest.*:InputGamepadSessionTest.*:NetworkClassificationTest.*"

# ── Base commune : toolchain + DisableSandboxNetwork (sans lui, pacman refuse
# les hooks dans une étape de build — voir SteamBox/Dockerfile.prebuilt).
FROM ${CACHYOS_BASE} AS base
SHELL ["/bin/bash", "-eo", "pipefail", "-c"]
RUN sed -i '/^\[options\]/a DisableSandboxNetwork' /etc/pacman.conf && \
    grep -q '^DisableSandboxNetwork' /etc/pacman.conf || { echo "FATAL: DisableSandboxNetwork non appliqué"; exit 1; }
RUN --mount=type=cache,target=/var/cache/pacman/pkg \
    pacman -Syu --needed --noconfirm --noprogressbar base-devel git cmake zstd

# ── src : sources figées et patchées.
# Paquets : ceux de SteamBox (Sunshine, CUDA) + ceux de libvirtualhid
# (Dockerfile.test de ds5-usbip : SDL3 et X11 se configurent via CPM, les
# dépendances manquantes font échouer la configuration).
# Les métadonnées (tag, commits) vont dans /meta, lues par build et test.
# patches/sunshine/*.patch : correctifs Sunshine (DualSense, web UI), appliqués
# dans l'ordre après les seds ; un patch qui ne s'applique plus casse le build.
FROM base AS src
SHELL ["/bin/bash", "-eo", "pipefail", "-c"]
ARG SUNSHINE_TAG
ARG DS5_USBIP_REF
ARG LVH_COMMIT
RUN --mount=type=cache,target=/var/cache/pacman/pkg \
    pacman -S --needed --noconfirm --noprogressbar \
      boost boost-libs nodejs npm shaderc appstream appstream-glib desktop-file-utils \
      python-jinja cuda sunshine \
      clang ninja pkgconf glib2 libevdev libinput sdl2 libx11 libxtst libxcursor \
      libxext libxi libxkbcommon libxrandr libxss vulkan-headers wayland wayland-protocols
COPY patches/sunshine /patches/sunshine
RUN set -e; \
    tag="${SUNSHINE_TAG}"; \
    if [ -z "${tag}" ]; then \
      tag=$(git ls-remote --tags --refs https://github.com/LizardByte/Sunshine.git 'v*' \
            | sed 's|.*refs/tags/||' | sort -V | tail -1); \
    fi; \
    [ -n "${tag}" ] || { echo "FATAL: aucun tag Sunshine trouvé"; exit 1; }; \
    echo "Sunshine ${tag}"; \
    git clone --quiet --depth 1 --branch "${tag}" --recurse-submodules --shallow-submodules \
      https://github.com/LizardByte/Sunshine.git /src; \
    mkdir -p /meta; \
    printf '%s\n' "${tag}" > /meta/sunshine-tag; \
    git -C /src rev-parse HEAD > /meta/sunshine-commit; \
    \
    # libvirtualhid : commit imposé, sinon celui que Sunshine épingle.
    f=$(find /src -name package-lock.cmake | head -1); \
    [ -n "${f}" ] || { echo "FATAL: package-lock.cmake absent de Sunshine ${tag}"; exit 1; }; \
    lvh="${LVH_COMMIT}"; \
    if [ -z "${lvh}" ]; then lvh=$(grep -oP 'LIBVIRTUALHID_COMMIT\D*\K[0-9a-f]{40}' "${f}" | head -1 || true); fi; \
    [ -n "${lvh}" ] || { echo "FATAL: LIBVIRTUALHID_COMMIT introuvable dans ${f}"; exit 1; }; \
    git clone --quiet https://github.com/LizardByte/libvirtualhid.git /lvh; \
    git -C /lvh checkout --quiet "${lvh}"; \
    git -C /lvh submodule update --quiet --init --recursive; \
    lvh=$(git -C /lvh rev-parse HEAD); \
    printf '%s\n' "${lvh}" > /meta/lvh-commit; \
    \
    # ds5-usbip : src/usbip (backend) et libvirtualhid/apply.sh (le posera).
    git clone --quiet https://github.com/Gunnm92/ds5-usbip.git /ds5; \
    git -C /ds5 checkout --quiet "${DS5_USBIP_REF}"; \
    ds5=$(git -C /ds5 rev-parse HEAD); \
    printf '%s\n' "${DS5_USBIP_REF}" > /meta/ds5-usbip-ref; \
    printf '%s\n' "${ds5}" > /meta/ds5-usbip-commit; \
    /ds5/libvirtualhid/apply.sh /lvh; \
    \
    # Patch Sunshine 1 : la DualSense virtuelle en USB, pas en Bluetooth.
    # Explication : voir le commentaire de SteamBox (Dockerfile.prebuilt, étape
    # sunshine-usb). Le motif est exact : une seule occurrence attendue.
    f=/src/src/platform/virtualhid_input.cpp; \
    sed -i 's|{"ds5", lvh::GamepadProfileKind::dualsense, lvh::profiles::dualsense}|{"ds5", lvh::GamepadProfileKind::dualsense, lvh::profiles::dualsense_usb}|' "${f}"; \
    grep -q 'lvh::profiles::dualsense_usb}' "${f}" || { echo "FATAL: patch DualSense USB non appliqué (Sunshine ${tag})"; exit 1; }; \
    \
    # Patch Sunshine 2 : latence des vibrations et effets de gâchette.
    # controlBroadcastThread attend jusqu'à 150 ms dans enet_host_service : la
    # file des retours manette n'est vidée qu'à chaque tour. 5 ms ramène le
    # pire cas de 100 ms (ping Moonlight) à 5 ms, pour ~200 réveils/s d'une
    # boucle très légère. L'envoi lui-même est déjà immédiat (enet_host_flush).
    f=/src/src/stream.cpp; \
    sed -i 's|server->iterate(150ms);|server->iterate(5ms);|' "${f}"; \
    grep -q 'server->iterate(5ms);' "${f}" || { echo "FATAL: patch latence vibrations non appliqué (Sunshine ${tag})"; exit 1; }; \
    \
    # Patches sunshine-ds (patches/sunshine, ordre alphabétique = ordre de numérotation).
    for p in /patches/sunshine/*.patch; do \
      name=$(basename "${p}"); \
      git -C /src apply --check "${p}" || { echo "FATAL: patch ${name} does not apply to Sunshine ${tag}"; exit 1; }; \
      git -C /src apply "${p}"; \
      echo "patch ${name} appliqué"; \
    done; \
    echo "libvirtualhid ${lvh} · ds5-usbip ${ds5} (${DS5_USBIP_REF})"

# ── test : tests de libvirtualhid (même configuration et mêmes exclusions que
# Dockerfile.test de ds5-usbip). Pas de /dev/uhid ni /dev/uinput dans le build :
# ces tests-là sont exclus, tout le reste doit passer.
FROM src AS test
SHELL ["/bin/bash", "-eo", "pipefail", "-c"]
ENV LVH_DEVICE_TESTS='^(LinuxRuntimeTest\.LinuxUhidSmokeTestRequiresPrerequisites|LinuxRuntimeTest\.LinuxUinputSmokeTestRequiresPrerequisites|LinuxConsumerTest\.(SdlSeesGenericCanonicalButtons|SdlSeesXbox360CanonicalButtons|SdlSeesXboxOneCanonicalButtons|SdlSeesXboxGuideChordsWithXpadneoShiftMode|SdlSeesXboxSeriesCanonicalButtons|Sdl3SeesXboxOneIdentityMappingsAndFourMotorRumble|Sdl3SeesXboxSeriesIdentityMappingsAndFourMotorRumble|SdlSeesSwitchProCanonicalButtons|SdlKeepsIdleSwitchProConnected|SdlSeesDualSenseUsbControllerBehavior|SdlSeesDualShock4UsbControllerBehavior|SdlSeesDualShock4BluetoothControllerBehavior|SdlSeesDualSenseBluetoothControllerDiscovery|LibinputSeesUinputKeyboardKeys|UinputKeyboardKeepsReleasedKeyUpUnderRapidTransitions|LibinputSeesSplitUinputMouseMotionAndButtons|LibinputSeesUinputTouchscreenContacts|LibinputSeesUinputTrackpadButton|LibinputSeesUinputPenTabletTool))$'
RUN cmake -S /lvh -B /lvh/build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_TESTS=ON \
      -DBUILD_DOCS=OFF \
      -DLIBVIRTUALHID_WARNINGS_AS_ERRORS=ON && \
    cmake --build /lvh/build --parallel && \
    ctest --test-dir /lvh/build --output-on-failure --no-tests=error -E "${LVH_DEVICE_TESTS}" && \
    mkdir -p /stamp && \
    echo "libvirtualhid $(cat /meta/lvh-commit) : ctest OK (exclusions LVH_DEVICE_TESTS)" > /stamp/lvh-tests.txt

# ── build : Sunshine avec la libvirtualhid patchée (CPM_libvirtualhid_SOURCE).
# Flags repris de SteamBox (Dockerfile.prebuilt, étape sunshine-usb), avec
# -DCPM_libvirtualhid_SOURCE pour utiliser /lvh au lieu de le télécharger.
# Sortie : /pkg = usr/bin/sunshine (strip) + usr/share/sunshine + overlay/.
# BUILD_TESTS=ON et compile_commands.json pour l'étape unit ; seule la cible
# sunshine et la web UI sont compilées ici.
FROM src AS build
SHELL ["/bin/bash", "-eo", "pipefail", "-c"]
COPY overlay /overlay
RUN set -e; \
    tag=$(cat /meta/sunshine-tag); ver="${tag#v}"; \
    commit=$(cat /meta/sunshine-commit); \
    lvh=$(cat /meta/lvh-commit); ds5=$(cat /meta/ds5-usbip-commit); ds5ref=$(cat /meta/ds5-usbip-ref); \
    export BRANCH=master BUILD_VERSION="${ver}" COMMIT="${commit}" \
           CC=gcc CXX=g++ CUDA_PATH=/opt/cuda PATH="/opt/cuda/bin:$PATH" NVCC_CCBIN=/usr/bin/g++; \
    cmake -S /src -B /build -Wno-dev -D BUILD_DOCS=OFF -D BUILD_WERROR=OFF -D BUILD_TESTS=ON -D CMAKE_EXPORT_COMPILE_COMMANDS=ON \
      -D CMAKE_BUILD_TYPE=Release -D CMAKE_INSTALL_PREFIX=/usr \
      -D SUNSHINE_EXECUTABLE_PATH=/usr/bin/sunshine -D SUNSHINE_ASSETS_DIR=share/sunshine \
      -D SUNSHINE_PUBLISHER_NAME=LizardByte -D SUNSHINE_PUBLISHER_WEBSITE=https://app.lizardbyte.dev \
      -D SUNSHINE_PUBLISHER_ISSUE_URL=https://app.lizardbyte.dev/support \
      -D CPM_libvirtualhid_SOURCE=/lvh; \
    cmake --build /build --target sunshine web-ui -j "$(nproc)"; \
    DESTDIR=/root-install cmake --install /build >/dev/null; \
    [ -f /root-install/usr/share/sunshine/web/index.html ] || { echo "FATAL: web UI absente de l'installation Sunshine ${tag}"; exit 1; }; \
    install -Dm755 -s /build/sunshine /pkg/usr/bin/sunshine; \
    mkdir -p /pkg/usr/share; \
    cp -a /root-install/usr/share/sunshine /pkg/usr/share/sunshine; \
    cp -a /overlay/. /pkg/; \
    mkdir -p /out; \
    tar --zstd -cf /out/sunshine-ds.tar.zst -C /pkg .; \
    lvh7=$(printf '%s' "${lvh}" | cut -c1-7); ds57=$(printf '%s' "${ds5}" | cut -c1-7); \
    echo "sunshine-ds ${tag} lvh ${lvh7} ds5-usbip ${ds57}" > /out/sunshine-ds.version; \
    { cat /out/sunshine-ds.version; \
      echo "sunshine        ${tag} (commit ${commit})"; \
      echo "libvirtualhid   ${lvh} (package-lock.cmake de Sunshine, ou LVH_COMMIT)"; \
      echo "ds5-usbip       ${ds5} (ref ${ds5ref})"; \
      echo "build           $(date -u +%Y-%m-%dT%H:%MZ)"; \
    } > /out/versions.txt; \
    cat /out/versions.txt

# ── unit : tests unitaires de Sunshine (arbre de build de l'étape build) et
# clang-tidy sur les fichiers C++ modifiés par les patches. Les tests cassent le
# build ; clang-tidy produit un rapport (out/clang-tidy.txt, hors release).
FROM build AS unit
SHELL ["/bin/bash", "-eo", "pipefail", "-c"]
ARG SUNSHINE_TEST_FILTER
RUN --mount=type=cache,id=pacman-unit,target=/var/cache/pacman/pkg \
    pacman -S --needed --noconfirm --noprogressbar clang
RUN set -e; \
    export CC=gcc CXX=g++ CUDA_PATH=/opt/cuda PATH="/opt/cuda/bin:$PATH" NVCC_CCBIN=/usr/bin/g++; \
    cmake --build /build --target test_sunshine -j "$(nproc)"; \
    mkdir -p /stamp /out; \
    (cd /build/tests && ./test_sunshine --gtest_filter="${SUNSHINE_TEST_FILTER}" --gtest_brief=1) | tee /out/unit-tests.txt; \
    echo "tests unitaires Sunshine OK (${SUNSHINE_TEST_FILTER})" > /stamp/unit-tests.txt; \
    files=$(sed -n 's|^diff --git a/\(.*\.cpp\) b/.*|\1|p' /patches/sunshine/*.patch | sort -u); \
    for f in ${files}; do \
      clang-tidy -p /build --quiet \
        --checks='-*,bugprone-use-after-move,clang-diagnostic-*,cppcoreguidelines-narrowing-conversions' \
        --extra-arg=-Wall --extra-arg=-Wno-unknown-warning-option "/src/${f}" 2>&1 || true; \
    done > /out/clang-tidy.txt; \
    echo "clang-tidy : $(grep -c -E ': (warning|error):' /out/clang-tidy.txt || true) diagnostics (out/clang-tidy.txt)"

# ── check : archive installée sur une image fraîche (dépendances d'exécution
# tirées des dépôts). Tout échec casse le build.
FROM ${CACHYOS_BASE} AS check
SHELL ["/bin/bash", "-eo", "pipefail", "-c"]
ARG REQUIRE_USBIP
RUN sed -i '/^\[options\]/a DisableSandboxNetwork' /etc/pacman.conf && \
    grep -q '^DisableSandboxNetwork' /etc/pacman.conf || { echo "FATAL: DisableSandboxNetwork non appliqué"; exit 1; }
# id distinct : cette étape tourne en parallèle de base (même cible sinon, pacman
# se marche sur ses fichiers .part dans le cache partagé).
RUN --mount=type=cache,id=pacman-check,target=/var/cache/pacman/pkg \
    pacman -Syu --needed --noconfirm --noprogressbar sunshine
COPY --from=build /out/sunshine-ds.tar.zst /tmp/sunshine-ds.tar.zst
RUN set -e; \
    tar --zstd -xf /tmp/sunshine-ds.tar.zst -C / --no-same-owner; \
    rm -f /tmp/sunshine-ds.tar.zst; \
    [ -x /usr/bin/sunshine ] || { echo "FATAL: /usr/bin/sunshine absent de l'archive"; exit 1; }; \
    ldd /usr/bin/sunshine > /tmp/ldd.txt 2>&1 || true; \
    if grep -q 'not found' /tmp/ldd.txt; then echo "FATAL: bibliothèques absentes :"; grep 'not found' /tmp/ldd.txt; exit 1; fi; \
    if [ "${REQUIRE_USBIP}" = 1 ]; then \
      grep -a -q LIBVIRTUALHID_DUALSENSE_USBIP /usr/bin/sunshine || { echo "FATAL: backend USB/IP absent du binaire (patch 0002 ?)"; exit 1; }; \
    else \
      echo "REQUIRE_USBIP=0 : contrôle du backend USB/IP ignoré"; \
    fi; \
    grep -a -q /api/dualsense /usr/bin/sunshine || { echo "FATAL: route /api/dualsense absente du binaire (patch 0002)"; exit 1; }; \
    [ -f /usr/share/sunshine/web/index.html ] || { echo "FATAL: web UI absente de l'archive"; exit 1; }; \
    grep -r -a -q DualSense /usr/share/sunshine/web || { echo "FATAL: page DualSense absente de la web UI (patch 0002)"; exit 1; }; \
    sh -n /usr/lib/sunshine-ds/vhci-permissions; \
    [ -f /etc/wireplumber/wireplumber.conf.d/52-ds5-usbip.conf ] || { echo "FATAL: règle wireplumber absente"; exit 1; }; \
    [ -f /etc/s6-overlay/s6-rc.d/init-sunshine-ds-vhci/up ] || { echo "FATAL: oneshot s6 absent"; exit 1; }; \
    mkdir -p /stamp; \
    echo "check OK (REQUIRE_USBIP=${REQUIRE_USBIP})" > /stamp/check.txt

# ── Export : seuls les fichiers de /out sortent (et les preuves de test/check,
# qui forcent ces étapes à tourner : un échec casse le build).
FROM ${CACHYOS_BASE} AS collect
SHELL ["/bin/bash", "-eo", "pipefail", "-c"]
COPY --from=build /out/ /out/
COPY --from=test /stamp/ /stamp/
COPY --from=check /stamp/ /stamp/
COPY --from=unit /stamp/ /stamp/
COPY --from=unit /out/unit-tests.txt /out/clang-tidy.txt /out/
RUN test -s /stamp/lvh-tests.txt && test -s /stamp/check.txt && test -s /stamp/unit-tests.txt && test -s /out/sunshine-ds.tar.zst

FROM scratch
COPY --from=collect /out/ /
