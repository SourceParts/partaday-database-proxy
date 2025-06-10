#!/bin/bash

# Database Connection Test Script
# Tests the database connection with automatic IP whitelisting using doctl
#
# Usage:
#   ./scripts/test-db-connection.sh           # Interactive mode
#   ./scripts/test-db-connection.sh --auto   # Automatic mode (no prompts)
#   ./scripts/test-db-connection.sh --manual # Manual mode (no auto-whitelisting)

set -e

# Parse command line arguments
AUTO_MODE=false
MANUAL_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
    --auto | -a)
        AUTO_MODE=true
        shift
        ;;
    --manual | -m)
        MANUAL_MODE=true
        shift
        ;;
    --help | -h)
        echo "Database Connection Test Script"
        echo ""
        echo "Usage:"
        echo "  $0           # Interactive mode (default)"
        echo "  $0 --auto   # Automatic IP whitelisting (no prompts)"
        echo "  $0 --manual # Manual mode (no auto-whitelisting)"
        echo "  $0 --help   # Show this help"
        echo ""
        echo "The script automatically manages IP whitelisting using doctl CLI."
        exit 0
        ;;
    *)
        echo "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
    esac
done

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🔍 Database Connection Test with Auto-Whitelisting${NC}"
echo "=================================================="

# Global variables for cleanup
LOCAL_IP=""
DATABASE_ID=""
FIREWALL_RULE_UUID=""
TEMP_RULE_ADDED=false

# Cleanup function - runs even if script fails
cleanup() {
    if [ "$TEMP_RULE_ADDED" = true ] && [ -n "$DATABASE_ID" ] && [ -n "$FIREWALL_RULE_UUID" ]; then
        echo ""
        echo -e "${YELLOW}🧹 Cleaning up: Removing temporary IP whitelist...${NC}"
        if doctl databases firewalls remove "$DATABASE_ID" --uuid "$FIREWALL_RULE_UUID" 2>/dev/null; then
            echo -e "${GREEN}✅ IP $LOCAL_IP removed from database whitelist${NC}"
        else
            echo -e "${RED}⚠️  Failed to remove IP $LOCAL_IP - you may need to remove it manually${NC}"
        fi
    fi
}

# Set cleanup trap
trap cleanup EXIT INT TERM

# Function to check doctl
check_doctl() {
    if ! command -v doctl &>/dev/null; then
        echo -e "${RED}❌ doctl CLI not found${NC}"
        echo "Install doctl to use automatic whitelisting: https://docs.digitalocean.com/reference/doctl/"
        return 1
    fi

    if ! doctl account get >/dev/null 2>&1; then
        echo -e "${RED}❌ doctl not authenticated${NC}"
        echo "Run: doctl auth init"
        return 1
    fi

    echo -e "${GREEN}✅ doctl CLI ready${NC}"
    return 0
}

# Function to get local IP
get_local_ip() {
    echo -e "${BLUE}🌐 Getting your public IP address...${NC}"

    if LOCAL_IP=$(curl -s --max-time 10 https://ipv4.icanhazip.com 2>/dev/null); then
        # Remove any whitespace
        LOCAL_IP=$(echo "$LOCAL_IP" | tr -d '[:space:]')

        # Validate IP format
        if [[ $LOCAL_IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo -e "${GREEN}✅ Your public IP: $LOCAL_IP${NC}"
            return 0
        else
            echo -e "${RED}❌ Invalid IP format received: $LOCAL_IP${NC}"
            return 1
        fi
    else
        echo -e "${RED}❌ Failed to get public IP address${NC}"
        echo "Check your internet connection"
        return 1
    fi
}

# Function to extract database ID from connection string
get_database_id() {
    echo -e "${BLUE}🔍 Finding database ID...${NC}"

    # Extract database name from hostname (format: db-postgresql-sfo3-partaday-do-user-*)
    if [[ $DATABASE_URL =~ @([^:]+): ]]; then
        local hostname="${BASH_REMATCH[1]}"
        echo -e "${BLUE}Database hostname: $hostname${NC}"

        # Extract database name from hostname (everything before -do-user-)
        if [[ $hostname =~ ^([^-]+-[^-]+-[^-]+-[^-]+)-do-user- ]]; then
            local db_name="${BASH_REMATCH[1]}"
            echo -e "${BLUE}Looking for database name: $db_name${NC}"
        else
            echo -e "${RED}❌ Could not extract database name from hostname${NC}"
            return 1
        fi

        # List databases and find matching one by name
        local db_list=$(doctl databases list --format ID,Name --no-header 2>/dev/null)

        if [ -z "$db_list" ]; then
            echo -e "${RED}❌ No databases found or unable to list databases${NC}"
            return 1
        fi

        # Find database ID by matching name (handle space-separated output)
        while read -r line; do
            if [ -z "$line" ]; then continue; fi

            # Split by whitespace and get first two fields
            id=$(echo "$line" | awk '{print $1}')
            name=$(echo "$line" | awk '{$1=""; print $0}' | sed 's/^ *//')

            if [[ "$name" == "$db_name" ]]; then
                DATABASE_ID="$id"
                echo -e "${GREEN}✅ Found database: $name (ID: $DATABASE_ID)${NC}"
                return 0
            fi
        done <<<"$db_list"

        echo -e "${RED}❌ Database not found for name: $db_name${NC}"
        echo "Available databases:"
        echo "$db_list"
        return 1
    else
        echo -e "${RED}❌ Could not extract hostname from DATABASE_URL${NC}"
        return 1
    fi
}

# Function to add IP to firewall
add_ip_to_firewall() {
    echo -e "${BLUE}🔒 Adding IP $LOCAL_IP to database firewall...${NC}"

    # Add IP to firewall rules
    if doctl databases firewalls append "$DATABASE_ID" --rule ip_addr:$LOCAL_IP >/dev/null 2>&1; then
        TEMP_RULE_ADDED=true
        echo -e "${GREEN}✅ IP whitelisted successfully${NC}"

        # Get the UUID of our newly added rule
        echo -e "${BLUE}🔍 Getting firewall rule UUID for cleanup...${NC}"
        local firewall_list=$(doctl databases firewalls list "$DATABASE_ID" --format UUID,Value --no-header 2>/dev/null)

        while read -r line; do
            if [ -z "$line" ]; then continue; fi
            local uuid=$(echo "$line" | awk '{print $1}')
            local value=$(echo "$line" | awk '{print $2}')

            if [[ "$value" == "$LOCAL_IP" ]]; then
                FIREWALL_RULE_UUID="$uuid"
                echo -e "${BLUE}Found rule UUID: $FIREWALL_RULE_UUID${NC}"
                break
            fi
        done <<<"$firewall_list"

        # Wait a moment for the rule to propagate
        echo -e "${YELLOW}⏳ Waiting 10 seconds for firewall rule to propagate...${NC}"
        sleep 10

        return 0
    else
        echo -e "${RED}❌ Failed to add IP to firewall${NC}"
        return 1
    fi
}

# Check if .env file exists
if [ ! -f ".env" ]; then
    echo -e "${RED}❌ .env file not found${NC}"
    echo "Run ./scripts/configure-db.sh first to set up your database configuration"
    exit 1
fi

# Load environment variables
set -a
source .env
set +a

# Check required variables
if [ -z "$DATABASE_URL" ]; then
    echo -e "${RED}❌ DATABASE_URL not set in .env file${NC}"
    exit 1
fi

echo -e "${BLUE}Database URL:${NC} ${DATABASE_URL%%@*}@***"
echo -e "${BLUE}SSL Mode:${NC} $(echo $DATABASE_URL | grep -o 'sslmode=[^&]*' || echo 'not specified')"
echo -e "${BLUE}CA Certificate:${NC} $([ -n "$DATABASE_CA_CERT" ] && echo 'configured' || echo 'not provided')"
echo ""

# Determine whitelisting mode
if [ "$MANUAL_MODE" = true ]; then
    use_auto_whitelist="n"
    echo -e "${BLUE}📝 Manual mode selected via command line${NC}"
elif [ "$AUTO_MODE" = true ]; then
    use_auto_whitelist="y"
    echo -e "${BLUE}🤖 Automatic mode selected via command line${NC}"
else
    # Ask user if they want automatic IP whitelisting
    echo -e "${YELLOW}🤖 Automatic IP Whitelisting Available${NC}"
    echo "This script can automatically:"
    echo "  1. Get your public IP address"
    echo "  2. Add it to the database firewall"
    echo "  3. Run the connection test"
    echo "  4. Remove your IP when done"
    echo ""
    read -p "Use automatic IP whitelisting? (Y/n): " use_auto_whitelist
    use_auto_whitelist=${use_auto_whitelist:-Y}
fi

if [[ $use_auto_whitelist =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${BLUE}🔧 Setting up automatic IP whitelisting...${NC}"

    # Check doctl
    if ! check_doctl; then
        echo -e "${YELLOW}⚠️  Falling back to manual testing${NC}"
        if [ "$AUTO_MODE" != true ]; then
            echo "Add your IP to the database trusted sources manually, then press Enter to continue..."
            read -p ""
        else
            echo -e "${RED}❌ Auto mode requires doctl to be available and authenticated${NC}"
            exit 1
        fi
    else
        # Get local IP
        if ! get_local_ip; then
            echo -e "${RED}❌ Cannot proceed with automatic whitelisting${NC}"
            exit 1
        fi

        # Get database ID
        if ! get_database_id; then
            echo -e "${RED}❌ Cannot find database for automatic whitelisting${NC}"
            exit 1
        fi

        # Add IP to firewall
        if ! add_ip_to_firewall; then
            echo -e "${RED}❌ Failed to whitelist IP automatically${NC}"
            exit 1
        fi
    fi
else
    echo ""
    echo -e "${YELLOW}📝 Manual IP whitelisting selected${NC}"
    if [ "$AUTO_MODE" != true ]; then
        echo "Make sure your IP is added to the database trusted sources, then press Enter to continue..."
        read -p ""
    else
        echo -e "${RED}❌ Auto mode was requested but manual mode was selected - this is a conflict${NC}"
        exit 1
    fi
fi

echo ""

# Check if node is available
if ! command -v node &>/dev/null; then
    echo -e "${RED}❌ Node.js not found${NC}"
    echo "Install Node.js to run the connection test"
    exit 1
fi

# Install dependencies if needed
if [ ! -d "node_modules" ] || [ ! -d "node_modules/pg" ]; then
    echo -e "${YELLOW}📦 Installing required dependencies...${NC}"
    npm install --no-save pg dotenv
fi

# Create connection test script
cat >test-connection.js <<'EOF'
const { Pool } = require('pg');
require('dotenv').config();

async function testConnection() {
    console.log('🔍 Attempting database connection...');
    
    // Parse connection string to extract components
    const url = new URL(process.env.DATABASE_URL);
    
    // Configure SSL for DigitalOcean
    let sslConfig = false;
    if (process.env.DATABASE_URL.includes('sslmode=require')) {
        sslConfig = {
            rejectUnauthorized: false  // Allow DigitalOcean's SSL setup
        };
        
        // Use certificate file if available
        if (process.env.DATABASE_CA_CERT_FILE) {
            try {
                const fs = require('fs');
                const caCert = fs.readFileSync(process.env.DATABASE_CA_CERT_FILE, 'utf8');
                sslConfig.ca = caCert;
                sslConfig.rejectUnauthorized = true;
                console.log('🔒 Using CA certificate from file for SSL connection');
            } catch (error) {
                console.log('⚠️  CA certificate file not found, using relaxed SSL');
            }
        } else if (process.env.DATABASE_CA_CERT) {
            // Use certificate content from environment variable
            try {
                // Replace \n with actual newlines in the certificate
                const caCert = process.env.DATABASE_CA_CERT.replace(/\\n/g, '\n');
                sslConfig.ca = caCert;
                sslConfig.rejectUnauthorized = true;
                console.log('🔒 Using CA certificate from environment variable for SSL connection');
            } catch (error) {
                console.log('⚠️  Failed to process CA certificate from environment, using relaxed SSL');
            }
        } else {
            console.log('🔒 Using relaxed SSL verification');
        }
    }
    
    const config = {
        host: url.hostname,
        port: parseInt(url.port) || 5432,
        database: url.pathname.slice(1) || 'defaultdb',
        user: url.username,
        password: url.password,
        connectionTimeoutMillis: 10000,
        ssl: sslConfig
    };
    
    console.log('🔍 Connecting to:', url.hostname + ':' + config.port);
    console.log('🔍 Database:', config.database);
    console.log('🔍 User:', config.user);

    const pool = new Pool(config);

    try {
        console.log('⏳ Connecting to database...');
        const client = await pool.connect();
        
        console.log('✅ Connection established!');
        
        // Test basic queries
        const versionResult = await client.query('SELECT version()');
        const dbResult = await client.query('SELECT current_database(), current_user, inet_server_addr()');
        
        console.log('');
        console.log('📊 Database Information:');
        console.log('  Database:', dbResult.rows[0].current_database);
        console.log('  User:', dbResult.rows[0].current_user);
        console.log('  Server IP:', dbResult.rows[0].inet_server_addr || 'N/A');
        console.log('  Version:', versionResult.rows[0].version.split(' ').slice(0, 2).join(' '));
        
        // Test create table permissions
        try {
            await client.query('CREATE TABLE IF NOT EXISTS connection_test (id SERIAL PRIMARY KEY, test_time TIMESTAMP DEFAULT NOW())');
            await client.query('INSERT INTO connection_test DEFAULT VALUES');
            const testResult = await client.query('SELECT COUNT(*) as count FROM connection_test');
            await client.query('DROP TABLE connection_test');
            
            console.log('  Permissions: ✅ Create/Insert/Drop (Full access)');
        } catch (permError) {
            console.log('  Permissions: ⚠️  Limited (Read-only or restricted)');
        }
        
        client.release();
        await pool.end();
        
        console.log('');
        console.log('🎉 Database connection test completed successfully!');
        return true;
        
    } catch (error) {
        console.error('');
        console.error('❌ Connection failed:');
        console.error('  Error:', error.message);
        
        if (error.message.includes('no pg_hba.conf entry')) {
            console.error('');
            console.error('🔒 This usually means your IP address is not whitelisted.');
            console.error('   Add your IP to the database trusted sources:');
            console.error('   - Go to DigitalOcean database settings');
            console.error('   - Add trusted source: your.ip.address/32');
        } else if (error.message.includes('certificate verify failed')) {
            console.error('');
            console.error('🔒 SSL certificate verification failed.');
            console.error('   Check that your CA certificate is correct.');
        } else if (error.message.includes('timeout')) {
            console.error('');
            console.error('⏰ Connection timeout - check network connectivity.');
        }
        
        await pool.end();
        return false;
    }
}

testConnection().then(success => {
    process.exit(success ? 0 : 1);
});
EOF

echo -e "${YELLOW}🧪 Running connection test...${NC}"
echo ""

# Run the test
if node test-connection.js; then
    echo ""
    echo -e "${GREEN}✅ Database connection test successful!${NC}"
    if [ "$TEMP_RULE_ADDED" = true ]; then
        echo -e "${GREEN}🎉 Database is ready for deployment!${NC}"
        echo -e "${BLUE}ℹ️  Your IP will be automatically removed from the whitelist${NC}"
    else
        echo -e "${GREEN}🎉 Database is ready for deployment!${NC}"
    fi
    exit_code=0
else
    echo ""
    echo -e "${RED}❌ Database connection test failed${NC}"
    echo ""
    if [ "$TEMP_RULE_ADDED" = true ]; then
        echo -e "${YELLOW}💡 Even though auto-whitelisting worked, the connection failed.${NC}"
        echo -e "${YELLOW}This suggests an issue with credentials or configuration:${NC}"
    else
        echo -e "${YELLOW}💡 Common solutions:${NC}"
    fi
    echo "1. Check that your connection string is correct"
    echo "2. Verify the CA certificate is properly formatted"
    echo "3. Ensure the database user has proper permissions"
    if [ "$TEMP_RULE_ADDED" != true ]; then
        echo "4. Try running with automatic IP whitelisting: ./scripts/test-db-connection.sh"
    fi
    exit_code=1
fi

# Clean up
rm -f test-connection.js

# Note: The cleanup() function will automatically remove the IP if it was added

exit $exit_code
