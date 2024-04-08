#!/bin/bash
set -e

# Define minimum versions required to run the Kurtosis CDK packages.
MINIMUM_KURTOSIS_VERSION_REQUIRED=0.88.9
MINIMUM_DOCKER_VERSION_REQUIRED=24.7
MINIMUM_YQ_MAJOR_VERSION_REQUIRED=4

ensure_tool_installed() {
    local tool="$1"
    local install_docs="$2"
    if ! command -v "$tool" &> /dev/null; then
        echo "❌ $tool is not installed. Please install $tool to proceed: $install_docs"
        return 1
    fi
}

check_kurtosis_version() {
    ensure_tool_installed "kurtosis" "https://docs.kurtosis.com/install/"

    local minimum_major_kurtosis_version_required="$(echo $MINIMUM_KURTOSIS_VERSION_REQUIRED | cut -d '.' -f 1)"
    local minimum_minor_kurtosis_version_required="$(echo $MINIMUM_KURTOSIS_VERSION_REQUIRED | cut -d '.' -f 2)"
    local minimum_bugfix_kurtosis_version_required="$(echo $MINIMUM_KURTOSIS_VERSION_REQUIRED | cut -d '.' -f 3)"

    local kurtosis_version="$(kurtosis version | head -n 1 | cut -d ' ' -f 5)"
    local major_kurtosis_version="$(echo $kurtosis_version | cut -d '.' -f 1)"
    local minor_kurtosis_version="$(echo $kurtosis_version | cut -d '.' -f 2)"
    local bugfix_kurtosis_version="$(echo $kurtosis_version | cut -d '.' -f 3)"

    # If the major version is strictly greater than the minimum major version required, it meets the requirement.
    # However, if the major version is exactly the same as the minimum major version required, we need to additionally check the minor version.
    # Same thing if the major and minor versions are the same, we need to check the bugfix version.
    if [ "$major_kurtosis_version" -gt "$minimum_major_kurtosis_version_required" ] || \
        ([ "$major_kurtosis_version" -eq "$minimum_major_kurtosis_version_required" ] && [ "$minor_kurtosis_version" -ge "$minimum_minor_kurtosis_version_required" ]) || \
        ([ "$major_kurtosis_version" -eq "$minimum_major_kurtosis_version_required" ] && [ "$minor_kurtosis_version" -eq "$minimum_minor_kurtosis_version_required" ] && [ "$bugfix_kurtosis_version" -ge "$minimum_bugfix_kurtosis_version_required" ]); then
        echo "✅ kurtosis $kurtosis_version is installed, meets the requirement (>=$MINIMUM_KURTOSIS_VERSION_REQUIRED)"
    else
        echo "❌ kurtosis $kurtosis_version is installed, but version $MINIMUM_KURTOSIS_VERSION_REQUIRED or higher is required"
        exit 1
    fi
}

check_docker_version() {
    ensure_tool_installed "docker" "https://docs.docker.com/engine/install/"

    local minimum_major_docker_version_required="$(echo $MINIMUM_DOCKER_VERSION_REQUIRED | cut -d '.' -f 1)"
    local minimum_minor_docker_version_required="$(echo $MINIMUM_DOCKER_VERSION_REQUIRED | cut -d '.' -f 2)"

    local docker_version="$(docker --version | awk '{print $3}' | cut -d ',' -f 1)"
    local major_docker_version="$(echo $docker_version | cut -d '.' -f 1)"
    local minor_docker_version="$(echo $docker_version | cut -d '.' -f 2)"

    # If the major version is strictly greater than the minimum major version required, it meets the requirement.
    # However, if the major version is exactly the same as the minimum major version required, we need to additionally check the minor version.
    if [ "$major_docker_version" -gt "$minimum_major_docker_version_required" ] || \
        ([ "$major_docker_version" -eq "$minimum_major_docker_version_required" ] && [ "$minor_docker_version" -ge "$minimum_minor_docker_version_required" ]); then
        echo "✅ docker $docker_version is installed, meets the requirement (>=$MINIMUM_DOCKER_VERSION_REQUIRED)"
    else
        echo "❌ docker $docker_version is installed, but version $MINIMUM_DOCKER_VERSION_REQUIRED or higher is required"
        exit 1
    fi
}

check_jq_version() {
    ensure_tool_installed "jq" "https://jqlang.github.io/jq/download/"

    local jq_version="$(jq --version | cut -d '-' -f 2)"
    echo "✅ jq $jq_version is installed"
}

check_yq_version() {
    ensure_tool_installed "yq" "https://pypi.org/project/yq/"

    local yq_version="$(yq --version | cut -d 'v' -f 3)"
    local major_yq_version="$(echo $yq_version | cut -d '.' -f 1)"
    if [ "$major_yq_version" -ge "$MINIMUM_YQ_MAJOR_VERSION_REQUIRED" ]; then
        echo "✅ yq $yq_version is installed, meets the requirement (>=$MINIMUM_YQ_MAJOR_VERSION_REQUIRED)"
    else
        echo "❌ yq $yq_version is installed, but version $MINIMUM_YQ_MAJOR_VERSION_REQUIRED or higher is required"
        exit 1
    fi
}

check_cast_version() {
    ensure_tool_installed "cast" "https://book.getfoundry.sh/getting-started/installation#using-foundryup"

    local cast_version="$(cast --version | cut -d ' ' -f 2)"
    echo "✅ cast $cast_version is installed"
}

check_polycli_version() {
    ensure_tool_installed "polycli" "https://github.com/maticnetwork/polygon-cli/releases"

    local polycli_version="$(polycli version | cut -d ' ' -f 4)"
    echo "✅ polycli $polycli_version is installed"
}

check_docker_mac_connect_version() {
    ensure_tool_installed "docker-mac-net-connect" "https://github.com/chipmk/docker-mac-net-connect?tab=readme-ov-file#installation"

    local docker_mac_connect_version="$(docker-mac-net-connect --version | cut -d ' ' -f 3 | cut -d "'" -f 2 | cut -d "v" -f 2)"
    echo "✅ docker-mac-connect $docker_mac_connect_version is installed"
}


echo "Ensuring all required tools and versions are installed for deploying the Kurtosis CDK package..."
check_kurtosis_version
check_docker_version
check_jq_version
check_yq_version
check_cast_version
check_polycli_version

if [[ "$(uname)" == "Darwin" ]]; then
    echo; echo "Checking macOS specific tools..."
    check_docker_mac_connect_version

    echo; echo "Running a dummy nginx container..."
    if docker ps -a --format '{{.Names}}' | grep -q '^nginx$'; then
        docker rm -f nginx
    fi
    docker run --rm --name nginx -d nginx

    echo; echo "Making an HTTP request directly to the internal IP of the nginx container..."
    if ! curl -m 1 -I $(docker inspect nginx --format '{{.NetworkSettings.IPAddress}}'); then
        echo "Curl request failed. Make sure docker-mac-connect is running and make sure you reinstalled Docker Engine for macOS!"
        exit 1
    fi
fi
