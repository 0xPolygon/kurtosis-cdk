# Docker Images

To push images to the Google Cloud registry, you can follow these steps:

1. Authenticate with GCR using your Google account

```bash
gcloud auth login
gcloud config set project prj-polygonlabs-devtools-dev
gcloud auth configure-docker
```

2. Push the image to GCR.

```bash
gcr_registry="europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public"
gcp_image_name="${gcr_registry}/${image_name}"
docker tag "${image_name}" "${gcp_image_name}"
docker push "${gcp_image_name}"
```

## Agglayer/ZkEVM Contracts

> Images were previously named `zkevm-contracts`.

Pre-compiled agglayer contracts.

Each image is suffixed with `-fork.<id>` to work properly with Kurtosis CDK. For example, pessimistic tags have been prefixed with `-fork.12`, e.g. the agglayer-contracts tag `v9.0.0-rc.2-pp` corresponds to `europe-west2-docker.pkg.dev/prj-polygonlabs-devtools-dev/public/zkevm-contracts:v9.0.0-rc.2-pp-fork.12`.

Repository: <https://github.com/agglayer/agglayer-contracts>

```bash
image_name="agglayer-contracts:v12.1.5-fork.0"
docker build --tag $image_name --file agglayer-contracts.Dockerfile .
```

## OP-Deployer

TODO

## Utility Images

### Toolbox

This image contains different tools to interact with blockchains such as `polycli` or `cast`.

```bash
image_name="toolbox:0.0.12"
docker build --tag $image_name --file toolbox.Dockerfile .
```

### Status Checker

A lightweight, modular tool for running and persisting status checks across multiple services.

Repository: <https://github.com/0xPolygon/status-checker>

```bash
# from the root of the repository
image_name="status-checker-cdk:v0.2.8"
docker build --tag "${image_name}" --file docker/status-checker-cdk.Dockerfile .
```

### Agglayer Dashboard

Build and create image from here:

Repository: <https://github.com/xavier-romero/agglayer-dashboard>
