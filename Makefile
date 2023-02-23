.POSIX:
.DEFAULT_GOAL: help

REGISTRY ?= docker.io/zulip/docker-zulip
REGISTRY_TAG ?= undefined
PUSH_LATEST_TAG ?= 0
ifeq ($(PUSH_LATEST_TAG), 1)
	PUSH_LATEST_TAG_ARG = -t $(REGISTRY):latest
else
	PUSH_LATEST_TAG_ARG =
endif
# Default to creating our own buildx context, as "default", using the native
# "docker" driver, can result in errors like the following when using Linux
# distros' Docker and not Docker Desktop:
#
# ERROR: multiple platforms feature is currently not supported for docker
# driver. Please switch to a different driver (eg. "docker buildx create
# --use")
BUILDX_BUILDER ?= zulip
BUILDX_PLATFORMS ?= linux/amd64,linux/arm64

.PHONY: help
help:
	@echo "This Makefile wraps Docker and Docker BuildX to build multiarch Zulip images." \
		"Make sure a recent Docker and BuildX are installed on your system - Docker Desktop users (on any OS) should be good to go, those using Linux distribution's builds of Docker will need to find the correct packages."
	@echo
	@echo "To use, set REGISTRY, REGISTRY_TAG, perhaps to 'local', and optionally override BUILDX_PLATFORMS." \
		"Additionally, PUSH_LATEST_TAG can be set to 1 to additonally tag :local when pushing to the registry." \
		"Then, run the build-multiarch-containers target. For example:"
	@echo
	@echo "    make build-multiarch-containers REGISTRY=docker.example.com/myorg/zulip REGISTRY_TAG=local PUSH_LATEST_TAG=1"
	@echo
	@echo "By default, REGISTRY:REGISTRY_TAG will be built for linux/amd64 and linux/arm64. Adding other platforms to this list is unsupported and will almost certainly not work, but the list can be shrunk."
	@echo "REGISTRY must be set to something the builder has push access to, because BuildX images and manifests are not loaded into the host's Docker registry."
	@echo
	@echo "One can expect this step to take many multiples of the time it takes to build the Zulip image for just the native architecture." \
		"If it takes 10 minutes to build the amd64 image by itself, expect cross-compiling the arm64 image to take 30-60 minutes on most currently-common hardware." \
		"Currently, distributing the image builds to multiple machines (perhaps to allow the arm64 image to build on a native arm64 host for efficiency) is unsupported."
	@echo
	@echo "Assuming all goes well, REGISTRY:REGISTRY_TAG will point to a multiarch manifest referring to an image for each of BUILDX_PLATFORMS, which can then be rolled out to your infrastructure, used in Docker Compose, etc."
	@echo
	@echo "Please report bugs with this Makefile or anything it runs, or with running Zulip on arm64 in general, at https://github.com/zulip/docker-zulip and/or at https://chat.zulip.org"

.PHONY: reset-qemu-static
reset-qemu-static:
# --credential yes is required to run sudo within qemu, without it the
# effective UID after a call to sudo will not be 0 and sudo in cross-built
# containers (eg. the arm64 build if running on an amd64 host) will fail
#
# see also: https://github.com/crazy-max/ghaction-docker-buildx/issues/213
#
# We're allowing failures here (- prefix) for two main reasons:
#
# - BUILDX_PLATFORMS can be overridden to a single, native platform (meaning
#   this QEMU reset won't be necessary anyway)
# - On ZFS<2.2 root filesystems, this incantation can fail due to Docker-side
#   dataset teardown issues as documented in
#   https://github.com/moby/moby/issues/40132. The QEMU reset may have
#   succeeded despite the Docker daemon errors, so we'll try to power through.
	-docker run --rm --privileged multiarch/qemu-user-static --reset -p yes --credential yes

.PHONY: build-multiarch-containers
ifeq ($(REGISTRY_TAG), undefined)
build-multiarch-containers:
	$(error REGISTRY_TAG must be provided in environment or make incantation)
else
build-multiarch-containers: reset-qemu-static
	(docker buildx ls | grep "$(BUILDX_BUILDER)" 2>&1 >/dev/null) || docker buildx create --name $(BUILDX_BUILDER) --platform $(BUILDX_PLATFORMS) --bootstrap --use
	docker buildx build --platform $(BUILDX_PLATFORMS) -t $(REGISTRY):$(REGISTRY_TAG) $(PUSH_LATEST_TAG_ARG) --push .
endif
