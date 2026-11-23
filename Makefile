# Pipeline de release sunshine-ds (voir README.md).
#
# DOCKER : la session porte des variables TLS qui cassent le proxy de socket
# (docker-socket-proxy:2375 sans TLS) : elles sont retirées ici.
DOCKER ?= env -u DOCKER_TLS_VERIFY -u DOCKER_CERT_PATH DOCKER_HOST=tcp://docker-socket-proxy:2375 docker
REPO ?= Gunnm92/sunshine-ds

# Arguments de build, passés seulement s'ils sont définis.
# Références résolues AVANT le build (dernier tag v* de Sunshine, commit de la
# branche main de ds5-usbip) : passées en arguments, elles changent la clé de
# cache de l'étape src dès qu'elles bougent. Sans ça, `git clone … main` en
# cache garderait un ancien ds5-usbip (vu le 22/11).
SUNSHINE_TAG ?= $(shell git ls-remote --tags --refs https://github.com/LizardByte/Sunshine.git 'v*' | sed 's|.*refs/tags/||' | sort -V | tail -1)
DS5_USBIP_REF ?= $(shell git ls-remote https://github.com/Gunnm92/ds5-usbip.git refs/heads/main | cut -f1)
LVH_COMMIT ?=
REQUIRE_USBIP ?=
SUNSHINE_TEST_FILTER ?=
BUILD_ARGS := \
  $(if $(SUNSHINE_TAG),--build-arg SUNSHINE_TAG=$(SUNSHINE_TAG)) \
  $(if $(DS5_USBIP_REF),--build-arg DS5_USBIP_REF=$(DS5_USBIP_REF)) \
  $(if $(LVH_COMMIT),--build-arg LVH_COMMIT=$(LVH_COMMIT)) \
  $(if $(REQUIRE_USBIP),--build-arg REQUIRE_USBIP=$(REQUIRE_USBIP)) \
  $(if $(SUNSHINE_TEST_FILTER),--build-arg SUNSHINE_TEST_FILTER="$(SUNSHINE_TEST_FILTER)")

.PHONY: build publish clean

# Produit out/sunshine-ds.tar.zst, out/sunshine-ds.version, out/versions.txt.
build:
	$(DOCKER) buildx build --builder default --pull --platform linux/amd64 \
	  --provenance=false --sbom=false --progress plain \
	  $(BUILD_ARGS) $(ARGS) \
	  --output type=local,dest=out .

# Publie out/ en release GitHub (tag dérivé de out/sunshine-ds.version).
publish:
	@test -s out/sunshine-ds.version || { echo "FATAL: out/sunshine-ds.version absent, lancer make build"; exit 1; }
	@tag=$$(awk '{print $$2}' out/sunshine-ds.version); \
	rel="sunshine-ds-$${tag}-$$(date -u +%Y%m%d-%H%M)"; \
	echo "release $${rel} sur $(REPO)"; \
	gh release create "$${rel}" --repo $(REPO) --latest \
	  --notes-file out/versions.txt \
	  out/*.tar.zst out/*.version out/versions.txt

clean:
	rm -rf out
