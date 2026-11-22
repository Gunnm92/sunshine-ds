# Pipeline de release sunshine-ds (voir README.md).
#
# DOCKER : la session porte des variables TLS qui cassent le proxy de socket
# (docker-socket-proxy:2375 sans TLS) : elles sont retirées ici.
DOCKER ?= env -u DOCKER_TLS_VERIFY -u DOCKER_CERT_PATH DOCKER_HOST=tcp://docker-socket-proxy:2375 docker
REPO ?= Gunnm92/sunshine-ds

# Arguments de build, passés seulement s'ils sont définis.
SUNSHINE_TAG ?=
DS5_USBIP_REF ?=
LVH_COMMIT ?=
REQUIRE_USBIP ?=
BUILD_ARGS := \
  $(if $(SUNSHINE_TAG),--build-arg SUNSHINE_TAG=$(SUNSHINE_TAG)) \
  $(if $(DS5_USBIP_REF),--build-arg DS5_USBIP_REF=$(DS5_USBIP_REF)) \
  $(if $(LVH_COMMIT),--build-arg LVH_COMMIT=$(LVH_COMMIT)) \
  $(if $(REQUIRE_USBIP),--build-arg REQUIRE_USBIP=$(REQUIRE_USBIP))

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
