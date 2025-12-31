# Image names
TOOLBOX_IMAGE_NAME := toolbox:0.0.12
AGGLAYER_CONTRACTS_IMAGE_NAME := agglayer-contracts:v12.2.1

# GCR registry
GCR_REGISTRY := europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "Usage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Build

.PHONY: build-toolbox
build-toolbox: ## Build toolbox image
	docker build --tag $(TOOLBOX_IMAGE_NAME) --file toolbox.Dockerfile .

.PHONY: build-agglayer-contracts
build-agglayer-contracts: ## Build agglayer contracts image
	docker build --tag $(AGGLAYER_CONTRACTS_IMAGE_NAME) --file agglayer-contracts.Dockerfile .

##@ Push

auth: ## Authenticate with Google Cloud Registry
	gcloud auth login
	gcloud config set project prj-polygonlabs-devtools-dev
	gcloud auth configure-docker europe-west2-docker.pkg.dev

.PHONY: push-toolbox
push-toolbox: ## Push toolbox image to GCR
	docker tag $(TOOLBOX_IMAGE_NAME) $(GCR_REGISTRY)/$(TOOLBOX_IMAGE_NAME)
	docker push $(GCR_REGISTRY)/$(TOOLBOX_IMAGE_NAME)

.PHONY: push-agglayer-contracts
push-agglayer-contracts: ## Push agglayer contracts image to GCR
	docker tag $(AGGLAYER_CONTRACTS_IMAGE_NAME) $(GCR_REGISTRY)/$(AGGLAYER_CONTRACTS_IMAGE_NAME)
	docker push $(GCR_REGISTRY)/$(AGGLAYER_CONTRACTS_IMAGE_NAME)
