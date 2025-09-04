#!/usr/bin/env bash

# NatiqQuran API Setup Script
# Description: A script to set up and run the NatiqQuran API project using Docker.
# It handles Docker installation, project folder setup, and initial configuration.
# Features: Complete lifecycle management, user-friendly, enhanced security, comprehensive logging
# Version: 2.5
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
readonly SCRIPT_VERSION="2.5"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Project Configuration ---
readonly PROJECT_FOLDER="quran-api"
readonly SOURCE_FILE="docker-compose.source.yaml"
readonly PROD_FILE="docker-compose.prod.yaml"
readonly NGINX_FILE="nginx.conf"
readonly COMPOSE_URL="https://raw.githubusercontent.com/NatiqQuran/quran-api/main/docker-compose.yaml"
readonly NGINX_URL="https://raw.githubusercontent.com/NatiqQuran/quran-api/main/nginx.conf"
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
    local secret=""

    if command_exists openssl; then
        secret=$(openssl rand -base64 48 | tr -d "=+/\n" | cut -c1-$len)
    else
        secret=$(head /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c $len)
    fi

    # Ensure we have a secret, fallback to a simple method
    if [[ -z "$secret" ]]; then
        secret=$(date +%s%N | sha256sum | head -c $len)
    fi

    echo "$secret"
}

# Create .env file with random generated values
create_env_file() {
    local env_file="$PROJECT_FOLDER/.env"
    
    log_info "Creating .env file with random generated values..."
    
    # Generate random values
    local postgres_user="user_$(generate_secret 8 | tr '[:upper:]' '[:lower:]')"
    local postgres_password=$(generate_secret 20)
    local database_username="$postgres_user"  # Same as POSTGRES_USER
    local database_password="$postgres_password"  # Same as POSTGRES_PASSWORD
    local rabbit_user="rabbit_$(generate_secret 8 | tr '[:upper:]' '[:lower:]')"
    local rabbitmq_pass=$(generate_secret 20)
    local celery_broker_url="amqp://${rabbit_user}:${rabbitmq_pass}@rabbitmq:5672//"
    local secret_key=$(generate_secret 50)
    local django_allowed_hosts="$(get_public_ip)"
    local debug="0"
    local forced_alignment_secret_key=$(generate_secret 50)
    
    # Create .env file content
    cat > "$env_file" << EOF
# NatiqQuran API Environment Configuration
# Generated automatically - You CAN edit these values if needed
# This file will be deleted after configuration is applied
# 
# IMPORTANT: Any changes you make to this file will be used in the final configuration
# Make sure to save your credentials securely as they cannot be recovered later

POSTGRES_USER=$postgres_user
POSTGRES_PASSWORD=$postgres_password
DATABASE_USERNAME=$database_username
DATABASE_PASSWORD=$database_password
RABBIT_USER=$rabbit_user
RABBITMQ_PASS=$rabbitmq_pass
CELERY_BROKER_URL=$celery_broker_url
SECRET_KEY=$secret_key
DJANGO_ALLOWED_HOSTS=$django_allowed_hosts
DEBUG=$debug
FORCED_ALIGNMENT_SECRET_KEY=$forced_alignment_secret_key

# Edit these values according to your AWS/S3-compatible storage configuration
AWS_ACCESS_KEY_ID=example123
AWS_SECRET_ACCESS_KEY=secretExample
AWS_S3_ENDPOINT_URL=https://example.com

# Maximum allowed size for client request body (file uploads)
NGINX_CLIENT_MAX_BODY_SIZE=10M

# Django Superuser Configuration
# These credentials will be used to create the admin user automatically
DJANGO_SUPERUSER_USERNAME=admin_$(generate_secret 8 | tr '[:upper:]' '[:lower:]')
DJANGO_SUPERUSER_PASSWORD=$(generate_secret 20)
DJANGO_SUPERUSER_EMAIL=example@gmail.com
EOF

    # Set proper permissions (readable by owner only)
    chmod 600 "$env_file" 2>/dev/null || log_warning "Could not set permissions on .env file"
    
    log_success ".env file created successfully at: $env_file"
    
    # Return the path to the .env file
    printf "%s" "$env_file"
}

# Read values from .env file
read_env_values() {
    local env_file="$1"
    
    [[ -f "$env_file" ]] || { log_error ".env file not found: $env_file"; return 1; }
    
    log_debug "Reading values from .env file: $env_file"
    
    # Source the .env file to get variables
    set -a  # automatically export all variables
    source "$env_file"
    set +a  # turn off automatic export
    
    # Return values as a pipe-separated string: db_user|db_pass|rabbit_user|rabbit_pass|secret_key|allowed_hosts|debug|forced_alignment_secret_key|aws_key|aws_secret|aws_endpoint|nginx_max_body|superuser_username|superuser_password|superuser_email
    printf "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s" "$POSTGRES_USER" "$POSTGRES_PASSWORD" "$RABBIT_USER" "$RABBITMQ_PASS" "$SECRET_KEY" "$DJANGO_ALLOWED_HOSTS" "$DEBUG" "$FORCED_ALIGNMENT_SECRET_KEY" "$AWS_ACCESS_KEY_ID" "$AWS_SECRET_ACCESS_KEY" "$AWS_S3_ENDPOINT_URL" "$NGINX_CLIENT_MAX_BODY_SIZE" "$DJANGO_SUPERUSER_USERNAME" "$DJANGO_SUPERUSER_PASSWORD" "$DJANGO_SUPERUSER_EMAIL"
}

# Securely delete .env file to prevent recovery
secure_cleanup_env() {
    local env_file="$1"
    
    [[ -f "$env_file" ]] || { log_debug ".env file already cleaned up or doesn't exist"; return 0; }
    
    log_debug "Securely cleaning up .env file: $env_file"
    
    # Overwrite file content with random data before deletion
    if command_exists shred; then
        shred -u -z -n 3 "$env_file" 2>/dev/null || {
            # Fallback if shred fails
            dd if=/dev/urandom of="$env_file" bs=1M count=1 2>/dev/null || true
            rm -f "$env_file"
        }
    else
        # Fallback method: overwrite with random data then delete
        dd if=/dev/urandom of="$env_file" bs=1M count=1 2>/dev/null || true
        rm -f "$env_file"
    fi
    
    log_debug ".env file securely cleaned up"
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
    
    log_info "Downloading configuration files from GitHub..."
    curl -fsSL "$COMPOSE_URL" -o "$PROJECT_FOLDER/$SOURCE_FILE" || { log_error "Failed to download compose file"; return 1; }
    curl -fsSL "$NGINX_URL" -o "$PROJECT_FOLDER/$NGINX_FILE" || { log_error "Failed to download nginx config"; return 1; }
    
    [[ -s "$PROJECT_FOLDER/$SOURCE_FILE" ]] || { log_error "Downloaded compose file is empty"; return 1; }
    [[ -s "$PROJECT_FOLDER/$NGINX_FILE" ]] || { log_error "Downloaded nginx config is empty"; return 1; }
    
    log_success "Configuration files downloaded from GitHub"
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

# Process nginx.conf file to add/update client_max_body_size
process_nginx_config() {
    local nginx_file="$1"
    local max_body_size="$2"
    
    [[ -f "$nginx_file" ]] || { log_error "Nginx config file not found: $nginx_file"; return 1; }
    
    log_debug "Processing nginx config: $nginx_file with max body size: $max_body_size"
    
    # First, remove any existing client_max_body_size lines
    sed -i '/client_max_body_size/d' "$nginx_file"
    
    # Then add client_max_body_size after include mime.types;
    sed -i "/include mime.types;/a\    client_max_body_size ${max_body_size};" "$nginx_file"
    
    log_success "Added client_max_body_size ${max_body_size} after include mime.types;"
}

# Create a temporary, production-ready compose file by injecting secrets from .env
create_production_config() {
    local env_file="$1"
    
    local source="$PROJECT_FOLDER/$SOURCE_FILE"
    local temp_file="$PROJECT_FOLDER/$PROD_FILE"
    
    [[ -f "$source" ]] || { log_error "Source file not found: $source"; return 1; }
    [[ -f "$env_file" ]] || { log_error ".env file not found: $env_file"; return 1; }
    
    log_debug "Creating production configuration from source using .env values..."
    
    # Read values from .env file
    local env_values; env_values=$(read_env_values "$env_file")
    [[ -n "$env_values" ]] || { log_error "Failed to read .env values"; return 1; }
    
    # Parse the returned values using pipe delimiter
    local db_user db_pass rabbit_user rabbit_pass secret_key allowed_hosts debug_value forced_alignment_secret_key aws_key aws_secret aws_endpoint nginx_max_body superuser_username superuser_password superuser_email
    IFS='|' read -r db_user db_pass rabbit_user rabbit_pass secret_key allowed_hosts debug_value forced_alignment_secret_key aws_key aws_secret aws_endpoint nginx_max_body superuser_username superuser_password superuser_email <<< "$env_values"
    
    # Debug: check parsed values
    log_debug "Parsed values from .env:"
    log_debug "  db_user: '$db_user'"
    log_debug "  db_pass: '$db_pass'"
    log_debug "  rabbit_user: '$rabbit_user'"
    log_debug "  rabbit_pass: '$rabbit_pass'"
    log_debug "  secret_key: '$secret_key'"
    log_debug "  allowed_hosts: '$allowed_hosts'"
    log_debug "  debug_value: '$debug_value'"
    log_debug "  forced_alignment_secret_key: '$forced_alignment_secret_key'"
    log_debug "  aws_key: '$aws_key'"
    log_debug "  aws_secret: '$aws_secret'"
    log_debug "  aws_endpoint: '$aws_endpoint'"
    log_debug "  nginx_max_body: '$nginx_max_body'"
    log_debug "  superuser_username: '$superuser_username'"
    log_debug "  superuser_email: '$superuser_email'"
    
    # Create the production config by replacing placeholders in the source file
    local temp_content=""
    
    # Track if we're in the natiq-api environment section and if we've added AWS vars
    local in_natiq_env=false
    local aws_vars_added=false
    local natiq_indent=""
    
    while IFS= read -r line; do
        case "$line" in
            *"natiq-api:"*)
                # We're entering the natiq-api service section
                in_natiq_env=false
                aws_vars_added=false
                temp_content+="$line"$'\n'
                ;;
            *"environment:"*)
                # Check if this is the environment section for natiq-api
                if [[ "$temp_content" == *"natiq-api:"* ]]; then
                    in_natiq_env=true
                    # Get the indentation level for environment section
                    natiq_indent="${line%%[^[:space:]]*}"
                fi
                temp_content+="$line"$'\n'
                ;;
            *"POSTGRES_USER:"*)
                # Preserve indentation and replace value
                local indent="${line%%[^[:space:]]*}"
                temp_content+="${indent}POSTGRES_USER: ${db_user}"$'\n'
                ;;
            *"POSTGRES_PASSWORD:"*)
                local indent="${line%%[^[:space:]]*}"
                temp_content+="${indent}POSTGRES_PASSWORD: ${db_pass}"$'\n'
                ;;
            *"DATABASE_USERNAME:"*)
                local indent="${line%%[^[:space:]]*}"
                temp_content+="${indent}DATABASE_USERNAME: ${db_user}"$'\n'
                ;;
            *"DATABASE_PASSWORD:"*)
                local indent="${line%%[^[:space:]]*}"
                temp_content+="${indent}DATABASE_PASSWORD: ${db_pass}"$'\n'
                ;;
            *"RABBITMQ_DEFAULT_USER:"*)
                local indent="${line%%[^[:space:]]*}"
                temp_content+="${indent}RABBITMQ_DEFAULT_USER: ${rabbit_user}"$'\n'
                ;;
            *"RABBITMQ_DEFAULT_PASS:"*)
                local indent="${line%%[^[:space:]]*}"
                temp_content+="${indent}RABBITMQ_DEFAULT_PASS: ${rabbit_pass}"$'\n'
                ;;
            *"CELERY_BROKER_URL:"*)
                local indent="${line%%[^[:space:]]*}"
                temp_content+="${indent}CELERY_BROKER_URL: amqp://${rabbit_user}:${rabbit_pass}@rabbitmq:5672//"$'\n'
                ;;
            *"FORCED_ALIGNMENT_SECRET_KEY:"*)
                local indent="${line%%[^[:space:]]*}"
                temp_content+="${indent}FORCED_ALIGNMENT_SECRET_KEY: ${forced_alignment_secret_key}"$'\n'
                ;;
            *"SECRET_KEY:"*)
                local indent="${line%%[^[:space:]]*}"
                temp_content+="${indent}SECRET_KEY: ${secret_key}"$'\n'
                ;;
            *"DJANGO_ALLOWED_HOSTS:"*)
                local indent="${line%%[^[:space:]]*}"
                temp_content+="${indent}DJANGO_ALLOWED_HOSTS: ${allowed_hosts}"$'\n'
                ;;
            *"DEBUG:"*)
                local indent="${line%%[^[:space:]]*}"
                temp_content+="${indent}DEBUG: ${debug_value}"$'\n'
                ;;

            *)
                temp_content+="$line"$'\n'
                ;;
        esac
        
        # After processing each line, check if we should add AWS variables
        if [[ "$in_natiq_env" == "true" && "$aws_vars_added" == "false" ]]; then
            # Look for the end of environment section or next service
            if [[ "$line" =~ ^[[:space:]]*[a-zA-Z] ]] && [[ "$line" != *":"* ]] && [[ "$line" != *"-"* ]]; then
                # We've reached the end of environment section, add AWS vars before this line
                temp_content+="${natiq_indent}  AWS_ACCESS_KEY_ID: ${aws_key}"$'\n'
                temp_content+="${natiq_indent}  AWS_SECRET_ACCESS_KEY: ${aws_secret}"$'\n'
                temp_content+="${natiq_indent}  AWS_S3_ENDPOINT_URL: ${aws_endpoint}"$'\n'
                aws_vars_added=true
                in_natiq_env=false
            elif [[ "$line" =~ ^[[:space:]]*[a-zA-Z].*: ]] && [[ "$line" != *"environment:"* ]]; then
                # We've reached another section, add AWS vars before this line
                temp_content+="${natiq_indent}  AWS_ACCESS_KEY_ID: ${aws_key}"$'\n'
                temp_content+="${natiq_indent}  AWS_SECRET_ACCESS_KEY: ${aws_secret}"$'\n'
                temp_content+="${natiq_indent}  AWS_S3_ENDPOINT_URL: ${aws_endpoint}"$'\n'
                aws_vars_added=true
                in_natiq_env=false
            fi
        fi
    done < "$source"
    
    # If we're still in natiq-api environment section at the end, add AWS vars
    if [[ "$in_natiq_env" == "true" && "$aws_vars_added" == "false" ]]; then
        temp_content+="${natiq_indent}  AWS_ACCESS_KEY_ID: ${aws_key}"$'\n'
        temp_content+="${natiq_indent}  AWS_SECRET_ACCESS_KEY: ${aws_secret}"$'\n'
        temp_content+="${natiq_indent}  AWS_S3_ENDPOINT_URL: ${aws_endpoint}"$'\n'
    fi
    
    # Write to file without control characters
    printf '%s' "$temp_content" > "$temp_file"

    [[ -s "$temp_file" ]] || { log_error "Production configuration file is empty or not created"; return 1; }

    # Set proper permissions for the production config file (readable by owner only)
    chmod 600 "$temp_file" 2>/dev/null || log_warning "Could not set permissions on production config file"
    
    log_debug "Production config created at: $temp_file"
    log_debug "Generated credentials - DB: $db_user, RabbitMQ: $rabbit_user, Secret Key Length: ${#secret_key}"
    log_debug "AWS credentials - Key: $aws_key, Endpoint: $aws_endpoint"
    log_debug "Nginx max body size: $nginx_max_body"
    log_debug "Django superuser - Username: $superuser_username, Email: $superuser_email"
    log_info "Production configuration file created successfully"
    printf "%s" "$temp_file"
}

# ==============================================================================
# === CONTAINER OPERATIONS
# ==============================================================================

# Start containers using the production config and clean up afterwards
start_and_cleanup_containers() {
    local prod_config="$1"
    local env_file="$2"
    
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
        log_debug "Cleaning up production config file: $prod_config"
        rm -f "$prod_config"
        
        return 1
    fi
}

# Cleanup .env file after restart/update operations with user confirmation
cleanup_env_after_operation() {
    local env_file="$1"
    local operation="$2"  # "restart" or "update"
    
    # Only cleanup if file was created during this operation
    if [[ ! -f "$env_file" ]]; then
        log_debug ".env file already cleaned up or doesn't exist"
        return 0
    fi
    
    log_warning "Security notice: The .env file contains sensitive information (passwords, secret keys, etc.)"
    log_info "This file was created during the $operation operation for configuration purposes."
    log_info "For security reasons, we recommend removing it after use."
    
    # Ask user if they want to keep the file
    local response
    read -p "Do you want to keep the .env file? (y/N): " -t 30 response
    
    # Default to 'N' if no response or timeout (more secure default)
    response="${response:-N}"
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        log_info "Keeping .env file as requested: $env_file"
        log_warning "⚠️  Remember: This file contains sensitive information. Keep it secure!"
        return 0
    else
        log_info "Securely removing .env file..."
        secure_cleanup_env "$env_file"
        log_success ".env file securely removed"
        return 0
    fi
}

# Create .env file interactively if missing (for restart/update commands)
create_env_file_interactive() {
    local env_file="$1"
    
    # Check if .env file exists
    if [[ -f "$env_file" ]]; then
        log_debug ".env file already exists: $env_file"
        return 0
    fi
    
    log_warning ".env file not found: $env_file"
    log_info "This file is required for restart/update operations."
    log_info "It contains database credentials, secret keys, and other configuration values."
    
    # Ask user if they want to create a new .env file
    local response
    read -p "Do you want to create a new .env file with sample values? (Y/n): " -t 30 response
    
    # Default to 'Y' if no response or timeout
    response="${response:-Y}"
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        log_info "Creating new .env file with sample values..."
        
        # Create .env file with sample values
        create_env_file "$env_file"
        
        if [[ -f "$env_file" ]]; then
            log_success ".env file created successfully"
            
            # Ask user if they want to edit the file
            read -p "Do you want to edit the .env file now? (Y/n): " -t 30 response
            response="${response:-Y}"
            
            if [[ "$response" =~ ^[Yy]$ ]]; then
                log_info "Opening .env file for editing..."
                
                # Try to find a suitable editor
                local editor=""
                for ed in nano vim vi; do
                    if command_exists "$ed"; then
                        editor="$ed"
                        break
                    fi
                done
                
                if [[ -n "$editor" ]]; then
                    log_info "Opening with $editor..."
                    if "$editor" "$env_file"; then
                        log_success "File editing completed"
                    else
                        log_warning "File editing was cancelled or failed"
                    fi
                else
                    log_warning "No suitable editor found (nano/vim/vi)"
                    log_info "You can manually edit the file later: $env_file"
                fi
            else
                log_info "Skipping file editing. You can edit manually later: $env_file"
            fi
            
            # Mark that we created a new file (for cleanup later)
            echo "true" > "/tmp/env_created_$$"
            
            return 0
        else
            log_error "Failed to create .env file"
            return 1
        fi
    else
        log_error "Operation cancelled by user"
        return 1
    fi
}

# A wrapper for restart/update commands
manage_containers() {
    local action="$1"
    local env_file="$2"
    
    local source_file="$PROJECT_FOLDER/$SOURCE_FILE"
    [[ -f "$source_file" ]] || { log_error "Project not found. Run 'install' first."; return 1; }
    [[ -f "$env_file" ]] || { log_error ".env file not found. Run 'install' first."; return 1; }
    
    log_info "Stopping all services..."
    docker compose -f "$source_file" down --remove-orphans 2>/dev/null || log_warning "Some containers may not have stopped cleanly."
    
    if [[ "$action" == "update" ]]; then
        log_info "Pulling latest images..."
        docker compose -f "$source_file" pull
    fi
    
    log_info "Creating new production configuration..."
    local prod_config; prod_config=$(create_production_config "$env_file")
    [[ -n "$prod_config" ]] || { log_error "Failed to get production config path"; return 1; }
    
    # Process nginx config for restart/update commands
    if [[ -f "$env_file" ]]; then
        local nginx_max_body; nginx_max_body=$(grep "^NGINX_CLIENT_MAX_BODY_SIZE=" "$env_file" | cut -d'=' -f2)
        if [[ -n "$nginx_max_body" ]]; then
            log_info "Processing nginx configuration..."
            if process_nginx_config "$PROJECT_FOLDER/$NGINX_FILE" "$nginx_max_body"; then
                log_success "Nginx configuration updated with max body size: $nginx_max_body"
            else
                log_warning "Failed to update nginx configuration"
            fi
        else
            log_warning "NGINX_CLIENT_MAX_BODY_SIZE not found in .env file, using default"
            nginx_max_body="10M"
            if process_nginx_config "$PROJECT_FOLDER/$NGINX_FILE" "$nginx_max_body"; then
                log_success "Nginx configuration updated with default max body size: $nginx_max_body"
            else
                log_warning "Failed to update nginx configuration with default value"
            fi
        fi
    else
        log_warning ".env file not found, skipping nginx configuration update"
    fi
    
    start_and_cleanup_containers "$prod_config" "$env_file"
}

# Wait for services to be ready before creating superuser
wait_for_services() {
    log_info "Waiting for services to be ready..."
    
    # Wait for database to be ready
    log_info "Waiting for database to be ready..."
    local db_ready=false
    local max_attempts=30
    local attempt=1
    
    while [[ "$db_ready" == "false" && $attempt -le $max_attempts ]]; do
        if docker compose -f "$PROJECT_FOLDER/$SOURCE_FILE" exec -T postgres-db pg_isready -U postgres >/dev/null 2>&1; then
            db_ready=true
            log_success "Database is ready"
        else
            log_info "Database not ready yet (attempt $attempt/$max_attempts), waiting 5s..."
            sleep 5
            ((attempt++))
        fi
    done
    
    if [[ "$db_ready" == "false" ]]; then
        log_error "Database failed to become ready after $max_attempts attempts"
        return 1
    fi
    
    # Wait for Django container to be ready
    log_info "Waiting for Django container to be ready..."
    local django_ready=false
    attempt=1
    
    while [[ "$django_ready" == "false" && $attempt -le $max_attempts ]]; do
        if docker compose -f "$PROJECT_FOLDER/$SOURCE_FILE" exec -T natiq-api python3 -c "import django; print('Django ready')" >/dev/null 2>&1; then
            django_ready=true
            log_success "Django container is ready"
        else
            log_info "Django container not ready yet (attempt $attempt/$max_attempts), waiting 5s..."
            sleep 5
            ((attempt++))
        fi
    done
    
    if [[ "$django_ready" == "false" ]]; then
        log_error "Django container failed to become ready after $max_attempts attempts"
        return 1
    fi
    
    # Run migrations
    log_info "Running database migrations..."
    if docker compose -f "$PROJECT_FOLDER/$SOURCE_FILE" exec -T natiq-api python3 manage.py migrate --noinput; then
        log_success "Database migrations completed successfully"
    else
        log_error "Database migrations failed"
        return 1
    fi
    
    log_success "All services are ready"
}

# Create a Django superuser automatically using .env values
create_superuser() {
    local env_file="$1"
    
    log_info "Creating Django superuser automatically..."
    
    # Check if .env file exists
    if [[ ! -f "$env_file" ]]; then
        log_error ".env file not found: $env_file"
        log_warning "Cannot create superuser without .env file"
        return 1
    fi
    
    # Read superuser credentials from .env file
    local superuser_username; superuser_username=$(grep "^DJANGO_SUPERUSER_USERNAME=" "$env_file" | cut -d'=' -f2)
    local superuser_password; superuser_password=$(grep "^DJANGO_SUPERUSER_PASSWORD=" "$env_file" | cut -d'=' -f2)
    local superuser_email; superuser_email=$(grep "^DJANGO_SUPERUSER_EMAIL=" "$env_file" | cut -d'=' -f2)
    
    if [[ -z "$superuser_username" || -z "$superuser_password" || -z "$superuser_email" ]]; then
        log_error "Superuser credentials not found in .env file"
        log_warning "Make sure DJANGO_SUPERUSER_USERNAME, DJANGO_SUPERUSER_PASSWORD, and DJANGO_SUPERUSER_EMAIL are set in .env"
        return 1
    fi
        
    # Use docker compose exec to create superuser
    local compose_file="$PROJECT_FOLDER/$SOURCE_FILE"
    if docker compose -f "$compose_file" exec -T natiq-api python3 manage.py shell -c "
from django.contrib.auth import get_user_model;
User = get_user_model();
if not User.objects.filter(username='$superuser_username').exists():
    User.objects.create_superuser('$superuser_username', '$superuser_email', '$superuser_password');
    print('Superuser created successfully');
else:
    print('Superuser already exists');
"; then
        log_success "Superuser creation completed successfully."
    else
        log_warning "Superuser creation failed or was cancelled."
        log_info "You can create one manually later with: docker compose -f $compose_file exec natiq-api python3 manage.py createsuperuser"
    fi
}

# ==============================================================================
# === MAIN COMMANDS & VALIDATION
# ==============================================================================

# The main installation command
cmd_install() {
    local skip_docker="$1" skip_firewall="$2"

    check_system || return 1
    check_internet || return 1
    
    log_info "Updating package lists..."
    if command_exists apt-get; then sudo apt-get update -qq; fi
    
    setup_docker "$skip_docker" || return 1
    [[ "$skip_firewall" == "false" ]] && { setup_firewall || log_warning "Firewall setup failed"; }
    
    download_files || return 1
    
    # Create .env file with random generated values
    local env_file; env_file=$(create_env_file)
    [[ -n "$env_file" ]] || { log_error "Failed to create .env file"; return 1; }
    
    # Prompt user to edit .env file if desired
    echo
    log_info "🔐 I have created a .env file with randomly generated secure values."
    log_info "📝 You can now choose to edit these values or use them as-is."
    log_info "💡 The .env file contains all the credentials and configuration needed for your API."
    log_info "☁️  AWS/S3 configuration is included for cloud storage access."
    log_info "🌐 Nginx configuration includes customizable max body size for file uploads."
    log_info "👤 Django superuser will be created automatically with credentials from .env"
    echo
    log_warning "  Important Notes:"
    log_warning "   • Any changes you make will be used in the final configuration"
    log_warning "   • This file will be securely deleted after deployment"
    log_warning "   • Make sure to save your credentials securely - they cannot be recovered!"
    echo
    
    read -p "Do you want to edit the .env file? (y/N): " -t "$TIMEOUT" edit_env || edit_env="n"
    
    if [[ "${edit_env,,}" =~ ^y ]]; then
        log_info "🖊️  Opening .env file for editing..."
        log_info "💡 You can modify any of the generated values as needed."
        log_info "💾 Remember to save the file when you're done editing."
        echo
        
        for editor in nano vim vi; do
            if command_exists "$editor"; then
                log_info "📂 Opening with $editor..."
                "$editor" "$env_file"
                log_success "✅ Edit completed successfully"
                log_info "🔄 Your custom values will now be used in the configuration"
                break
            fi
        done
    else
        log_info "✅ Using generated values as-is."
        log_info "🔒 The randomly generated secure credentials will be applied."
    fi
    
    local prod_config; prod_config=$(create_production_config "$env_file")
    [[ -n "$prod_config" ]] || { log_error "Failed to create production config"; return 1; }
    
    prompt_edit "$prod_config" "production docker-compose configuration"
    
    # Process nginx.conf to add/update client_max_body_size
    log_info "Processing nginx configuration..."
    local nginx_max_body; nginx_max_body=$(grep "^NGINX_CLIENT_MAX_BODY_SIZE=" "$env_file" | cut -d'=' -f2)
    if [[ -n "$nginx_max_body" ]]; then
        if process_nginx_config "$PROJECT_FOLDER/$NGINX_FILE" "$nginx_max_body"; then
            log_success "Nginx configuration updated with max body size: $nginx_max_body"
        else
            log_warning "Failed to update nginx configuration"
        fi
    else
        log_warning "NGINX_CLIENT_MAX_BODY_SIZE not found in .env file, using default"
        nginx_max_body="10M"
        if process_nginx_config "$PROJECT_FOLDER/$NGINX_FILE" "$nginx_max_body"; then
            log_success "Nginx configuration updated with default max body size: $nginx_max_body"
        else
            log_warning "Failed to update nginx configuration with default value"
        fi
    fi
    
    prompt_edit "$PROJECT_FOLDER/$NGINX_FILE" "nginx configuration"
    
    # Start containers first
    start_and_cleanup_containers "$prod_config" "$env_file" || return 1
    
    # Wait for services to be ready before creating superuser
    wait_for_services || { log_error "Services failed to become ready"; return 1; }
    
    # Create superuser after services are ready
    create_superuser "$env_file"
    
    # Clean up .env file after superuser creation
    log_info "Cleaning up .env file..."
    secure_cleanup_env "$env_file"
    
    echo; echo -e "${GREEN}========================================\n🎉 Installation completed successfully!\n========================================${NC}"; echo
    log_info "🔐 Configuration Summary:"
    log_info "   • All credentials and settings have been applied from .env file"
    log_info "   • AWS/S3 configuration has been configured for cloud storage"
    log_info "   • Nginx max body size has been set to: $nginx_max_body"
    log_info "   • Django superuser has been created automatically"
    log_info "   • The .env file has been securely deleted for security"
    log_info "   • Your API is now configured and ready to use"
    echo
    log_warning "  Security Reminder:"
    log_warning "   • Make sure to save your credentials securely"
    log_warning "   • The .env file cannot be recovered"
    log_warning "   • Keep your credentials in a safe place"
    
    echo; log_info "🌐 Access your API at: http://$(get_public_ip)"
    log_info "📊 View logs: docker compose -f $PROJECT_FOLDER/$SOURCE_FILE logs -f"
    log_info "🛑 Stop services: docker compose -f $PROJECT_FOLDER/$SOURCE_FILE down"
}

# The restart command
cmd_restart() {
    local env_file="$PROJECT_FOLDER/.env"
    local env_was_created=false
    
    # Check if .env file exists, create interactively if missing
    if [[ ! -f "$env_file" ]]; then
        create_env_file_interactive "$env_file" || return 1
        env_was_created=true
    fi
    
    manage_containers "restart" "$env_file"
    log_success "🎉 Services restarted successfully!"
    
    # Cleanup .env file if it was created during this operation
    if [[ "$env_was_created" == "true" ]]; then
        cleanup_env_after_operation "$env_file" "restart"
    fi
}

# The update command
cmd_update() {
    local env_file="$PROJECT_FOLDER/.env"
    local env_was_created=false
    
    # Check if .env file exists, create interactively if missing
    if [[ ! -f "$env_file" ]]; then
        create_env_file_interactive "$env_file" || return 1
        env_was_created=true
    fi
    
    manage_containers "update" "$env_file"
    log_success "🎉 Services updated successfully!"
    
    # Cleanup .env file if it was created during this operation
    if [[ "$env_was_created" == "true" ]]; then
        cleanup_env_after_operation "$env_file" "update"
    fi
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
    restart    Restart all services (creates .env interactively if missing)
    update     Pull the latest images and restart (creates .env interactively if missing)

OPTIONS FOR (install):
    --no-install        (Optional) Skip Docker installation
    --no-firewall       (Optional) Skip firewall setup

FEATURES:
    🔐 Automatic Credential Generation: Creates .env file with random secure values
    ✏️  Interactive Editing: Option to edit generated values before deployment
    🗑️  Secure Cleanup: .env file is securely deleted after configuration

GLOBAL OPTIONS:
    --help, -h         Show this help message.
    --version, -v      Show version
    --debug            Enable debug output

EXAMPLES:
    bash ${SCRIPT_NAME} install
    bash ${SCRIPT_NAME} install --no-firewall
    bash ${SCRIPT_NAME} restart
    bash ${SCRIPT_NAME} update
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
        if [[ -f "$PROJECT_FOLDER/$PROD_FILE" ]]; then
            log_debug "Cleaning up production config file: $PROJECT_FOLDER/$PROD_FILE"
            rm -f "$PROJECT_FOLDER/$PROD_FILE"
            log_debug "Production config files cleaned up"
        else
            log_debug "Production config file already cleaned up or doesn't exist"
        fi
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
    
    # Parse all options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-install) skip_docker="true"; shift ;;
            --no-firewall) skip_firewall="true"; shift ;;
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
            cmd_install "$skip_docker" "$skip_firewall"
            ;;
        restart)
            cmd_restart
            ;;
        update)
            cmd_update
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