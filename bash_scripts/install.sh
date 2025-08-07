#!/usr/bin/env bash

# NatiqQuran API Setup Script
# Description: A script to set up and run the NatiqQuran API project using Docker.
# It handles Docker installation, project folder setup, and initial configuration.
# Features: Complete lifecycle management, user-friendly, enhanced security, comprehensive logging
# Version: 2.3
# Author: Natiq dev Team
# Usage: bash setup.sh [COMMAND] [OPTIONS]
#
# Options:
#   --no-install   Skip Docker installation
#   --help         Show this help message
#   --version      Show version information

set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
# === SCRIPT METADATA & CONFIGURATION
# ==============================================================================

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="2.3"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Project Configuration ---
readonly PROJECT_FOLDER="nq-api"
readonly SOURCE_FILE="docker-compose.source.yaml"
readonly PROD_FILE="docker-compose.prod.yaml"
readonly NGINX_FILE="nginx.conf"
readonly COMPOSE_URL="https://raw.githubusercontent.com/NatiqQuran/nq-api/main/docker-compose.yaml"
readonly NGINX_URL="https://raw.githubusercontent.com/NatiqQuran/nq-api/main/nginx.conf"
readonly DOCKER_IMAGE="natiqquran/nq-api:latest"
readonly MIN_DOCKER_VERSION="20.10.0"
readonly TIMEOUT=15
readonly WAIT_TIME=10

# --- Color Constants ---
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly PURPLE='\033[0;35m'
readonly NC='\033[0m'

# ==============================================================================
# === LOGGING FUNCTIONS
# ==============================================================================

# Log an informational message
log_info() { echo -e "${CYAN}ℹ️  $*${NC}" >&2; }

# Log a success message
log_success() { echo -e "${GREEN}✅ $*${NC}" >&2; }

# Log a warning message
log_warning() { echo -e "${YELLOW}⚠️  $*${NC}" >&2; }

# Log an error message
log_error() { echo -e "${RED}❌ $*${NC}" >&2; }

# Log a debug message (only if DEBUG=1 is set)
log_debug() { [[ "${DEBUG:-0}" == "1" ]] && echo -e "${PURPLE}🐛 $*${NC}" >&2 || true; }

# ==============================================================================
# === UTILITY FUNCTIONS
# ==============================================================================

command_exists() {
    command -v "$1" >/dev/null 2>&1
}
validate_url() {
    curl --connect-timeout 10 --max-time 30 -fsSL --head "$1" >/dev/null 2>&1
}
check_internet() {
    log_info "Checking internet connectivity..."
    if ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        log_success "Internet connection verified"
    else
        log_error "No internet connection"; return 1
    fi
}

check_system() {
    log_info "Checking system requirements..."
    
    # OS Check
    [[ -f /etc/os-release ]] || { log_error "Unsupported OS"; return 1; }
    
    # Disk space (min 2GB)
    local space; space=$(df . | awk 'NR==2 {print $4}')
    [[ $space -lt 2097152 ]] && log_warning "Low disk space (<2GB available)"
    
    # Root check
    [[ $EUID -eq 0 ]] && log_warning "Running as root"
    
    log_success "System requirements OK"
}

generate_secret() {
    local len=${1:-32}
    if command_exists openssl; then
        openssl rand -base64 48 | tr -d "=+/\n" | cut -c1-$len
    else
        head /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c $len
    fi
}

get_public_ip() {
    for service in "https://api.ipify.org" "https://ipecho.net/plain" "https://icanhazip.com"; do
        if ip=$(curl --connect-timeout 5 -fsSL "$service" 2>/dev/null) && [[ $ip =~ ^[0-9.]+$ ]]; then
            echo "$ip"; return 0
        fi
    done
    echo "localhost"
}

# ==============================================================================
# === DOCKER & FIREWALL MANAGEMENT
# ==============================================================================

check_docker_version() {
    local current; current=$(docker --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    [[ -n "$current" ]] && printf '%s\n%s\n' "$MIN_DOCKER_VERSION" "$current" | sort -V | head -1 | grep -q "^$MIN_DOCKER_VERSION"
}

# Install Docker using the official script
install_docker() {
    log_info "Installing Docker..."
    command_exists curl || { log_error "curl is required but not found"; return 1; }
    
    local script="/tmp/docker-install.sh"
    curl -fsSL https://get.docker.com -o "$script" || { log_error "Failed to download Docker installer"; return 1; }
    
    if bash "$script"; then
        rm -f "$script"
        if [[ $EUID -ne 0 ]] && ! groups "$USER" | grep -q docker; then
            log_info "Adding user to docker group..."
            sudo usermod -aG docker "$USER"
            log_warning "Please re-login for docker group changes to take effect"
        fi
        log_success "Docker installed successfully"
    else
        rm -f "$script"; log_error "Docker installation failed"; return 1
    fi
}

setup_docker() {
    local skip_install="$1"
    
    if [[ "$skip_install" == "true" ]]; then
        log_info "Skipping Docker installation as requested"
        command_exists docker || { log_error "Docker not found and --no-install specified"; return 1; }
    else
        if command_exists docker && check_docker_version; then
            log_success "Docker is already installed and up to date"
        else
            install_docker || return 1
        fi
    fi
}

setup_firewall() {
    log_info "Setting up UFW firewall..."
    
    if ! command_exists ufw; then
        if command_exists apt-get; then
            sudo apt-get update -qq && sudo apt-get install -y ufw
        else
            log_warning "Cannot auto-install UFW. Please install it manually."
            return 1
        fi
    fi

    {
        sudo ufw --force reset
        sudo ufw default deny incoming
        sudo ufw default allow outgoing
        sudo ufw allow ssh
        sudo ufw allow 80/tcp
        sudo ufw allow 443/tcp
        sudo ufw --force enable
    } >/dev/null 2>&1
    
    log_success "UFW configured (SSH, HTTP, HTTPS allowed)"
}

# ==============================================================================
# === PROJECT SETUP & CONFIGURATION
# ==============================================================================

# Download the source configuration files from GitHub
download_files() {
    log_info "Setting up project folder: $PROJECT_FOLDER"
    mkdir -p "$PROJECT_FOLDER"
    
    log_info "Downloading configuration files..."
    validate_url "$COMPOSE_URL" || { log_error "Cannot access compose file URL"; return 1; }
    validate_url "$NGINX_URL" || { log_error "Cannot access nginx config URL"; return 1; }
    
    curl -fsSL "$COMPOSE_URL" -o "$PROJECT_FOLDER/$SOURCE_FILE" || { log_error "Failed to download compose file"; return 1; }
    curl -fsSL "$NGINX_URL" -o "$PROJECT_FOLDER/$NGINX_FILE" || { log_error "Failed to download nginx config"; return 1; }
    
    [[ -s "$PROJECT_FOLDER/$SOURCE_FILE" ]] || { log_error "Downloaded compose file is empty"; return 1; }
    [[ -s "$PROJECT_FOLDER/$NGINX_FILE" ]] || { log_error "Downloaded nginx config is empty"; return 1; }
    
    log_success "Configuration files downloaded"
}

# Prompt the user to manually edit a configuration file
prompt_edit() {
    local file="$1"
    local name="$2"
    
    echo
    log_info "Edit option for $name"
    read -p "Do you want to edit '$name' before deployment? (y/N): " -t "$TIMEOUT" edit || edit="n"
    
    if [[ "${edit,,}" =~ ^y ]]; then
        for editor in nano vim vi; do
            if command_exists "$editor"; then
                log_info "Opening '$name' with $editor..."
                "$editor" "$file"
                log_success "Edit completed"
                return 0
            fi
        done
        log_warning "No editor found. Please edit '$file' manually."
    else
        log_info "Skipping manual edit of '$name'."
    fi
}

# Prompt user for credentials if they weren't provided as flags
prompt_for_credentials() {
    log_info "Credential flags were not provided. Entering interactive setup."
    echo -e "You can provide credentials in two ways:"
    echo -e "1. On a single line: ${YELLOW}dbname=user dbpass=secret ...${NC}"
    echo -e "2. On multiple lines, ending each line with a backslash (${YELLOW}\\${NC})"
    echo -e "   Example:"
    echo -e "   ${YELLOW}dbname=myuser \\${NC}"
    echo -e "   ${YELLOW}dbpass=mypassword${NC}"
    echo -e "Type ${GREEN}END${NC} on a new line when you are finished."
    echo

    local all_input=""
    while IFS= read -r line; do
        # Stop reading if the user types END
        [[ "$line" == "END" ]] && break
        # Append the line to the full input string, removing trailing backslashes
        all_input+="${line%\\} "
    done

    # Parse the collected input string to find key=value pairs
    # This pattern handles spaces around the '=' sign
    db_user=$(echo "$all_input" | grep -o 'dbname\s*=\s*[^ ]*' | head -n 1 | cut -d'=' -f2- | tr -d ' ')
    db_pass=$(echo "$all_input" | grep -o 'dbpass\s*=\s*[^ ]*' | head -n 1 | cut -d'=' -f2- | tr -d ' ')
    rabbit_user=$(echo "$all_input" | grep -o 'rabbituser\s*=\s*[^ ]*' | head -n 1 | cut -d'=' -f2- | tr -d ' ')
    rabbit_pass=$(echo "$all_input" | grep -o 'rabbitpass\s*=\s*[^ ]*' | head -n 1 | cut -d'=' -f2- | tr -d ' ')

    # Export variables to be used by the calling function
    export db_user db_pass rabbit_user rabbit_pass
}


# Create a temporary, production-ready compose file by injecting secrets
create_production_config() {
    local db_user="$1"
    local db_pass="$2"
    local rabbit_user="$3"
    local rabbit_pass="$4"
    
    local source="$PROJECT_FOLDER/$SOURCE_FILE"
    local temp_file="$PROJECT_FOLDER/$PROD_FILE"
    
    [[ -f "$source" ]] || { log_error "Source file not found: $source"; return 1; }
    
    log_debug "Creating production configuration from source..."
    
    local secret_key; secret_key=$(generate_secret 50)
    local allowed_hosts; allowed_hosts="$(get_public_ip),localhost,127.0.0.1"
    
    # Create the production config by replacing placeholders in the source file
    # The new sed pattern handles leading whitespace to preserve YAML indentation
    sed \
        -e "s/^\([[:space:]]*POSTGRES_USER:\).*/\1 ${db_user}/" \
        -e "s/^\([[:space:]]*POSTGRES_PASSWORD:\).*/\1 ${db_pass}/" \
        -e "s/^\([[:space:]]*DATABASE_USERNAME:\).*/\1 ${db_user}/" \
        -e "s/^\([[:space:]]*DATABASE_PASSWORD:\).*/\1 ${db_pass}/" \
        -e "s/^\([[:space:]]*RABBITMQ_DEFAULT_USER:\).*/\1 ${rabbit_user}/" \
        -e "s/^\([[:space:]]*RABBITMQ_DEFAULT_PASS:\).*/\1 ${rabbit_pass}/" \
        -e "s|^\([[:space:]]*CELERY_BROKER_URL:\).*|\1 amqp://${rabbit_user}:${rabbit_pass}@rabbitmq:5672//|" \
        -e "s/^\([[:space:]]*SECRET_KEY:\).*/\1 ${secret_key}/" \
        -e "s/^\([[:space:]]*DJANGO_ALLOWED_HOSTS:\).*/\1 ${allowed_hosts}/" \
        -e "s/^\([[:space:]]*DEBUG:\).*/\1 0/" \
        "$source" > "$temp_file"
    
    [[ -s "$temp_file" ]] || { log_error "Production configuration file is empty or not created"; return 1; }
    
    log_debug "Production config created at: $temp_file"
    printf "%s" "$temp_file"
}

# ==============================================================================
# === CONTAINER OPERATIONS
# ==============================================================================

# Start containers using the production config and clean up afterwards
start_and_cleanup_containers() {
    local prod_config="$1"
    
    log_info "Starting containers..."
    local start_time; start_time=$(date +%s)
    
    if docker compose -f "$prod_config" up -d; then
        local end_time; end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        log_success "Containers started successfully in ${duration}s"
        log_debug "Cleaning up production config file: $prod_config"
        rm -f "$prod_config"
        
        log_info "Waiting ${WAIT_TIME}s for services to initialize..."
        sleep "$WAIT_TIME"
        return 0
    else
        log_error "Failed to start containers"
        log_info "Displaying container logs for debugging:"
        docker compose -f "$prod_config" logs --tail=20 2>/dev/null || true
        rm -f "$prod_config"
        return 1
    fi
}

# A wrapper for restart/update commands
manage_containers() {
    local action="$1"
    local db_user="$2"
    local db_pass="$3"
    local rabbit_user="$4"
    local rabbit_pass="$5"
    
    local source_file="$PROJECT_FOLDER/$SOURCE_FILE"
    [[ -f "$source_file" ]] || { log_error "Project not found. Run 'install' first."; return 1; }
    
    log_info "Stopping all services..."
    docker compose -f "$source_file" down --remove-orphans 2>/dev/null || log_warning "Some containers may not have stopped cleanly."
    
    if [[ "$action" == "update" ]]; then
        log_info "Pulling latest images..."
        docker compose -f "$source_file" pull
    fi
    
    log_info "Creating new production configuration..."
    local prod_config; prod_config=$(create_production_config "$db_user" "$db_pass" "$rabbit_user" "$rabbit_pass")
    [[ -n "$prod_config" ]] || { log_error "Failed to get production config path"; return 1; }
    
    start_and_cleanup_containers "$prod_config"
}

# Create a Django superuser interactively
create_superuser() {
    log_info "Creating Django superuser..."
    
    local container_id; container_id=$(docker ps -q -f "ancestor=$DOCKER_IMAGE" | head -n 1)
    [[ -z "$container_id" ]] && { log_error "API container not found"; return 1; }
    
    echo
    log_warning "You will now be connected to the container to create a superuser."
    log_info "Please follow the prompts to set up your admin account."
    sleep 3
    
    if docker exec -it "$container_id" python3 manage.py createsuperuser; then
        log_success "Superuser created successfully."
    else
        log_warning "Superuser creation failed or was cancelled."
        log_info "You can create one later with: docker exec -it $container_id python3 manage.py createsuperuser"
    fi
}

# ==============================================================================
# === MAIN COMMANDS & VALIDATION
# ==============================================================================

# Validate that all required credentials are provided for management commands
validate_credentials() {
    local action="$1"
    local db_user="$2"
    local db_pass="$3"
    local rabbit_user="$4"
    local rabbit_pass="$5"
    
    if [[ "$action" != "install" ]]; then
        local missing=()
        [[ -z "$db_user" ]] && missing+=("--dbname")
        [[ -z "$db_pass" ]] && missing+=("--dbpass")
        [[ -z "$rabbit_user" ]] && missing+=("--rabbituser")
        [[ -z "$rabbit_pass" ]] && missing+=("--rabbitpass")
        
        if [[ ${#missing[@]} -gt 0 ]]; then
            log_error "Missing required credentials for '$action': ${missing[*]}"
            log_info "Usage: $SCRIPT_NAME $action --dbname <user> --dbpass <pass> --rabbituser <user> --rabbitpass <pass>"
            return 1
        fi
    fi
}

# The main installation command
cmd_install() {
    # Check if any credential flag is provided. If not, use interactive mode.
    if [[ -z "$1" && -z "$2" && -z "$3" && -z "$4" ]]; then
        prompt_for_credentials
    else
        # This part handles credentials passed via flags
        export db_user="$1" db_pass="$2" rabbit_user="$3" rabbit_pass="$4"
    fi
    local skip_docker="$5" skip_firewall="$6"

    check_system || return 1
    check_internet || return 1
    
    log_info "Updating package lists..."
    if command_exists apt-get; then sudo apt-get update -qq; fi
    
    setup_docker "$skip_docker" || return 1
    [[ "$skip_firewall" == "false" ]] && { setup_firewall || log_warning "Firewall setup failed"; }
    
    download_files || return 1
    
    # Use provided credentials or generate new ones if they are still empty
    local final_db_user=${db_user:-"user_$(generate_secret 8 | tr '[:upper:]' '[:lower:]')"}
    local final_db_pass=${db_pass:-$(generate_secret 20)}
    local final_rabbit_user=${rabbit_user:-"rabbit_$(generate_secret 8 | tr '[:upper:]' '[:lower:]')"}
    local final_rabbit_pass=${rabbit_pass:-$(generate_secret 20)}
    
    local prod_config; prod_config=$(create_production_config "$final_db_user" "$final_db_pass" "$final_rabbit_user" "$final_rabbit_pass")
    [[ -n "$prod_config" ]] || { log_error "Failed to create production config"; return 1; }
    
    prompt_edit "$prod_config" "production docker-compose configuration"
    prompt_edit "$PROJECT_FOLDER/$NGINX_FILE" "nginx configuration"
    
    start_and_cleanup_containers "$prod_config" || return 1
    create_superuser
    
    echo; echo -e "${GREEN}========================================\n🎉 Installation completed successfully!\n========================================${NC}"; echo
    log_info "🔒 Your credentials (SAVE THESE!):"
    log_success "  Database Username: $final_db_user"
    log_success "  Database Password: $final_db_pass"
    log_success "  RabbitMQ Username: $final_rabbit_user"
    log_success "  RabbitMQ Password: $final_rabbit_pass"
    echo; [[ -z "$db_user" && -z "$1" ]] && log_warning "Credentials were auto-generated. Save them securely!"
    echo; log_info "🌐 Access your API at: http://$(get_public_ip)"
    log_info "📊 View logs: docker compose -f $PROJECT_FOLDER/$SOURCE_FILE logs -f"
    log_info "🛑 Stop services: docker compose -f $PROJECT_FOLDER/$SOURCE_FILE down"
}

# The restart command
cmd_restart() {
    local db_user="$1" db_pass="$2" rabbit_user="$3" rabbit_pass="$4"
    validate_credentials "restart" "$db_user" "$db_pass" "$rabbit_user" "$rabbit_pass" || return 1
    manage_containers "restart" "$db_user" "$db_pass" "$rabbit_user" "$rabbit_pass"
    log_success "🎉 Services restarted successfully!"
}

# The update command
cmd_update() {
    local db_user="$1" db_pass="$2" rabbit_user="$3" rabbit_pass="$4"
    validate_credentials "update" "$db_user" "$db_pass" "$rabbit_user" "$rabbit_pass" || return 1
    manage_containers "update" "$db_user" "$db_pass" "$rabbit_user" "$rabbit_pass"
    log_success "🎉 Services updated successfully!"
}

# ==============================================================================
# === HELP, VERSION & MAIN EXECUTION
# ==============================================================================

# Display the help message
show_help() {
    cat << EOF
${SCRIPT_NAME} v${SCRIPT_VERSION} - NatiqQuran API Setup & Management

USAGE:
    $SCRIPT_NAME [COMMAND] [OPTIONS]

COMMANDS:
    install    (Default) Run full installation and setup (default)
    restart    Restart all services. Requires all credential flags.
    update     Pull the latest images and restart. Requires all credential flags.

OPTIONS FOR (install):
    --no-install        (Optional) Skip Docker installation
    --no-firewall       (Optional) Skip firewall setup
    --dbname <user>     (Optional) Custom database username
    --dbpass <pass>     (Optional) Custom database password
    --rabbituser <user> (Optional) Custom RabbitMQ username
    --rabbitpass <pass> (Optional) Custom RabbitMQ password

OPTIONS FOR (restart AND update):
    --dbname <user>     (required) Database username 
    --dbpass <pass>     (required) Database password
    --rabbituser <user> (required) RabbitMQ username
    --rabbitpass <pass> (required) RabbitMQ password

GLOBAL OPTIONS:
    --help, -h         Show this help message.
    --version, -v      Show version
    --debug            Enable debug output

EXAMPLES:
    bash ${SCRIPT_NAME} install
    bash ${SCRIPT_NAME} install --dbname myuser --dbpass mysecret
    bash ${SCRIPT_NAME} restart --dbname myuser --dbpass mysecret --rabbituser ruser --rabbitpass rpass
    bash ${SCRIPT_NAME} update --dbname myuser --dbpass mysecret --rabbituser ruser --rabbitpass rpass
EOF
}

# Display the script version
show_version() {
    echo "$SCRIPT_NAME version $SCRIPT_VERSION"
}

# Cleanup function for traps
cleanup() {
    log_debug "Performing cleanup..."
    if [[ -n "${PROJECT_FOLDER:-}" ]] && [[ -d "$PROJECT_FOLDER" ]]; then
        rm -f "$PROJECT_FOLDER/$PROD_FILE"
        log_debug "Cleaned up production config files"
    fi
}

# Error handler for traps
error_handler() {
    log_error "Error occurred at line $1"; cleanup; exit 1;
}

# Set traps for clean exit on error or script end
trap 'error_handler ${LINENO}' ERR
trap cleanup EXIT

# Main function to parse arguments and execute commands
main() {
    # Default command is 'install'
    local command="install"
    if [[ $# -gt 0 && ! "$1" =~ ^-- ]]; then
        command="$1"
        shift
    fi
    
    # Initialize option variables
    local skip_docker="false"
    local skip_firewall="false"
    local db_user=""
    local db_pass=""
    local rabbit_user=""
    local rabbit_pass=""
    
    # Parse all options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-install) skip_docker="true"; shift ;;
            --no-firewall) skip_firewall="true"; shift ;;
            --dbname) db_user="$2"; shift 2 ;;
            --dbpass) db_pass="$2"; shift 2 ;;
            --rabbituser) rabbit_user="$2"; shift 2 ;;
            --rabbitpass) rabbit_pass="$2"; shift 2 ;;
            --debug) export DEBUG=1; shift ;;
            --help|-h) show_help; exit 0 ;;
            --version|-v) show_version; exit 0 ;;
            *) log_error "Unknown option: $1"; show_help; exit 1 ;;
        esac
    done
    
    # Display header
    echo
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE} NatiqQuran API Setup Script v${SCRIPT_VERSION}${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo
    
    # Execute the chosen command
    case "$command" in
        install)
            cmd_install "$db_user" "$db_pass" "$rabbit_user" "$rabbit_pass" "$skip_docker" "$skip_firewall"
            ;;
        restart)
            cmd_restart "$db_user" "$db_pass" "$rabbit_user" "$rabbit_pass"
            ;;
        update)
            cmd_update "$db_user" "$db_pass" "$rabbit_user" "$rabbit_pass"
            ;;
        *)
            log_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Run the main function with all provided arguments
main "$@"
