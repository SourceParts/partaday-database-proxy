#!/bin/bash

# Helper script to switch .env to use certificate file instead of inline certificate

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🔧 Updating .env to use certificate file${NC}"
echo "================================="

# Check if .env exists
if [ ! -f ".env" ]; then
    echo -e "${RED}❌ .env file not found${NC}"
    exit 1
fi

# Check if ca-certificate.crt exists
if [ ! -f "ca-certificate.crt" ]; then
    echo -e "${RED}❌ ca-certificate.crt file not found${NC}"
    echo "Make sure you have downloaded the CA certificate from DigitalOcean"
    exit 1
fi

# Create backup of .env
cp .env .env.backup
echo -e "${GREEN}✅ Created backup: .env.backup${NC}"

# Remove inline certificate and add file path
echo -e "${BLUE}📝 Updating certificate configuration...${NC}"

# Remove the multiline DATABASE_CA_CERT entry
sed -i '/^DATABASE_CA_CERT=/,/^-----END CERTIFICATE-----"$/d' .env

# Add the certificate file path
echo "DATABASE_CA_CERT_FILE=./ca-certificate.crt" >> .env

echo -e "${GREEN}✅ Updated .env to use certificate file${NC}"
echo ""
echo -e "${BLUE}Changes made:${NC}"
echo "- Removed inline DATABASE_CA_CERT"
echo "- Added DATABASE_CA_CERT_FILE=./ca-certificate.crt"
echo ""
echo -e "${YELLOW}💡 To revert, run: mv .env.backup .env${NC}" 
