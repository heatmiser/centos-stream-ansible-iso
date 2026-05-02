#!/bin/bash
#
# build-live-image.sh - Portable CentOS Stream 10 MIN-Live ISO Builder
#
# Fully containerized build process requiring only Podman.
# Works on Linux, Mac, and Windows WSL2.
#
# Usage:
#   ./build-live-image.sh [--vault-password-file FILE]
#
# Configuration:
#   live-image.conf           - Plaintext configuration (required)
#   live-image-vault.yml      - Encrypted credentials (optional)
#

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/live-image.conf"
VAULT_FILE="${SCRIPT_DIR}/live-image-vault.yml"
CREDENTIALS_FILE="${SCRIPT_DIR}/kiwi-descriptions/root/etc/liveimage-credentials.conf"
OUTPUT_DIR="${SCRIPT_DIR}/outdir"
KIWI_DESC_DIR="${SCRIPT_DIR}/kiwi-descriptions"

# Container images
ANSIBLE_CONTAINER="quay.io/ansible/creator-ee:latest"
CENTOS_CONTAINER="quay.io/centos/centos:stream10-development"

# Vault password file
VAULT_PASSWORD_FILE=""

#######################################
# Print colored message
#######################################
print_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

#######################################
# Check for Podman availability
#######################################
check_podman() {
    print_info "Checking for Podman..."

    if ! command -v podman &> /dev/null; then
        print_error "Podman is not installed or not in PATH"
        print_error "Please install Podman: https://podman.io/getting-started/installation"
        exit 1
    fi

    if ! podman ps &> /dev/null; then
        print_error "Cannot connect to Podman"
        print_error "Please ensure Podman is properly configured and running"
        exit 1
    fi

    print_success "Podman is available: $(podman --version)"
}

#######################################
# Validate configuration files
#######################################
validate_config() {
    print_info "Validating configuration..."

    if [ ! -f "${CONFIG_FILE}" ]; then
        print_error "Configuration file not found: ${CONFIG_FILE}"
        print_error "Please create live-image.conf (see live-image.conf.example)"
        exit 1
    fi

    # Source and validate config
    source "${CONFIG_FILE}"

    if [ -z "${LIVE_USERNAME:-}" ]; then
        print_error "LIVE_USERNAME not set in ${CONFIG_FILE}"
        exit 1
    fi

    # Check SSH key file if specified
    if [ -n "${LIVE_USER_SSHKEY_FILE:-}" ]; then
        if [ ! -f "${LIVE_USER_SSHKEY_FILE}" ]; then
            print_error "SSH key file not found: ${LIVE_USER_SSHKEY_FILE}"
            exit 1
        fi
    fi

    print_success "Configuration validated"
}

#######################################
# Decrypt vault and extract credentials
#######################################
decrypt_vault() {
    if [ ! -f "${VAULT_FILE}" ]; then
        print_info "No vault file found, skipping vault decryption"
        return 0
    fi

    print_info "Decrypting vault file: ${VAULT_FILE}"

    # Build ansible-vault command
    local vault_cmd="ansible-vault view /work/live-image-vault.yml"

    if [ -n "${VAULT_PASSWORD_FILE}" ]; then
        vault_cmd="${vault_cmd} --vault-password-file=/work/${VAULT_PASSWORD_FILE}"
        vault_args="-v ${SCRIPT_DIR}:/work:z"
    else
        vault_args="-it -v ${SCRIPT_DIR}:/work:z"
    fi

    # Decrypt vault using Ansible container
    local vault_content
    if ! vault_content=$(podman run --rm ${vault_args} \
        "${ANSIBLE_CONTAINER}" \
        bash -c "${vault_cmd}" 2>&1); then
        print_error "Failed to decrypt vault file"
        print_error "${vault_content}"
        exit 1
    fi

    # Parse YAML and extract variables
    # Simple parsing for our use case (live_user_password_hash, additional_ssh_keys)
    VAULT_PASSWORD_HASH=$(echo "${vault_content}" | grep '^live_user_password_hash:' | sed 's/^live_user_password_hash: *"\(.*\)"/\1/' | sed "s/^live_user_password_hash: *'\(.*\)'/\1/" | sed 's/^live_user_password_hash: *//')
    VAULT_ADDITIONAL_KEYS=$(echo "${vault_content}" | awk '/^additional_ssh_keys:/,/^[a-z]/ {if ($0 ~ /^  - /) print}' | sed 's/^  - //' | sed 's/"//g' | sed "s/'//g")

    if [ -n "${VAULT_PASSWORD_HASH}" ]; then
        print_success "Password hash extracted from vault"
    fi

    if [ -n "${VAULT_ADDITIONAL_KEYS}" ]; then
        print_success "Additional SSH keys extracted from vault"
    fi
}

#######################################
# Create credential injection file
#######################################
inject_credentials() {
    print_info "Creating credential injection file..."

    # Create directory if it doesn't exist
    mkdir -p "$(dirname "${CREDENTIALS_FILE}")"

    # Source config again to get variables
    source "${CONFIG_FILE}"

    # Create credentials file
    cat > "${CREDENTIALS_FILE}" << EOF
# Live Image Credentials Configuration
# Generated by build-live-image.sh on $(date)
# DO NOT COMMIT THIS FILE

LIVE_USERNAME="${LIVE_USERNAME}"
LIVE_USER_GROUPS="${LIVE_USER_GROUPS:-wheel}"
EOF

    # Add password hash if provided (from vault or config)
    if [ -n "${VAULT_PASSWORD_HASH:-}" ]; then
        echo "LIVE_USER_PASSWORD_HASH=\"${VAULT_PASSWORD_HASH}\"" >> "${CREDENTIALS_FILE}"
    elif [ -n "${LIVE_USER_PASSWORD_HASH:-}" ]; then
        echo "LIVE_USER_PASSWORD_HASH=\"${LIVE_USER_PASSWORD_HASH}\"" >> "${CREDENTIALS_FILE}"
    fi

    # Add SSH key if provided
    if [ -n "${LIVE_USER_SSHKEY_FILE:-}" ]; then
        local ssh_key_content
        ssh_key_content=$(cat "${LIVE_USER_SSHKEY_FILE}")
        echo "LIVE_USER_SSHKEY=\"${ssh_key_content}\"" >> "${CREDENTIALS_FILE}"
    elif [ -n "${LIVE_USER_SSHKEY:-}" ]; then
        echo "LIVE_USER_SSHKEY=\"${LIVE_USER_SSHKEY}\"" >> "${CREDENTIALS_FILE}"
    fi

    # Add additional SSH keys from vault
    if [ -n "${VAULT_ADDITIONAL_KEYS:-}" ]; then
        echo "LIVE_USER_ADDITIONAL_SSHKEYS=\"${VAULT_ADDITIONAL_KEYS}\"" >> "${CREDENTIALS_FILE}"
    fi

    chmod 600 "${CREDENTIALS_FILE}"
    print_success "Credentials file created: ${CREDENTIALS_FILE}"
}

#######################################
# Pull required container images
#######################################
pull_containers() {
    print_info "Pulling CentOS Stream 10 development container..."

    if ! podman pull "${CENTOS_CONTAINER}"; then
        print_error "Failed to pull ${CENTOS_CONTAINER}"
        exit 1
    fi

    print_success "Container image ready"
}

#######################################
# Build ISO using kiwi-ng in container
#######################################
build_iso() {
    print_info "Starting ISO build with kiwi-ng..."

    # Create output directory
    mkdir -p "${OUTPUT_DIR}"

    # Run kiwi-ng build in CentOS Stream 10 container
    print_info "Running kiwi-ng system build in container..."
    print_info "This may take 15-30 minutes depending on network speed..."

    if ! podman run --rm --privileged \
        -v "${KIWI_DESC_DIR}:/code:z" \
        -v "${OUTPUT_DIR}:/outdir:z" \
        -w /code \
        "${CENTOS_CONTAINER}" \
        bash -c "
            set -ex
            # Install EPEL and kiwi
            dnf --assumeyes install epel-release dnf-plugins-core
            dnf --assumeyes upgrade epel-release
            dnf config-manager --set-enabled crb
            dnf --assumeyes install kiwi

            # Run kiwi-ng build
            kiwi-ng --type=iso --profile=MIN-Live --color-output \
                system build --description ./ --target-dir /outdir
        "; then
        print_error "ISO build failed"
        exit 1
    fi

    print_success "ISO build completed successfully"
}

#######################################
# Cleanup temporary files
#######################################
cleanup() {
    print_info "Cleaning up temporary files..."

    if [ -f "${CREDENTIALS_FILE}" ]; then
        rm -f "${CREDENTIALS_FILE}"
        print_success "Removed temporary credentials file"
    fi
}

#######################################
# Show build results
#######################################
show_results() {
    print_success "Build process completed!"
    echo
    print_info "ISO image location:"
    find "${OUTPUT_DIR}" -name "*.iso" -type f -exec ls -lh {} \;
    echo
    print_info "Next steps:"
    echo "  1. Test the ISO in a VM:"
    echo "     qemu-system-x86_64 -m 2048 -cdrom ${OUTPUT_DIR}/*.iso -boot d"
    echo
    echo "  2. Verify SSH access and Ansible connectivity"
    echo "     See README-BUILD.md for complete verification steps"
}

#######################################
# Main function
#######################################
main() {
    echo
    print_info "========================================="
    print_info "CentOS Stream 10 MIN-Live ISO Builder"
    print_info "========================================="
    echo

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --vault-password-file)
                VAULT_PASSWORD_FILE="$2"
                shift 2
                ;;
            -h|--help)
                echo "Usage: $0 [--vault-password-file FILE]"
                echo
                echo "Options:"
                echo "  --vault-password-file FILE    Path to vault password file"
                echo "  -h, --help                    Show this help message"
                echo
                echo "Configuration:"
                echo "  live-image.conf               Plaintext configuration (required)"
                echo "  live-image-vault.yml          Encrypted credentials (optional)"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    # Trap cleanup on exit
    trap cleanup EXIT

    # Execute build steps
    check_podman
    validate_config
    decrypt_vault
    inject_credentials
    pull_containers
    build_iso

    # Show results
    show_results
}

# Run main function
main "$@"
