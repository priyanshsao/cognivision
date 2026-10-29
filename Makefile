.PHONY: help install binary run all clean fmt proto

.DEFAULT_GOAL := help
.NOTPARALLEL:

GO_VERSION            ?= 1.25.0
PYTHON_VERSION        ?= 3.12
REDIS_VERSION         ?= 7.0
PROTOC_VERSION        ?= 25.1
PROTOC_GEN_GO_VERSION ?= 1.36.1

LOG_LEVEL       ?= INFO
SCRIPTS_DIR     ?= scripts
GO_BINARY_NAME  ?= cognivision
CGO_ENABLED     ?= 0
VERSION         ?= v0.0.1
BIN_DIR         ?= bin
BIN_PATH        := $(BIN_DIR)/$(GO_BINARY_NAME)
PYTHON_BINARY   ?= .venv/bin/python
LDFLAGS         ?= -s -w -X main.version=$(VERSION)

OS_ID := $(shell . /etc/os-release 2>/dev/null && echo "$$ID")

ifeq ($(OS_ID),ubuntu)
	SHELL := /bin/bash
	.SHELLFLAGS := -euo pipefail -c
	export PATH := /usr/local/go/bin:$(HOME)/go/bin:$(PATH)
else
	$(error Unsupported OS: only Ubuntu is supported.)
endif

help: ## Show command usage help
	@echo "Usage: make <target>"
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "} {printf "  %-10s %s\n", $$1, $$2}'

install: ## Install dependencies
	bash $(SCRIPTS_DIR)/setup-ubuntu.sh $(GO_VERSION) $(PYTHON_VERSION) $(REDIS_VERSION) $(PROTOC_VERSION) $(PROTOC_GEN_GO_VERSION)

proto: ## Generate protobuf files
	protoc --proto_path=. --go_out=gateway/ --go_opt=paths=source_relative proto/define.proto
	protoc --python_out=inference/ --pyi_out=inference/ proto/define.proto

binary: proto ## Build gateway binary
	@mkdir -p "$(BIN_DIR)"
	CGO_ENABLED=$(CGO_ENABLED) go build -trimpath -ldflags "$(LDFLAGS)" -o "$(BIN_PATH)" ./cmd/gateway.go

fmt: ## Format source code
	gofmt -w gateway/
	ruff format inference/

run: install binary ## Run inference and gateway
	@set -m; \
	"$(PYTHON_BINARY)" -m cmd.inference --log-level="$(LOG_LEVEL)" & \
	python_pid=$$!; \
	trap 'kill $$python_pid 2>/dev/null || true; wait $$python_pid 2>/dev/null || true' EXIT INT TERM; \
	"./$(BIN_PATH)" --log-level="$(LOG_LEVEL)"

all: install binary run ## Install dependencies and build

clean: ## Remove build output
	rm -rf "$(BIN_DIR)"
