#!/bin/bash

# Define minimum versions required to run the Kurtosis CDK packages.
MINIMUM_KURTOSIS_VERSION_REQUIRED=0.88.9
MINIMUM_DOCKER_VERSION_REQUIRED=24.7
MAXIMUM_YQ_MAJOR_VERSION_SUPPORTED=3.x

## Helper functions.
ensure_required_tool_is_installed() {
    local tool="$1"
    local install_docs="$2"
    if ! command -v "$tool" &>/dev/null; then
        echo "❌ $tool is not installed. Please install $tool to proceed: $install_docs"
        exit 1
    fi
}

ensure_optional_tool_is_installed() {
    local tool="$1"
    local install_docs="$2"
    if ! command -v "$tool" &>/dev/null; then
        echo "⚠️  $tool is not installed. You can install $tool at: $install_docs"
        return 1
    fi
}

## Check tool versions.
check_kurtosis_version() {
    ensure_required_tool_is_installed "kurtosis" "https://docs.kurtosis.com/install/"

    minimum_major_kurtosis_version_required="$(echo "$MINIMUM_KURTOSIS_VERSION_REQUIRED" | cut -d '.' -f 1)"
    minimum_minor_kurtosis_version_required="$(echo "$MINIMUM_KURTOSIS_VERSION_REQUIRED" | cut -d '.' -f 2)"
    minimum_bugfix_kurtosis_version_required="$(echo "$MINIMUM_KURTOSIS_VERSION_REQUIRED" | cut -d '.' -f 3)"

    kurtosis_version="$(kurtosis version | head -n 1 | cut -d ' ' -f 5)"
    major_kurtosis_version="$(echo "$kurtosis_version" | cut -d '.' -f 1)"
    minor_kurtosis_version="$(echo "$kurtosis_version" | cut -d '.' -f 2)"
    bugfix_kurtosis_version="$(echo "$kurtosis_version" | cut -d '.' -f 3)"

    # If the major version is strictly greater than the minimum major version required, it meets the requirement.
    # However, if the major version is exactly the same as the minimum major version required, we need to additionally check the minor version.
    # Same thing if the major and minor versions are the same, we need to check the bugfix version.
    if [ "$major_kurtosis_version" -gt "$minimum_major_kurtosis_version_required" ] || \
        { [ "$major_kurtosis_version" -eq "$minimum_major_kurtosis_version_required" ] && [ "$minor_kurtosis_version" -ge "$minimum_minor_kurtosis_version_required" ]; } || \
        { [ "$major_kurtosis_version" -eq "$minimum_major_kurtosis_version_required" ] && [ "$minor_kurtosis_version" -eq "$minimum_minor_kurtosis_version_required" ] && [ "$bugfix_kurtosis_version" -ge "$minimum_bugfix_kurtosis_version_required" ]; }; then
        echo "✅ kurtosis $kurtosis_version is installed, meets the requirement (>=$MINIMUM_KURTOSIS_VERSION_REQUIRED)"
    else
        echo "❌ kurtosis $kurtosis_version is installed, but version $MINIMUM_KURTOSIS_VERSION_REQUIRED or higher is required"
        exit 1
    fi
}

check_docker_version() {
    ensure_required_tool_is_installed "docker" "https://docs.docker.com/engine/install/"

    minimum_major_docker_version_required="$(echo "$MINIMUM_DOCKER_VERSION_REQUIRED" | cut -d '.' -f 1)"
    minimum_minor_docker_version_required="$(echo "$MINIMUM_DOCKER_VERSION_REQUIRED" | cut -d '.' -f 2)"

    docker_version="$(docker --version | awk '{print $3}' | cut -d ',' -f 1)"
    major_docker_version="$(echo "$docker_version" | cut -d '.' -f 1)"
    minor_docker_version="$(echo "$docker_version" | cut -d '.' -f 2)"

    # If the major version is strictly greater than the minimum major version required, it meets the requirement.
    # However, if the major version is exactly the same as the minimum major version required, we need to additionally check the minor version.
    if [ "$major_docker_version" -gt "$minimum_major_docker_version_required" ] || \
        { [ "$major_docker_version" -eq "$minimum_major_docker_version_required" ] && [ "$minor_docker_version" -ge "$minimum_minor_docker_version_required" ]; }; then
        echo "✅ docker $docker_version is installed, meets the requirement (>=$MINIMUM_DOCKER_VERSION_REQUIRED)"
    else
        echo "❌ docker $docker_version is installed, but version $MINIMUM_DOCKER_VERSION_REQUIRED or higher is required"
        exit 1
    fi
}

check_docker_mac_connect_version() {
    ensure_required_tool_is_installed "docker-mac-net-connect" "https://github.com/chipmk/docker-mac-net-connect?tab=readme-ov-file#installation"

    docker_mac_connect_version="$(docker-mac-net-connect --version | cut -d ' ' -f 3 | cut -d "'" -f 2 | cut -d "v" -f 2)"
    echo "✅ docker-mac-connect $docker_mac_connect_version is installed"
}

check_jq_version() {
    ensure_optional_tool_is_installed "jq" "https://jqlang.github.io/jq/download/"
    if [ $? -eq 0 ]; then
        jq_version="$(jq --version | cut -d '-' -f 2)"
        echo "✅ jq $jq_version is installed"
    fi
}

check_yq_version() {
    ensure_optional_tool_is_installed "yq" "https://pypi.org/project/yq/"
    if [ $? -eq 0 ]; then
        maximum_yq_major_version_supported="$(echo "$MAXIMUM_YQ_MAJOR_VERSION_SUPPORTED" | cut -d '.' -f 1)"

        yq_version="$(yq --version | cut -d ' ' -f 2)"
        major_yq_version="$(echo "$yq_version" | cut -d '.' -f 1)"
        if [ "$major_yq_version" -le "$maximum_yq_major_version_supported" ]; then
            echo "✅ yq $yq_version is installed, meets the requirement (<=$MAXIMUM_YQ_MAJOR_VERSION_SUPPORTED)"
        else
            echo "❌ yq $yq_version is installed, but version $MAXIMUM_YQ_MAJOR_VERSION_SUPPORTED or higher is not supported"
            exit 1
        fi
    fi
}

check_cast_version() {
    ensure_optional_tool_is_installed "cast" "https://book.getfoundry.sh/getting-started/installation#using-foundryup"
    if [ $? -eq 0 ]; then
        cast_version="$(cast --version | cut -d ' ' -f 2)"
        echo "✅ cast $cast_version is installed"
    fi
}

check_polycli_version() {
    ensure_optional_tool_is_installed "polycli" "https://github.com/maticnetwork/polygon-cli/releases"
    if [ $? -eq 0 ]; then
        polycli_version="$(polycli version | cut -d ' ' -f 4)"
        echo "✅ polycli $polycli_version is installed"
    fi
}

## Main function.
main() {
    echo "Checking that you have the necessary tools to deploy the Kurtosis CDK package..."
    check_kurtosis_version
    check_docker_version
    if [[ "$(uname)" == "Darwin" ]]; then
        echo; echo "Checking macOS specific tools..."
        check_docker_mac_connect_version

        echo; echo "Running a dummy nginx container..."
        if docker ps -a --format '{{.Names}}' | grep -q '^nginx$'; then
            docker rm -f nginx 2>&1 > /dev/null
        fi
        docker run --rm --name nginx -d nginx

        echo; echo "Making an HTTP request directly to the internal IP of the nginx container..."
        if ! curl -m 1 -I "$(docker inspect nginx --format '{{.NetworkSettings.IPAddress}}')"; then
            echo "❌ Curl request failed. Make sure docker-mac-connect is running and make sure you reinstalled Docker Engine for macOS!"
            exit 1
        else
            echo "✅ You can successfully access containers using their internal IPs!"
            docker rm -f nginx 2>&1 > /dev/null
        fi
    fi

    echo; echo "You might as well need the following tools to interact with the environment..."
    check_jq_version
    check_yq_version
    check_cast_version
    check_polycli_version

    echo; echo "✅ You are ready to go!"
}

main
