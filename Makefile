# SPDX-License-Identifier: GPL-2.0

ORG_NAME ?= hihg-um
OS_BASE ?= ubuntu
OS_VER ?= 23.10

IMAGE_REPOSITORY ?=

TOOLS := bcftools plink2 samtools shapeit4 tabix vcftools

DOCKER_BUILD_ARGS ?=
DOCKER_TAG ?= $(shell git describe --tags --broken --dirty --all --long | \
			sed "s,heads/,," | sed "s,tags/,,")
DOCKER_BASE ?= $(patsubst docker-%,%,$(shell basename \
		`git remote --verbose | grep origin | grep fetch | \
		cut -f2 | cut -d ' ' -f1` | sed 's/.git//'))
DOCKER_IMAGES := $(TOOLS:=\:$(DOCKER_TAG))
SIF_IMAGES := $(TOOLS:=\:$(DOCKER_TAG).sif)

IMAGE_TEST := /test.sh

.PHONY: apptainer_clean apptainer_test \
	docker_base docker_clean docker_test docker_release $(TOOLS)

help:
	@echo "Targets: all build clean test release"
	@echo "         docker docker_base docker_clean docker_test docker_release"
	@echo "         apptainer apptainer_clean apptainer_test"
	@echo
	@echo "Docker container(s):"
	@for f in $(DOCKER_IMAGES); do \
		printf "\t$$f\n"; \
	done
	@echo
	@echo "Apptainer(s):"
	@for f in $(SIF_IMAGES); do \
		printf "\t$$f\n"; \
	done
	@echo

all: clean build test

build: docker apptainer

clean: apptainer_clean docker_clean

release: docker_release

test: docker_test apptainer_test

# Docker
docker: docker_base $(TOOLS)

$(TOOLS):
	@echo "Building Docker container: $@"
	@docker build \
		-f Dockerfile.$(DOCKER_BASE) \
		-t $(ORG_NAME)/$@:$(DOCKER_TAG) \
		$(DOCKER_BUILD_ARGS) \
		--build-arg BASE_IMAGE=$(ORG_NAME)/$(DOCKER_BASE):$(DOCKER_TAG) \
		--build-arg RUN_CMD=$@ \
		.

	$(if $(shell git fetch; git diff @{upstream}),,docker tag \
		$(ORG_NAME)/$@:$(DOCKER_TAG) $(ORG_NAME)/$@:latest)

docker_base:
	@echo "Building Docker base: $(DOCKER_BASE):$(DOCKER_TAG)"
	@docker build -t $(ORG_NAME)/$(DOCKER_BASE):$(DOCKER_TAG) \
		$(DOCKER_BUILD_ARGS) \
		--build-arg BASE_IMAGE=$(OS_BASE):$(OS_VER) \
		.

docker_clean:
	@for f in $(TOOLS); do \
		docker rmi -f $(ORG_NAME)/$$f:$(DOCKER_TAG) 2>/dev/null; \
		if [ -z "`git fetch; git diff @{upstream}`" ]; then \
			docker rmi -f $(ORG_NAME)/$$f:latest; \
		fi \
	done
	@docker rmi -f $(ORG_NAME)/$(DOCKER_BASE):$(DOCKER_TAG)
	@docker builder prune -f 2>/dev/null;

docker_test: 
	@for f in $(DOCKER_IMAGES); do \
		echo "Testing Docker container: $(ORG_NAME)/$$f"; \
		docker run -t \
			-v /etc/passwd:/etc/passwd:ro \
			-v /etc/group:/etc/group:ro \
			--entrypoint=$(IMAGE_TEST) \
			--user=$(shell echo `id -u`):$(shell echo `id -g`) \
			$(ORG_NAME)/$$f; \
	done

docker_release: $(DOCKER_IMAGES)
	@for f in $^; do \
		docker push $(IMAGE_REPOSITORY)/$(ORG_NAME)/$$f; \
	done

# Apptainer
apptainer: $(SIF_IMAGES)

$(SIF_IMAGES):
	@echo "Building Apptainer: $@"
	@apptainer build $@ docker-daemon:$(ORG_NAME)/$(patsubst %.sif,%,$@)

apptainer_clean:
	@for f in $(SIF_IMAGES); do \
		if [ -f "$$f" ]; then \
			printf "Cleaning up Apptainer: $$f\n"; \
			rm -f $$f; \
		fi \
	done

apptainer_test: $(SIF_IMAGES)
	@for f in $^; do \
		echo "Testing Apptainer: $$f"; \
		apptainer exec $$f $(IMAGE_TEST); \
	done
