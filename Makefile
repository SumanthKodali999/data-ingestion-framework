OUTPUT_DIR=./build
SOURCE_DIRS=cmd pkg
PACKAGES=go list ./... | grep -v /vendor | grep -v /out
SHELL='/bin/bash'
REMOTE=github.com
USER=turbonomic
PROJECT=data-ingestion-framework
BINARY=turbodif
DEFAULT_VERSION=latest

.DEFAULT_GOAL:=build

GIT_COMMIT=$(shell git rev-parse HEAD)
BUILD_TIME=$(shell date -R)
PROJECT_PATH=$(REMOTE)/$(USER)/$(PROJECT)
VERSION=$(or $(TURBODIF_VERSION), $(DEFAULT_VERSION))
LDFLAGS='\
 -X "$(PROJECT_PATH)/version.GitCommit=$(GIT_COMMIT)" \
 -X "$(PROJECT_PATH)/version.BuildTime=$(BUILD_TIME)" \
 -X "$(PROJECT_PATH)/version.Version=$(VERSION)"'


LINUX_ARCH=amd64 arm64 ppc64le s390x

$(LINUX_ARCH): clean
	env GOOS=linux GOARCH=$@ go build -ldflags $(LDFLAGS) -o $(OUTPUT_DIR)/linux/$@/$(BINARY) ./cmd

product: $(LINUX_ARCH)	

debug-product: clean
	env GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -ldflags $(LDFLAGS) -gcflags "-N -l" -o $(OUTPUT_DIR)/$(BINARY)_debug.linux ./cmd

build: clean
	go build -ldflags $(LDFLAGS) -o $(OUTPUT_DIR)/$(BINARY) ./cmd

debug: clean
	go build -ldflags $(LDFLAGS) -gcflags "-N -l" -o $(OUTPUT_DIR)/$(BINARY).debug ./cmd

docker: product
	DOCKER_BUILDKIT=1 docker build -f build/Dockerfile -t turbonomic/turbodif .

test: clean
	@go test -v -race ./pkg/...

.PHONY: fmtcheck
fmtcheck:
	@gofmt -s -l $(SOURCE_DIRS) | grep ".*\.go"; if [ "$$?" = "0" ]; then exit 1; fi

.PHONY: vet
vet:
	@go vet $(shell $(PACKAGES))

clean:
	@rm -rf $(OUTPUT_DIR)/$(BINARY)* ${OUTPUT_DIR}/linux


PLATFORMS ?= linux/arm64,linux/amd64,linux/s390x,linux/ppc64le
REPO_NAME ?= icr.io/cpopen/turbonomic
multi-archs:
	env GOOS=${TARGETOS} GOARCH=${TARGETARCH} CGO_ENABLED=0 go build -ldflags $(LDFLAGS) -o $(OUTPUT_DIR)/$(BINARY) ./cmd
.PHONY: docker-buildx
docker-buildx:
	docker buildx create --name turbodif-builder
	- docker buildx use turbodif-builder
	- docker buildx build --platform=$(PLATFORMS) --label "git-commit=$(GIT_COMMIT)" --label "git-version=$(VERSION)" --provenance=false --push --tag $(REPO_NAME)/turbodif:$(VERSION) -f build/Dockerfile.multi-archs --build-arg VERSION=$(VERSION) .
	docker buildx rm turbodif-builder
