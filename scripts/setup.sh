#!/bin/bash

# PartADay Database Proxy Setup Script
# This script helps set up the database proxy service

set -e

echo "🚀 PartADay Database Proxy Setup"
echo "=================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to generate random strings
generate_key() {
    openssl rand -hex $1
}

# Function to prompt for input
prompt_input() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    
    if [ -n "$default" ]; then
        read -p "$prompt [$default]: " input
        input=${input:-$default}
    else
        read -p "$prompt: " input
    fi
    
    eval "$var_name='$input'"
}

echo -e "${BLUE}Step 1: Environment Configuration${NC}"
echo "================================="

# Check if .env file exists
if [ -f ".env" ]; then
    echo -e "${YELLOW}Warning: .env file already exists!${NC}"
    read -p "Do you want to overwrite it? (y/N): " overwrite
    if [[ ! $overwrite =~ ^[Yy]$ ]]; then
        echo "Setup cancelled."
        exit 0
    fi
fi

# Generate API keys
echo -e "${GREEN}Generating secure API keys...${NC}"
API_KEY=$(generate_key 16)  # 32 character hex string
SECRET_KEY=$(generate_key 32)  # 64 character hex string

echo -e "${GREEN}✓ Generated API Key: ${API_KEY}${NC}"
echo -e "${GREEN}✓ Generated Secret Key: ${SECRET_KEY}${NC}"

# Get database configuration
echo ""
echo -e "${BLUE}Database Configuration:${NC}"
prompt_input "Database URL" "" DATABASE_URL
prompt_input "Database CA Certificate (optional)" "" DATABASE_CA_CERT

# Get CORS configuration
echo ""
echo -e "${BLUE}CORS Configuration:${NC}"
prompt_input "Allowed Origins" "https://partaday.com,https://www.partaday.com" ALLOWED_ORIGINS

# Get environment
echo ""
echo -e "${BLUE}Environment Configuration:${NC}"
prompt_input "Environment" "development" NODE_ENV
prompt_input "Port" "3000" PORT

# Create .env file
echo ""
echo -e "${GREEN}Creating .env file...${NC}"

cat > .env << EOF
# Database Configuration
DATABASE_URL=${DATABASE_URL}
DATABASE_CA_CERT="${DATABASE_CA_CERT}"

# Authentication Configuration
PROXY_API_KEY=${API_KEY}
PROXY_SECRET_KEY=${SECRET_KEY}

# CORS Configuration
ALLOWED_ORIGINS=${ALLOWED_ORIGINS}

# Application Configuration
NODE_ENV=${NODE_ENV}
PORT=${PORT}

# Connection Pool Configuration
MAX_CONNECTIONS=20
QUERY_TIMEOUT=30000
IDLE_TIMEOUT=30000

# Logging Configuration
LOG_LEVEL=info
LOG_FORMAT=json
EOF

echo -e "${GREEN}✓ .env file created successfully!${NC}"

echo ""
echo -e "${BLUE}Step 2: Dependencies${NC}"
echo "==================="

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo -e "${RED}❌ Node.js is not installed. Please install Node.js 18+ first.${NC}"
    exit 1
fi

NODE_VERSION=$(node --version)
echo -e "${GREEN}✓ Node.js version: ${NODE_VERSION}${NC}"

# Check if npm is installed
if ! command -v npm &> /dev/null; then
    echo -e "${RED}❌ npm is not installed. Please install npm first.${NC}"
    exit 1
fi

NPM_VERSION=$(npm --version)
echo -e "${GREEN}✓ npm version: ${NPM_VERSION}${NC}"

# Install dependencies
echo ""
echo -e "${GREEN}Installing dependencies...${NC}"
npm install

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Dependencies installed successfully!${NC}"
else
    echo -e "${RED}❌ Failed to install dependencies.${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}Step 3: Build Project${NC}"
echo "===================="

echo -e "${GREEN}Building TypeScript project...${NC}"
npm run build

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Project built successfully!${NC}"
else
    echo -e "${RED}❌ Build failed. Please check the errors above.${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}Step 4: Test Configuration${NC}"
echo "=========================="

echo -e "${GREEN}Testing database connection...${NC}"

# Start the server in background for testing
npm start &
SERVER_PID=$!

# Wait for server to start
sleep 5

# Test health endpoint
if curl -s http://localhost:${PORT}/health > /dev/null; then
    echo -e "${GREEN}✓ Health check passed!${NC}"
else
    echo -e "${YELLOW}⚠️  Health check failed - this might be expected if database is not accessible${NC}"
fi

# Stop the test server
kill $SERVER_PID 2>/dev/null || true

echo ""
echo -e "${BLUE}Step 5: Deployment Information${NC}"
echo "=============================="

echo ""
echo -e "${GREEN}🎉 Setup completed successfully!${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "1. Review the generated .env file"
echo "2. Test locally with: npm run dev"
echo "3. Deploy to DigitalOcean App Platform"
echo "4. Update your Vercel environment variables:"
echo ""
echo -e "${YELLOW}Vercel Environment Variables:${NC}"
echo "DATABASE_PROXY_URL=https://your-app.ondigitalocean.app"
echo "DATABASE_PROXY_API_KEY=${API_KEY}"
echo "DATABASE_PROXY_SECRET_KEY=${SECRET_KEY}"
echo ""
echo -e "${BLUE}For deployment help, see the README.md file.${NC}"

echo ""
echo -e "${GREEN}Setup completed! 🚀${NC}" 
