#!/bin/bash

# PartADay Database Proxy Deployment Script
# Uses doctl CLI to deploy and manage the App Platform application

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
APP_NAME="partaday-database-proxy"
GITHUB_REPO="" # Will be set interactively
APP_ID="" # Will be retrieved after creation

# Function to print colored output
print_status() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_header() {
    echo -e "${PURPLE}$1${NC}"
    echo "=================================="
}

# Function to check if doctl is installed and authenticated
check_doctl() {
    if ! command -v doctl &> /dev/null; then
        print_error "doctl CLI is not installed!"
        echo "Install it from: https://docs.digitalocean.com/reference/doctl/how-to/install/"
        exit 1
    fi

    # Check if authenticated
    if ! doctl account get > /dev/null 2>&1; then
        print_error "doctl is not authenticated!"
        echo "Run: doctl auth init"
        exit 1
    fi

    print_status "doctl CLI is installed and authenticated"
}

# Function to check if required files exist
check_files() {
    local required_files=(".do/app.yaml" "package.json" "src/app.ts")
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            print_error "Required file not found: $file"
            exit 1
        fi
    done
    
    print_status "All required files found"
}

# Function to load environment variables
load_env() {
    if [ -f ".env" ]; then
        set -a
        source .env
        set +a
        print_status "Loaded environment variables from .env"
    else
        print_warning "No .env file found - will need to set environment variables manually"
    fi
}

# Function to get GitHub repository URL
get_github_repo() {
    if [ -z "$GITHUB_REPO" ]; then
        # Try to get from git remote
        if git remote get-url origin &> /dev/null; then
            local git_url=$(git remote get-url origin)
            # Convert SSH to HTTPS format and extract repo path
            if [[ $git_url == git@github.com:* ]]; then
                GITHUB_REPO=$(echo $git_url | sed 's/git@github.com://' | sed 's/\.git$//')
            elif [[ $git_url == https://github.com/* ]]; then
                GITHUB_REPO=$(echo $git_url | sed 's/https:\/\/github\.com\///' | sed 's/\.git$//')
            fi
        fi
        
        if [ -z "$GITHUB_REPO" ]; then
            read -p "Enter your GitHub repository (username/repo-name): " GITHUB_REPO
        fi
    fi
    
    print_info "Using GitHub repository: $GITHUB_REPO"
}

# Function to create the app specification
create_app_spec() {
    local temp_spec="/tmp/app-spec.yaml"
    
    # Update the app.yaml with the correct GitHub repo
    sed "s|your-username/partaday-database-proxy|$GITHUB_REPO|g" .do/app.yaml > "$temp_spec"
    
    echo "$temp_spec"
}

# Function to create the app
create_app() {
    print_header "Creating App Platform Application"
    
    local app_spec=$(create_app_spec)
    
    print_info "Creating app with specification..."
    
    local create_output=$(doctl apps create --spec "$app_spec" --format json)
    APP_ID=$(echo "$create_output" | jq -r '.id')
    
    if [ "$APP_ID" = "null" ] || [ -z "$APP_ID" ]; then
        print_error "Failed to create app"
        echo "$create_output" | jq .
        exit 1
    fi
    
    print_status "App created with ID: $APP_ID"
    
    # Save app ID for future use
    echo "APP_ID=$APP_ID" > .app-id
    
    # Clean up temp file
    rm -f "$app_spec"
}

# Function to set environment variables
set_environment_variables() {
    print_header "Setting Environment Variables"
    
    if [ -z "$APP_ID" ]; then
        print_error "App ID not found. Run create command first."
        exit 1
    fi
    
    # Required environment variables
    local env_vars=(
        "NODE_ENV=${NODE_ENV:-production}"
        "PORT=3000"
        "DATABASE_URL=${DATABASE_URL}"
        "DATABASE_CA_CERT=${DATABASE_CA_CERT}"
        "PROXY_API_KEY=${PROXY_API_KEY}"
        "PROXY_SECRET_KEY=${PROXY_SECRET_KEY}"
        "ALLOWED_ORIGINS=${ALLOWED_ORIGINS:-https://partaday.com,https://www.partaday.com}"
    )
    
    for env_var in "${env_vars[@]}"; do
        local key=$(echo "$env_var" | cut -d'=' -f1)
        local value=$(echo "$env_var" | cut -d'=' -f2-)
        
        if [ -z "$value" ]; then
            print_warning "Environment variable $key is not set"
            read -p "Enter value for $key: " value
        fi
        
        # Determine if it should be a secret (contains sensitive info)
        local is_secret="false"
        case "$key" in
            DATABASE_URL|DATABASE_CA_CERT|PROXY_API_KEY|PROXY_SECRET_KEY)
                is_secret="true"
                ;;
        esac
        
        print_info "Setting $key..."
        doctl apps update "$APP_ID" --spec <(
            doctl apps get "$APP_ID" --format json | \
            jq --arg key "$key" --arg value "$value" --argjson secret "$is_secret" \
            '.spec.services[0].envs += [{"key": $key, "value": $value, "type": (if $secret then "SECRET" else "GENERAL" end)}]'
        ) > /dev/null
    done
    
    print_status "Environment variables configured"
}

# Function to deploy the app
deploy_app() {
    print_header "Deploying Application"
    
    if [ -z "$APP_ID" ]; then
        print_error "App ID not found. Run create command first."
        exit 1
    fi
    
    print_info "Triggering deployment..."
    local deployment_id=$(doctl apps create-deployment "$APP_ID" --format json | jq -r '.id')
    
    print_info "Deployment started with ID: $deployment_id"
    print_info "Waiting for deployment to complete..."
    
    # Wait for deployment to complete
    local status="PENDING"
    local attempt=0
    local max_attempts=60  # 10 minutes max
    
    while [ "$status" != "ACTIVE" ] && [ "$status" != "ERROR" ] && [ $attempt -lt $max_attempts ]; do
        sleep 10
        status=$(doctl apps get "$APP_ID" --format json | jq -r '.last_deployment_active_at // empty')
        
        if [ -n "$status" ]; then
            status="ACTIVE"
        else
            status=$(doctl apps get "$APP_ID" --format json | jq -r '.last_deployment_created_at')
            if [ "$status" != "null" ]; then
                status="BUILDING"
            fi
        fi
        
        attempt=$((attempt + 1))
        echo -n "."
    done
    
    echo ""
    
    if [ "$status" = "ACTIVE" ]; then
        print_status "Deployment completed successfully!"
    else
        print_error "Deployment failed or timed out"
        print_info "Check deployment status with: doctl apps get $APP_ID"
        exit 1
    fi
}

# Function to get app information
get_app_info() {
    print_header "Application Information"
    
    if [ -z "$APP_ID" ]; then
        if [ -f ".app-id" ]; then
            source .app-id
        else
            print_error "App ID not found. Run create command first."
            exit 1
        fi
    fi
    
    local app_info=$(doctl apps get "$APP_ID" --format json)
    local app_url=$(echo "$app_info" | jq -r '.live_url')
    local status=$(echo "$app_info" | jq -r '.phase')
    
    print_info "App ID: $APP_ID"
    print_info "App URL: $app_url"
    print_info "Status: $status"
    
    # Get outbound IP (this might not be directly available via API)
    print_info "Getting outbound IP address..."
    if [ "$app_url" != "null" ]; then
        local ip=$(dig +short $(echo "$app_url" | sed 's|https://||' | sed 's|http://||'))
        if [ -n "$ip" ]; then
            print_status "Outbound IP: $ip"
            echo ""
            print_warning "ADD THIS IP TO YOUR DATABASE TRUSTED SOURCES:"
            echo -e "${YELLOW}$ip/32${NC}"
            echo ""
        else
            print_info "Could not determine outbound IP automatically"
            print_info "Check the App Platform console for networking details"
        fi
    fi
    
    # Test health endpoint
    if [ "$app_url" != "null" ] && [ "$status" = "ACTIVE" ]; then
        print_info "Testing health endpoint..."
        if curl -s "$app_url/health" > /dev/null; then
            print_status "Health check passed!"
        else
            print_warning "Health check failed - app might still be starting"
        fi
    fi
}

# Function to update the app
update_app() {
    print_header "Updating Application"
    
    if [ -z "$APP_ID" ]; then
        if [ -f ".app-id" ]; then
            source .app-id
        else
            print_error "App ID not found. Run create command first."
            exit 1
        fi
    fi
    
    deploy_app
}

# Function to show logs
show_logs() {
    print_header "Application Logs"
    
    if [ -z "$APP_ID" ]; then
        if [ -f ".app-id" ]; then
            source .app-id
        else
            print_error "App ID not found. Run create command first."
            exit 1
        fi
    fi
    
    print_info "Fetching logs for app $APP_ID..."
    doctl apps logs "$APP_ID" --type=build,deploy,run --follow
}

# Function to delete the app
delete_app() {
    print_header "Deleting Application"
    
    if [ -z "$APP_ID" ]; then
        if [ -f ".app-id" ]; then
            source .app-id
        else
            print_error "App ID not found. Nothing to delete."
            exit 1
        fi
    fi
    
    read -p "Are you sure you want to delete app $APP_ID? (y/N): " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        doctl apps delete "$APP_ID" --force
        rm -f .app-id
        print_status "App deleted successfully"
    else
        print_info "Delete cancelled"
    fi
}

# Function to show help
show_help() {
    echo "PartADay Database Proxy Deployment Script"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  create    - Create and deploy the app"
    echo "  deploy    - Deploy/update the app"
    echo "  info      - Show app information and outbound IP"
    echo "  logs      - Show application logs"
    echo "  env       - Set environment variables"
    echo "  delete    - Delete the app"
    echo "  help      - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 create          # Create and deploy new app"
    echo "  $0 deploy          # Update existing app"
    echo "  $0 info            # Get app URL and IP for database whitelist"
    echo "  $0 logs            # Follow application logs"
}

# Main script logic
main() {
    local command=${1:-help}
    
    case $command in
        create)
            check_doctl
            check_files
            load_env
            get_github_repo
            create_app
            set_environment_variables
            deploy_app
            get_app_info
            ;;
        deploy|update)
            check_doctl
            load_env
            update_app
            get_app_info
            ;;
        info)
            check_doctl
            get_app_info
            ;;
        logs)
            check_doctl
            show_logs
            ;;
        env)
            check_doctl
            load_env
            set_environment_variables
            ;;
        delete)
            check_doctl
            delete_app
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            print_error "Unknown command: $command"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@" 
