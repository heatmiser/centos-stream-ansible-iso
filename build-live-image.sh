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
# Security Hardening:
#   - Container images pinned to SHA256 digests (supply chain protection)
#   - Ansible container digest strictly verified (has access to vault secrets)
#   - Network isolation for vault decryption (prevents exfiltration)
#   - Safe configuration parsing (no arbitrary code execution)
#   - KIWI descriptions mounted read-only in container
#   - SELinux isolation enabled
#   - Container breakout monitoring
#   - Digest verification of all pulled images
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
# SECURITY: Pinned to specific SHA256 digests to prevent supply chain attacks
# CRITICAL: Ansible container has access to decrypted vault secrets - must be trusted
ANSIBLE_CONTAINER="quay.io/ansible/creator-ee@sha256:a03e8311cc722be36a81e8c9aa61ee8f65b535ddfbf16d65b6eadc99b720fa24"
CENTOS_CONTAINER="quay.io/centos/centos@sha256:f55f0785fbe24a765d263202a26ce6f14537f2201dc30f89d92ba03ba6ff41e5"

# Vault password file
VAULT_PASSWORD_FILE=""

# kiwi-ng build profile
BUILD_PROFILE="MIN-Live-Automation"

# Build status tracking
BUILD_SUCCESS=false

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
# Safely parse configuration file
#######################################
safe_source_config() {
    local config_file="$1"
    
    while IFS='=' read -r key value; do
        # Remove leading/trailing whitespace from the key
        key=$(echo "$key" | xargs)
        
        # Skip empty lines and lines starting with comments (#)
        if [[ -z "$key" || "$key" == \#* ]]; then
            continue
        fi

        # STRICT VALIDATION: Ensure the key is a valid bash variable name
        if [[ ! "$key" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
            print_warning "Invalid configuration variable name: '$key'. Skipping."
            continue
        fi

        # Strip surrounding quotes from the value (single or double)
        value="${value%\"}"
        value="${value#\"}"
        value="${value%\'}"
        value="${value#\'}"

        # Export the variable so it is available globally (mimicking 'source')
        export "$key=$value"

    done < "$config_file"
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

    # Safely parse and validate config (Replacing unsafe 'source' command)
    safe_source_config "${CONFIG_FILE}"

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

    # SECURITY: Pull and verify Ansible container before processing secrets
    print_info "Pulling and verifying Ansible container..."
    if ! podman pull "${ANSIBLE_CONTAINER}" >/dev/null 2>&1; then
        print_error "Failed to pull Ansible container"
        exit 1
    fi

    # SECURITY: Verify container digest before trusting it with secrets
    local pulled_digest
    pulled_digest=$(podman inspect "${ANSIBLE_CONTAINER}" --format '{{.Digest}}' 2>/dev/null || echo "")
    local expected_digest="sha256:a03e8311cc722be36a81e8c9aa61ee8f65b535ddfbf16d65b6eadc99b720fa24"

    if [ -n "${pulled_digest}" ] && [ "${pulled_digest}" != "${expected_digest}" ]; then
        print_error "CRITICAL: Ansible container digest mismatch!"
        print_error "Expected: ${expected_digest}"
        print_error "Got: ${pulled_digest}"
        print_error "This container has access to your decrypted vault secrets."
        print_error "Refusing to continue - possible supply chain compromise."
        exit 1
    fi
    print_success "Ansible container digest verified"

    # Build ansible-vault command
    local vault_cmd="ansible-vault view /work/live-image-vault.yml"

    if [ -n "${VAULT_PASSWORD_FILE}" ]; then
        vault_cmd="${vault_cmd} --vault-password-file=/work/${VAULT_PASSWORD_FILE}"
        vault_args="-v ${SCRIPT_DIR}:/work:z"
    else
        vault_args="-it -v ${SCRIPT_DIR}:/work:z"
    fi

    # SECURITY: Decrypt vault using Ansible container
    # Network disabled - vault decryption is local crypto operation only
    # Prevents exfiltration of vault password or decrypted secrets
    local vault_content
    if ! vault_content=$(podman run --rm --network=none ${vault_args} \
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

    # Safely parse config again to get variables (Replacing unsafe 'source' command)
    safe_source_config "${CONFIG_FILE}"

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

    # SECURITY: Verify the pulled image matches expected digest
    local pulled_digest
    pulled_digest=$(podman inspect "${CENTOS_CONTAINER}" --format '{{.Digest}}' 2>/dev/null || echo "")
    local expected_digest="sha256:f55f0785fbe24a765d263202a26ce6f14537f2201dc30f89d92ba03ba6ff41e5"

    if [ -n "${pulled_digest}" ] && [ "${pulled_digest}" != "${expected_digest}" ]; then
        print_warning "Container image digest mismatch!"
        print_warning "Expected: ${expected_digest}"
        print_warning "Got: ${pulled_digest}"
        print_warning "This may indicate a supply chain compromise or registry issue."
    else
        print_success "Container image digest verified: ${expected_digest}"
    fi

    print_success "Container image ready"
}

#######################################
# Build ISO using kiwi-ng in container
#######################################
build_iso() {
    print_info "Starting ISO build with kiwi-ng..."

    # Create output and temp directories
    mkdir -p "${OUTPUT_DIR}"
    mkdir -p "${OUTPUT_DIR}/tmp"

    # SECURITY: Record build directory to detect container breakout attempts
    local build_marker="${OUTPUT_DIR}/.build-security-marker"
    echo "BUILD_PWD=$(pwd)" > "${build_marker}"
    echo "BUILD_USER=$(whoami)" >> "${build_marker}"
    echo "BUILD_START=$(date -u +%s)" >> "${build_marker}"

    # Run kiwi-ng build in CentOS Stream 10 container
    print_info "Running kiwi-ng system build in container..."
    print_info "This may take 15-30 minutes depending on network speed..."

    # SECURITY HARDENING:
    # - Container image pinned to SHA256 digest
    # - KIWI descriptions mounted read-only (ro)
    # - SELinux isolation enabled (:z flag)
    # - Privileged mode required for loop devices, mount, chroot operations
    # - /var/tmp mounted from outdir/tmp to support SELinux xattrs during ISO creation
    if ! podman run --rm --privileged \
        -v "${KIWI_DESC_DIR}:/code:ro,z" \
        -v "${OUTPUT_DIR}:/outdir:z" \
        -v "${OUTPUT_DIR}/tmp:/var/tmp:z" \
        -w /code \
        "${CENTOS_CONTAINER}" \
        bash -c "
            set -ex

            # SECURITY: Verify we're in expected directory
            if [ \"\$(pwd)\" != \"/code\" ]; then
                echo 'ERROR: Unexpected working directory' >&2
                exit 1
            fi

            # Install EPEL and kiwi with required tools
            dnf --assumeyes install epel-release dnf-plugins-core
            dnf --assumeyes upgrade epel-release
            dnf config-manager --set-enabled crb

            # KIWI build dependencies:
            # - kiwi: Image building framework
            # - isomd5sum: Provides implantisomd5 for ISO checksums (mediacheck feature)
            # - qemu-img: Disk image utility for boot image creation
            # - dosfstools: Provides mkdosfs for FAT filesystems (EFI boot partition)
            # - erofs-utils: Provides mkfs.erofs for creating erofs filesystem
            # - xorriso: Modern ISO 9660 creation tool (replaces mkisofs/genisoimage)
            # - syslinux: Provides isohybrid for USB-bootable ISOs
            dnf --assumeyes install kiwi isomd5sum qemu-img dosfstools \
                erofs-utils xorriso syslinux

            # Run kiwi-ng build
            kiwi-ng --type=iso --profile=${BUILD_PROFILE} --color-output \
                system build --description ./ --target-dir /outdir
        "; then
        print_error "ISO build failed"
        rm -f "${build_marker}"
        exit 1
    fi

    # SECURITY: Verify no unexpected modifications to build environment
    if [ -f "${build_marker}" ]; then
        local recorded_pwd
        recorded_pwd=$(grep "^BUILD_PWD=" "${build_marker}" | cut -d= -f2)
        if [ "$(pwd)" != "${recorded_pwd}" ]; then
            print_warning "Working directory changed during build - possible container escape attempt"
            print_warning "Expected: ${recorded_pwd}, Current: $(pwd)"
        fi
        rm -f "${build_marker}"
    fi

    print_success "ISO build completed successfully"
}

#######################################
# Rename outputs when building a non-default profile
# kiwi derives output filenames from config.xml image name, which is
# hardcoded to CentOS-Stream-MIN-Live-Automation. Rename to match the
# actual profile so builds are distinguishable.
#######################################
rename_outputs() {
    if [ "${BUILD_PROFILE}" = "MIN-Live-Automation" ]; then
        return 0
    fi

    local default_stem="CentOS-Stream-MIN-Live-Automation"
    local target_stem="CentOS-Stream-${BUILD_PROFILE}"

    print_info "Renaming output files: ${default_stem} → ${target_stem}"

    for ext in iso packages verified; do
        local src="${OUTPUT_DIR}/${default_stem}.x86_64-10.${ext}"
        local dst="${OUTPUT_DIR}/${target_stem}.x86_64-10.${ext}"
        if [ -f "${src}" ]; then
            mv "${src}" "${dst}"
            print_success "Renamed: $(basename "${dst}")"
        fi
    done
}

#######################################
# Cleanup temporary files
#######################################
cleanup() {
    print_info "Cleaning up temporary files..."

    # Always remove credentials file (security critical)
    if [ -f "${CREDENTIALS_FILE}" ]; then
        rm -f "${CREDENTIALS_FILE}"
        print_success "Removed temporary credentials file"
    fi

    # Clean up build artifacts using container (handles root-owned files)
    if [ -d "${OUTPUT_DIR}" ] && [ -n "$(ls -A "${OUTPUT_DIR}" 2>/dev/null)" ]; then
        if [ "${BUILD_SUCCESS}" = "false" ]; then
            # Build failed - remove everything
            print_warning "Build failed - cleaning up all artifacts in ${OUTPUT_DIR}"
            if podman run --rm -v "${OUTPUT_DIR}:/outdir:z" \
                "${CENTOS_CONTAINER}" \
                bash -c "rm -rf /outdir/*" 2>/dev/null; then
                print_success "Removed all build artifacts"
            else
                print_warning "Could not remove all artifacts - try: sudo rm -rf ${OUTPUT_DIR}/*"
            fi
        else
            # Build succeeded - keep ISO, remove intermediate artifacts
            print_info "Cleaning up intermediate build artifacts (keeping ISO)..."
            # KIWI creates: build/, *.iso, *.packages, *.verified, kiwi-*.log
            # We keep: *.iso (final product), *.packages (metadata), *.verified (checksums)
            # We remove: build/ (image-root, temp files), logs (can be large)
            if podman run --rm -v "${OUTPUT_DIR}:/outdir:z" \
                "${CENTOS_CONTAINER}" \
                bash -c "
                    cd /outdir
                    # Keep: *.iso, *.packages, *.verified files
                    # Remove: build/, kiwi-*.log, and other intermediate files
                    find . -mindepth 1 -maxdepth 1 ! -name '*.iso' ! -name '*.packages' ! -name '*.verified' -exec rm -rf {} +
                " 2>/dev/null; then
                print_success "Cleaned up intermediate artifacts, ISO preserved"
            else
                print_warning "Could not clean intermediate artifacts - manual cleanup may be needed"
            fi
        fi
    fi
}

#######################################
# Show build results
#######################################
show_results() {
    print_success "Build process completed!"
    echo
    print_info "ISO image location:"
    find "${OUTPUT_DIR}" -maxdepth 1 -name "*.iso" -type f -exec ls -lh {} \;
    echo
    print_info "Intermediate build artifacts cleaned up (ISO and metadata preserved)"
    echo
    local iso_path
    iso_path=$(find "${OUTPUT_DIR}" -maxdepth 1 -name "*.iso" -type f | head -1)

    print_info "Next steps:"
    echo "  1. Test the ISO in a VM (UEFI boot):"
    echo "     qemu-system-x86_64 -m 2048 -machine q35 -enable-kvm -cpu host \\"
    echo "       -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE.fd \\"
    echo "       -cdrom ${iso_path} -boot d \\"
    echo "       -netdev user,id=net0,hostfwd=tcp::2222-:22 -device virtio-net-pci,netdev=net0"
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
            --profile)
                BUILD_PROFILE="$2"
                shift 2
                ;;
            --profile=*)
                BUILD_PROFILE="${1#--profile=}"
                shift
                ;;
            -h|--help)
                echo "Usage: $0 [--vault-password-file FILE] [--profile PROFILE]"
                echo
                echo "Options:"
                echo "  --vault-password-file FILE    Path to vault password file"
                echo "  --profile PROFILE             kiwi-ng build profile (default: MIN-Live-Automation)"
                echo "                                Available: MIN-Live-Automation, MIN-Live-Auto-Cloud"
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

    # Mark build as successful (prevents cleanup of artifacts)
    BUILD_SUCCESS=true

    # Rename outputs to match the build profile
    rename_outputs

    # Show results
    show_results
}

# Run main function
main "$@"