# Image names
AGGLAYER_CONTRACTS_IMAGE_NAME := agglayer-contracts:v12.2.1
TOOLBOX_IMAGE_NAME := toolbox:0.0.12
ZKEVM_BRIDGE_UI_IMAGE_NAME := zkevm-bridge-ui:dbd55ed

# GCR registry
GCR_REGISTRY := europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "Usage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Build

.PHONY: build-agglayer-contracts
build-agglayer-contracts: ## Build agglayer contracts image
	docker build --tag $(AGGLAYER_CONTRACTS_IMAGE_NAME) --file agglayer-contracts.Dockerfile .

.PHONY: build-toolbox
build-toolbox: ## Build toolbox image
	docker build --tag $(TOOLBOX_IMAGE_NAME) --file toolbox.Dockerfile .

.PHONY: build-zkevm-bridge-ui
build-zkevm-bridge-ui: ## Build zkevm-bridge-ui image
	docker build --tag $(ZKEVM_BRIDGE_UI_IMAGE_NAME) --file zkevm-bridge-ui/Dockerfile zkevm-bridge-ui

##@ Push

auth: ## Authenticate with Google Cloud Registry
	gcloud auth login
	gcloud config set project prj-polygonlabs-devtools-dev
	gcloud auth configure-docker europe-west2-docker.pkg.dev

.PHONY: push-agglayer-contracts
push-agglayer-contracts: ## Push agglayer contracts image to GCR
	docker tag $(AGGLAYER_CONTRACTS_IMAGE_NAME) $(GCR_REGISTRY)/$(AGGLAYER_CONTRACTS_IMAGE_NAME)
	docker push $(GCR_REGISTRY)/$(AGGLAYER_CONTRACTS_IMAGE_NAME)

.PHONY: push-toolbox
push-toolbox: ## Push toolbox image to GCR
	docker tag $(TOOLBOX_IMAGE_NAME) $(GCR_REGISTRY)/$(TOOLBOX_IMAGE_NAME)
	docker push $(GCR_REGISTRY)/$(TOOLBOX_IMAGE_NAME)

.PHONY: push-zkevm-bridge-ui
push-zkevm-bridge-ui: ## Push zkevm-bridge-ui image to GCR
	docker tag $(ZKEVM_BRIDGE_UI_IMAGE_NAME) $(GCR_REGISTRY)/$(ZKEVM_BRIDGE_UI_IMAGE_NAME)
	docker push $(GCR_REGISTRY)/$(ZKEVM_BRIDGE_UI_IMAGE_NAME)
