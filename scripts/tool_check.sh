#!/bin/bash

# Define minimum versions required to run the Kurtosis CDK packages.
KURTOSIS_VERSION_SUPPORTED=0.89
DOCKER_VERSION_SUPPORTED=24.7
YQ_VERSION_SUPPORTED=3.2

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
        echo "🟡 Optional $tool is not installed. You can install $tool at: $install_docs"
        return 1
    fi
}

## Check tool versions.
check_kurtosis_version() {
    kurtosis_install_docs="https://docs.kurtosis.com/install/"
    ensure_required_tool_is_installed "kurtosis" "$kurtosis_install_docs"

    major_kurtosis_version_supported="$(echo "$KURTOSIS_VERSION_SUPPORTED" | cut -d '.' -f 1)"
    minor_kurtosis_version_supported="$(echo "$KURTOSIS_VERSION_SUPPORTED" | cut -d '.' -f 2)"

    kurtosis_version="$(kurtosis version | head -n 1 | cut -d ' ' -f 5)"
    major_kurtosis_version="$(echo "$kurtosis_version" | cut -d '.' -f 1)"
    minor_kurtosis_version="$(echo "$kurtosis_version" | cut -d '.' -f 2)"

    if { [ "$major_kurtosis_version" -eq "$major_kurtosis_version_supported" ] && [ "$minor_kurtosis_version" -eq "$minor_kurtosis_version_supported" ]; }; then
        echo "✅ kurtosis $kurtosis_version is installed, meets the requirement (=$KURTOSIS_VERSION_SUPPORTED)."
    else
        echo "❌ kurtosis $kurtosis_version is installed, but only version $KURTOSIS_VERSION_SUPPORTED is supported by the package."
        exit 1
    fi
}

check_docker_version() {
    docker_install_docs="https://docs.docker.com/engine/install/"
    ensure_required_tool_is_installed "docker" "$docker_install_docs"

    major_docker_version_supported="$(echo "$DOCKER_VERSION_SUPPORTED" | cut -d '.' -f 1)"
    minor_docker_version_supported="$(echo "$DOCKER_VERSION_SUPPORTED" | cut -d '.' -f 2)"

    docker_version="$(docker --version | awk '{print $3}' | cut -d ',' -f 1)"
    major_docker_version="$(echo "$docker_version" | cut -d '.' -f 1)"
    minor_docker_version="$(echo "$docker_version" | cut -d '.' -f 2)"


    # If the major version is strictly greater than the minimum major version required, it meets the requirement.
    # However, if the major version is exactly the same as the minimum major version required, we need to additionally check the minor version.
    if [ "$major_docker_version" -ge "$major_docker_version_supported" ] || \
        { [ "$major_docker_version" -eq "$major_docker_version_supported" ] && [ "$minor_docker_version" -ge "$minor_docker_version_supported" ]; }; then
        echo "✅ docker $docker_version is installed, meets the requirement (>=$DOCKER_VERSION_SUPPORTED)."
    else
        echo "❌ docker $docker_version is installed, but only version $DOCKER_VERSION_SUPPORTED is supported by the package."
        exit 1
    fi
}

check_jq_version() {
    jq_install_docs="https://jqlang.github.io/jq/download/"
    if ensure_optional_tool_is_installed "jq" "$jq_install_docs"; then
        jq_version="$(jq --version | cut -d '-' -f 2)"
        echo "✅ jq $jq_version is installed."
    fi
}

check_yq_version() {
    yq_install_docs="https://pypi.org/project/yq/"
    if ensure_optional_tool_is_installed "yq" "$yq_install_docs"; then
        yq_major_version_supported="$(echo "$YQ_VERSION_SUPPORTED" | cut -d '.' -f 1)"
        yq_minor_version_supported="$(echo "$YQ_VERSION_SUPPORTED" | cut -d '.' -f 2)"

        yq_version="$(yq --version | cut -d ' ' -f 2)"
        major_yq_version="$(echo "$yq_version" | cut -d '.' -f 1)"
        minor_yq_version="$(echo "$yq_version" | cut -d '.' -f 2)"
        if { [ "$major_yq_version" -eq "$yq_major_version_supported" ] && [ "$minor_yq_version" -ge "$yq_minor_version_supported" ]; }; then
            echo "✅ yq $yq_version is installed, meets the requirement (>=$YQ_VERSION_SUPPORTED)."
        else
            echo "❌ yq $yq_version is installed, but only version $YQ_VERSION_SUPPORTED is supported by the package."
            exit 1
        fi
    fi
}

check_cast_version() {
    cast_install_docs="https://book.getfoundry.sh/getting-started/installation#using-foundryup"
    if ensure_optional_tool_is_installed "cast" "$cast_install_docs"; then
        cast_version="$(cast --version | cut -d ' ' -f 2)"
        echo "✅ cast $cast_version is installed."
    fi
}

check_polycli_version() {
    polycli_install_docs="https://github.com/maticnetwork/polygon-cli/releases"
    if ensure_optional_tool_is_installed "polycli" "$polycli_install_docs"; then
        polycli_version="$(polycli version | cut -d ' ' -f 4)"
        echo "✅ polycli $polycli_version is installed."
    fi
}

## Main function.
main() {
    echo "Checking that you have the necessary tools to deploy the Kurtosis CDK package..."
    check_kurtosis_version
    check_docker_version

    echo; echo "You might as well need the following tools to interact with the environment..."
    check_jq_version
    check_yq_version
    check_cast_version
    check_polycli_version

    echo; echo "🎉 You are ready to go!"
}

main
