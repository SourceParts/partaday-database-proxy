#!/bin/bash

# Database Configuration Helper
# Sets up environment variables for DigitalOcean database connection

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🔧 Database Configuration Setup${NC}"
echo "======================================="

# Function to read multiline input
read_multiline() {
    local prompt="$1"
    local var_name="$2"

    echo -e "${YELLOW}$prompt${NC}"
    echo "Press Ctrl+D when finished, or type 'END' on a new line:"

    local content=""
    local line
    while IFS= read -r line; do
        if [ "$line" = "END" ]; then
            break
        fi
        if [ -n "$content" ]; then
            content="$content\n$line"
        else
            content="$line"
        fi
    done

    eval "$var_name='$content'"
}

# Get database connection info
echo ""
echo -e "${BLUE}Step 1: Database Connection String${NC}"
echo "Paste your DigitalOcean database connection string:"
echo "Should look like: postgresql://doadmin:password@host:25060/defaultdb?sslmode=require"
read -p "DATABASE_URL: " DATABASE_URL

# Validate connection string format
if [[ ! "$DATABASE_URL" =~ ^postgresql:// ]]; then
    echo -e "${RED}❌ Invalid connection string format${NC}"
    echo "Should start with postgresql://"
    exit 1
fi

echo -e "${GREEN}✓ Database URL configured${NC}"

# Get CA Certificate
echo ""
echo -e "${BLUE}Step 2: CA Certificate${NC}"
echo "Paste your DigitalOcean CA certificate (including BEGIN/END lines):"

read_multiline "CA Certificate:" DATABASE_CA_CERT

if [[ ! "$DATABASE_CA_CERT" =~ "BEGIN CERTIFICATE" ]]; then
    echo -e "${RED}❌ CA Certificate doesn't look valid${NC}"
    echo "Should start with -----BEGIN CERTIFICATE-----"
    exit 1
fi

echo -e "${GREEN}✓ CA Certificate configured${NC}"

# Generate API keys
echo ""
echo -e "${BLUE}Step 3: Generating API Keys${NC}"

if command -v openssl &>/dev/null; then
    PROXY_API_KEY=$(openssl rand -hex 16)
    PROXY_SECRET_KEY=$(openssl rand -hex 32)
    echo -e "${GREEN}✓ API keys generated securely${NC}"
else
    # Fallback if openssl not available
    PROXY_API_KEY=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 32)
    PROXY_SECRET_KEY=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 64)
    echo -e "${YELLOW}⚠ Generated keys using fallback method${NC}"
fi

# Set other defaults
ALLOWED_ORIGINS="https://partaday.com,https://www.partaday.com,http://localhost:3000"
NODE_ENV="development"
PORT="3000"

# Create .env file
echo ""
echo -e "${BLUE}Step 4: Creating .env file${NC}"

cat >.env <<EOF
# ========================================
# PartADay Database Proxy Configuration
# ========================================

# Database Configuration from DigitalOcean
DATABASE_URL=$DATABASE_URL
DATABASE_CA_CERT="$DATABASE_CA_CERT"

# Authentication Configuration (Generated)
PROXY_API_KEY=$PROXY_API_KEY
PROXY_SECRET_KEY=$PROXY_SECRET_KEY

# CORS Configuration
ALLOWED_ORIGINS=$ALLOWED_ORIGINS

# Application Configuration
NODE_ENV=$NODE_ENV
PORT=$PORT

# Connection Pool Settings
MAX_CONNECTIONS=20
QUERY_TIMEOUT=30000
IDLE_TIMEOUT=30000

# Logging Configuration
LOG_LEVEL=info
LOG_FORMAT=json
EOF

echo -e "${GREEN}✓ .env file created successfully!${NC}"

# Note about connection testing
echo ""
echo -e "${BLUE}Step 5: Configuration Complete${NC}"
echo -e "${YELLOW}⚠️  Database connection test skipped${NC}"
echo "Your local IP may not be whitelisted in the database trusted sources."
echo "The connection will be tested when deployed to App Platform."

# Show next steps
echo ""
echo -e "${BLUE}🎉 Configuration Complete!${NC}"
echo "======================================="
echo ""
echo -e "${GREEN}Generated credentials for Vercel:${NC}"
echo "DATABASE_PROXY_API_KEY=$PROXY_API_KEY"
echo "DATABASE_PROXY_SECRET_KEY=$PROXY_SECRET_KEY"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "1. Run: ./scripts/setup.sh (to install dependencies and build)"
echo "2. Run: ./scripts/deploy.sh create (to deploy to App Platform)"
echo "3. Add the Vercel environment variables shown above"
echo ""
echo -e "${BLUE}Optional - Test database connection:${NC}"
echo "4. Run: ./scripts/test-db-connection.sh (after whitelisting your IP)"
echo ""
echo -e "${YELLOW}Important: Save these API keys securely!${NC}"
