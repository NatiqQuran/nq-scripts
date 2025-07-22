#!/usr/bin/env bash

# NatiqQuran API Setup Script
# Description: A script to set up and run the NatiqQuran API project using Docker.
# It handles Docker installation, project folder setup, and initial configuration.
# Version: 2.0
# Author: Natiq dev Team
# Usage: bash install.sh [OPTIONS]
#
# Options:
#   --no-install    Skip Docker installation
#   --help         Show this help message
#   --version      Show version information

set -euo pipefail
IFS=$'\n\t'

# --- Script Metadata ---
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="2.0"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Configuration Variables ---
readonly PROJECT_FOLDER="nq-api"
readonly COMPOSE_URL="https://raw.githubusercontent.com/NatiqQuran/nq-api/main/docker-compose.yaml"
readonly NGINX_CONF_URL="https://raw.githubusercontent.com/NatiqQuran/nq-api/main/nginx.conf"
readonly DOCKER_IMAGE="natiqquran/nq-api:latest"
readonly REQUIRED_DOCKER_VERSION="20.10.0"
readonly TIMEOUT_DURATION=15
readonly CONTAINER_START_WAIT=10

# --- Color Constants ---
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# --- Logging Functions ---

# Enhanced logging with different levels
log_info() {
    echo -e "${CYAN}➡️  $*${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $*${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $*${NC}"
}

log_error() {
    echo -e "${RED}❌ $*${NC}" >&2
}

log_debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo -e "${PURPLE}🐛 DEBUG: $*${NC}" >&2
    fi
}

# Progress indicator
show_spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# --- Utility Functions ---

# Check if command exists with better error handling
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate URL accessibility
validate_url() {
    local url="$1"
    if ! curl --connect-timeout 10 --max-time 30 -fsSL --head "$url" >/dev/null 2>&1; then
        log_error "URL is not accessible: $url"
        return 1
    fi
    return 0
}

# Check internet connectivity
check_internet() {
    log_info "Checking internet connectivity..."
    if ! ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        log_error "No internet connection detected"
        return 1
    fi
    log_success "Internet connection verified"
}

# Validate system requirements
check_system_requirements() {
    log_info "Checking system requirements..."
    
    # Check OS
    if [[ ! -f /etc/os-release ]]; then
        log_error "Unsupported operating system"
        return 1
    fi
    
    # Check available disk space (minimum 2GB)
    local available_space
    available_space=$(df . | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 2097152 ]]; then  # 2GB in KB
        log_warning "Low disk space detected. At least 2GB recommended."
    fi
    
    # Check if running as root (not recommended)
    if [[ $EUID -eq 0 ]]; then
        log_warning "Running as root is not recommended"
        read -p "Continue anyway? (y/N): " -t "$TIMEOUT_DURATION" continue_root || continue_root="n"
        if [[ "${continue_root,,}" != "y" ]]; then
            log_error "Script execution cancelled"
            exit 1
        fi
    fi
    
    log_success "System requirements check passed"
}

# Generate secure random secret
generate_secret() {
    local length=${1:-40}
    if command_exists openssl; then
        openssl rand -base64 32 | tr -d "=+/" | cut -c1-$length
    elif [[ -f /dev/urandom ]]; then
        head /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c $length
    else
        log_error "Unable to generate secure random string"
        return 1
    fi
}

# Get public IP with fallback methods
get_public_ip() {
    local ip=""
    local services=(
        "https://api.ipify.org"
        "https://ipecho.net/plain"
        "https://icanhazip.com"
        "https://ident.me"
    )
    
    for service in "${services[@]}"; do
        if ip=$(curl --connect-timeout 5 --max-time 10 -fsSL "$service" 2>/dev/null) && [[ -n "$ip" ]]; then
            # Validate IP format
            if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                echo "$ip"
                return 0
            fi
        fi
    done
    
    log_warning "Could not detect public IP, using localhost"
    echo "localhost"
}

# Enhanced file backup
backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local backup_name="${file}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$file" "$backup_name"
        log_info "Backup created: $backup_name"
    fi
}

# --- Installation Functions ---

# Check Docker version compatibility
check_docker_version() {
    local current_version
    current_version=$(docker --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    
    if [[ -n "$current_version" ]]; then
        # Simple version comparison (assuming semantic versioning)
        if printf '%s\n%s\n' "$REQUIRED_DOCKER_VERSION" "$current_version" | sort -V | head -1 | grep -q "^$REQUIRED_DOCKER_VERSION$"; then
            return 0
        else
            log_warning "Docker version $current_version is older than recommended $REQUIRED_DOCKER_VERSION"
            return 1
        fi
    fi
    return 1
}

# Install Docker with enhanced error handling
install_docker() {
    log_info "🛠️ Installing Docker..."
    
    # Check if curl is available
    if ! command_exists curl; then
        log_error "curl is required but not installed"
        return 1
    fi
    
    # Download and verify installation script
    local docker_script="/tmp/docker-install.sh"
    if ! curl -fsSL https://get.docker.com -o "$docker_script"; then
        log_error "Failed to download Docker installation script"
        return 1
    fi
    
    # Run installation with error handling
    if bash "$docker_script"; then
        rm -f "$docker_script"
        
        # Add current user to docker group if not root
        if [[ $EUID -ne 0 ]] && ! groups "$USER" | grep -q docker; then
            log_info "Adding user to docker group..."
            sudo usermod -aG docker "$USER"
            log_warning "Please log out and log back in for docker group changes to take effect"
        fi
        
        log_success "Docker installed successfully"
        return 0
    else
        rm -f "$docker_script"
        log_error "Docker installation failed"
        return 1
    fi
}

# --- Project Setup Functions ---

# Setup project directory with enhanced error handling
setup_project_folder() {
    log_info "📁 Setting up project folder: $PROJECT_FOLDER"
    
    # Check if folder exists and handle accordingly
    if [[ -d "$PROJECT_FOLDER" ]]; then
        log_warning "Project folder already exists"
        read -p "Do you want to continue and overwrite existing files? (y/N): " -t "$TIMEOUT_DURATION" overwrite || overwrite="n"
        if [[ "${overwrite,,}" != "y" ]]; then
            log_error "Project setup cancelled"
            return 1
        fi
        
        # Backup existing files
        for file in docker-compose.yaml nginx.conf; do
            if [[ -f "$PROJECT_FOLDER/$file" ]]; then
                backup_file "$PROJECT_FOLDER/$file"
            fi
        done
    fi
    
    mkdir -p "$PROJECT_FOLDER"
    
    # Validate URLs before downloading
    log_info "Validating download URLs..."
    validate_url "$COMPOSE_URL" || return 1
    validate_url "$NGINX_CONF_URL" || return 1
    
    # Download files with progress indication
    log_info "⬇️ Downloading docker-compose.yaml..."
    if ! curl --progress-bar -fsSL "$COMPOSE_URL" -o "$PROJECT_FOLDER/docker-compose.yaml"; then
        log_error "Failed to download docker-compose.yaml"
        return 1
    fi
    
    log_info "⬇️ Downloading nginx.conf..."
    if ! curl --progress-bar -fsSL "$NGINX_CONF_URL" -o "$PROJECT_FOLDER/nginx.conf"; then
        log_error "Failed to download nginx.conf"
        return 1
    fi
    
    # Verify downloaded files
    for file in docker-compose.yaml nginx.conf; do
        if [[ ! -s "$PROJECT_FOLDER/$file" ]]; then
            log_error "Downloaded file is empty or corrupted: $file"
            return 1
        fi
    done
    
    log_success "Project files downloaded successfully to $PROJECT_FOLDER"
}

# Enhanced configuration customization
customize_files() {
    local project_dir="$1"
    local compose_file="$project_dir/docker-compose.yaml"
    local nginx_file="$project_dir/nginx.conf"
    
    log_info "🔧 Customizing configuration files..."
    
    # Validate compose file exists and is readable
    if [[ ! -f "$compose_file" ]]; then
        log_error "docker-compose.yaml not found in $project_dir"
        return 1
    fi
    
    # Generate SECRET_KEY with enhanced security
    log_info "🔒 Generating secure SECRET_KEY..."
    local secret
    if ! secret=$(generate_secret 50); then
        log_error "Failed to generate secret key"
        return 1
    fi
    
    # Update SECRET_KEY with better regex
    if grep -q "SECRET_KEY:" "$compose_file"; then
        local sk_indent
        sk_indent=$(grep -E '^\s*SECRET_KEY:' "$compose_file" | sed -E 's/(^\s*).*/\1/')
        sed -i "s|^\s*SECRET_KEY:.*|${sk_indent}SECRET_KEY: $secret|" "$compose_file"
        log_success "SECRET_KEY updated"
    else
        log_warning "SECRET_KEY not found in compose file"
    fi
    
    # Set DJANGO_ALLOWED_HOSTS with fallback
    log_info "🌐 Configuring DJANGO_ALLOWED_HOSTS..."
    local ip
    ip=$(get_public_ip)
    
    if grep -q "DJANGO_ALLOWED_HOSTS:" "$compose_file"; then
        local dh_indent
        dh_indent=$(grep -E '^\s*DJANGO_ALLOWED_HOSTS:' "$compose_file" | sed -E 's/(^\s*).*/\1/')
        sed -i "s|^\s*DJANGO_ALLOWED_HOSTS:.*|${dh_indent}DJANGO_ALLOWED_HOSTS: $ip,localhost,127.0.0.1|" "$compose_file"
        log_success "DJANGO_ALLOWED_HOSTS set to: $ip,localhost,127.0.0.1"
    else
        log_warning "DJANGO_ALLOWED_HOSTS not found in compose file"
    fi
    
    # Validate YAML syntax
    if command_exists python3; then
        if ! python3 -c "import yaml; yaml.safe_load(open('$compose_file'))" 2>/dev/null; then
            log_warning "YAML syntax validation failed - please check the file manually"
        else
            log_success "YAML syntax validation passed"
        fi
    fi
    
    # Manual edit options with better UX
    prompt_manual_edit "$compose_file" "docker-compose.yaml"
    prompt_manual_edit "$nginx_file" "nginx.conf"
}

# Improved manual edit prompt
prompt_manual_edit() {
    local file="$1"
    local filename="$2"
    
    if [[ ! -f "$file" ]]; then
        log_warning "File not found: $filename"
        return 1
    fi
    
    echo ""
    log_info "Manual edit option for $filename"
    read -p "Do you want to manually edit $filename? (y/N): " -t "$TIMEOUT_DURATION" ans || ans="n"
    
    case "${ans,,}" in
        y|yes)
            # Try different editors in order of preference
            local editors=(code nano vim vi)
            local editor_found=false
            
            for editor in "${editors[@]}"; do
                if command_exists "$editor"; then
                    log_info "Opening $filename with $editor..."
                    "$editor" "$file"
                    editor_found=true
                    break
                fi
            done
            
            if [[ "$editor_found" == false ]]; then
                log_warning "No suitable editor found. Please edit $file manually."
            else
                log_success "Manual edit of $filename completed"
            fi
            ;;
        *)
            log_info "⏩ Skipping manual edit of $filename"
            ;;
    esac
}

# --- Docker Operations ---

# Enhanced Docker container management
start_containers() {
    local project_dir="$1"
    local compose_file="$project_dir/docker-compose.yaml"
    
    log_info "🚀 Starting containers..."
    local start_time
    start_time=$(date +%s)
    
    # Pre-flight checks
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon is not running"
        return 1
    fi
    
    if [[ ! -f "$compose_file" ]]; then
        log_error "docker-compose.yaml not found"
        return 1
    fi
    
    # Start containers with better error handling
    if ! docker compose -f "$compose_file" up -d; then
        log_error "Failed to start containers"
        log_info "You can check logs with: docker compose -f $compose_file logs"
        return 1
    fi
    
    local end_time
    end_time=$(date +%s)
    local startup_time=$((end_time - start_time))
    
    log_success "Containers started successfully in ${startup_time}s"
    
    # Wait for container to be ready
    log_info "🔍 Waiting ${CONTAINER_START_WAIT}s for containers to initialize..."
    sleep "$CONTAINER_START_WAIT"
    
    return 0
}

# Find and validate container
find_container() {
    local container_id
    container_id=$(docker ps --filter "ancestor=$DOCKER_IMAGE" --format "{{.ID}}" | head -n 1)
    
    if [[ -z "$container_id" ]]; then
        log_error "Could not find running container with image $DOCKER_IMAGE"
        log_info "Available containers:"
        docker ps --format "table {{.ID}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
        return 1
    fi
    
    # Verify container is healthy
    local container_status
    container_status=$(docker inspect --format='{{.State.Status}}' "$container_id" 2>/dev/null)
    
    if [[ "$container_status" != "running" ]]; then
        log_error "Container is not in running state: $container_status"
        return 1
    fi
    
    echo "$container_id"
}

# Enhanced superuser creation
create_superuser() {
    local container_id="$1"
    
    log_info "👤 Creating Django superuser..."
    echo ""
    log_warning "You will now be connected to the container to create a superuser."
    log_info "Please follow the prompts. The script will continue after completion."
    echo ""
    
    sleep 3
    
    # Attempt to create superuser with better error handling
    if docker exec -it "$container_id" python3 manage.py createsuperuser; then
        log_success "Superuser created successfully"
    else
        log_warning "Superuser creation failed or was cancelled"
        log_info "You can create a superuser later with:"
        log_info "docker exec -it $container_id python3 manage.py createsuperuser"
    fi
}

# --- Help and Version Functions ---

show_help() {
    cat << EOF
${SCRIPT_NAME} - NatiqQuran API Setup Script

DESCRIPTION:
    Professional setup script for NatiqQuran API project using Docker.
    Handles Docker installation, project setup, and initial configuration.

USAGE:
    ${SCRIPT_NAME} [OPTIONS]

OPTIONS:
    --no-install    Skip Docker installation
    --help          Show this help message
    --version       Show version information
    --debug         Enable debug output

EXAMPLES:
    ${SCRIPT_NAME}                 # Full setup with Docker installation
    ${SCRIPT_NAME} --no-install    # Setup without installing Docker
    DEBUG=1 ${SCRIPT_NAME}         # Run with debug output

REQUIREMENTS:
    - Ubuntu/Debian-based system
    - Internet connection
    - curl command
    - sudo privileges (for Docker installation)

For more information, visit: https://github.com/NatiqQuran/nq-api
EOF
}

show_version() {
    echo "${SCRIPT_NAME} version ${SCRIPT_VERSION}"
}

# --- Cleanup and Error Handling ---

cleanup() {
    log_debug "Performing cleanup..."
    # Remove temporary files if any
    rm -f /tmp/docker-install.sh
}

error_handler() {
    local line_number=$1
    log_error "An error occurred on line $line_number"
    log_info "For troubleshooting, run with DEBUG=1 $SCRIPT_NAME"
    cleanup
    exit 1
}

# Set error handler
trap 'error_handler ${LINENO}' ERR
trap cleanup EXIT

# --- Main Execution Logic ---

main() {
    # Parse command line arguments
    local skip_docker_install=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --no-install)
                skip_docker_install=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            --version|-v)
                show_version
                exit 0
                ;;
            --debug)
                export DEBUG=1
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Script header
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}   NatiqQuran API Setup Script v${SCRIPT_VERSION}${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    # Pre-flight checks
    check_system_requirements
    check_internet
    
    # Package updates
    log_info "🔄 Updating package list..."
    if command_exists apt-get; then
        sudo apt-get update -qq
    elif command_exists yum; then
        sudo yum check-update -q || true
    fi
    log_success "Package list updated"
    
    # Docker handling
    if [[ "$skip_docker_install" == false ]]; then
        if command_exists docker && check_docker_version; then
            log_success "Docker is already installed and up to date"
        else
            if command_exists docker; then
                log_warning "Docker is installed but may be outdated"
                read -p "Do you want to reinstall Docker? (y/N): " -t "$TIMEOUT_DURATION" reinstall || reinstall="n"
                if [[ "${reinstall,,}" =~ ^(y|yes)$ ]]; then
                    install_docker || exit 1
                fi
            else
                install_docker || exit 1
            fi
        fi
    else
        log_info "⏩ Skipping Docker installation as requested"
        if ! command_exists docker; then
            log_error "Docker is not installed and --no-install was specified"
            exit 1
        fi
    fi
    
    # Main setup tasks
    setup_project_folder || exit 1
    customize_files "$PROJECT_FOLDER" || exit 1
    start_containers "$PROJECT_FOLDER" || exit 1
    
    # Find container and create superuser
    local container_id
    if container_id=$(find_container); then
        create_superuser "$container_id"
    else
        log_error "Container setup failed"
        exit 1
    fi
    
    # Final success message
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}🎉 Setup completed successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    log_success "NatiqQuran API is now running!"
    log_info "📁 Project files are in: $PROJECT_FOLDER"
    log_info "🌐 Access your API at: http://$(get_public_ip)"
    log_info "📊 Check logs with: docker compose -f $PROJECT_FOLDER/docker-compose.yaml logs"
    log_info "🛑 Stop services with: docker compose -f $PROJECT_FOLDER/docker-compose.yaml down"
    echo ""
}

# Execute main function with all arguments
main "$@"