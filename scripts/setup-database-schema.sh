#!/bin/bash

# Database Schema Setup Script
# Creates all necessary tables for the PartADay application
#
# Usage:
#   ./scripts/setup-database-schema.sh [--force]
#
# The --force flag will drop existing tables and recreate them

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Parse arguments
FORCE_RECREATE=false
if [[ "$1" == "--force" ]]; then
    FORCE_RECREATE=true
fi

echo -e "${BLUE}🗄️  Database Schema Setup${NC}"
echo "=================================="

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

echo -e "${BLUE}Database:${NC} ${DATABASE_URL%%@*}@***"
echo ""

# Check if node is available
if ! command -v node &>/dev/null; then
    echo -e "${RED}❌ Node.js not found${NC}"
    echo "Install Node.js to run the schema setup"
    exit 1
fi

# Install dependencies if needed
if [ ! -d "node_modules" ] || [ ! -d "node_modules/pg" ]; then
    echo -e "${YELLOW}📦 Installing required dependencies...${NC}"
    npm install --no-save pg dotenv
fi

# Create schema setup script
cat >setup-schema.js <<'EOF'
const { Pool } = require('pg');
require('dotenv').config();

const forceRecreate = process.argv.includes('--force');

async function setupSchema() {
    console.log('🗄️  Setting up database schema...');
    
    // Parse connection string to extract components
    const url = new URL(process.env.DATABASE_URL);
    
    // Configure SSL for DigitalOcean
    let sslConfig = false;
    if (process.env.DATABASE_URL.includes('sslmode=require')) {
        sslConfig = {
            rejectUnauthorized: false
        };
        
        // Use certificate content from environment variable
        if (process.env.DATABASE_CA_CERT) {
            try {
                const caCert = process.env.DATABASE_CA_CERT.replace(/\\n/g, '\n');
                sslConfig.ca = caCert;
                sslConfig.rejectUnauthorized = true;
                console.log('🔒 Using SSL connection with CA certificate');
            } catch (error) {
                console.log('⚠️  Using relaxed SSL verification');
            }
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

    const pool = new Pool(config);

    try {
        const client = await pool.connect();
        console.log('✅ Connected to database');
        
        // Begin transaction
        await client.query('BEGIN');
        
        if (forceRecreate) {
            console.log('🧹 Force recreate mode: Dropping existing tables...');
            
            // Drop tables in reverse dependency order
            const dropTables = [
                'analytics_events',
                'part_suggestions', 
                'quote_requests',
                'parts',
                'users'
            ];
            
            for (const table of dropTables) {
                try {
                    await client.query(`DROP TABLE IF EXISTS ${table} CASCADE`);
                    console.log(`   ✅ Dropped table: ${table}`);
                } catch (error) {
                    console.log(`   ⚠️  Could not drop table ${table}: ${error.message}`);
                }
            }
        }
        
        console.log('📝 Creating database tables...');
        
        // 1. Users table
        await client.query(`
            CREATE TABLE IF NOT EXISTS users (
                id SERIAL PRIMARY KEY,
                email VARCHAR(255) UNIQUE NOT NULL,
                name VARCHAR(255),
                company VARCHAR(255),
                phone VARCHAR(50),
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                is_active BOOLEAN DEFAULT true
            )
        `);
        console.log('   ✅ Users table created');
        
        // 2. Parts table
        await client.query(`
            CREATE TABLE IF NOT EXISTS parts (
                id SERIAL PRIMARY KEY,
                name VARCHAR(500) NOT NULL,
                description TEXT,
                manufacturer VARCHAR(255),
                part_number VARCHAR(255),
                category VARCHAR(100),
                subcategory VARCHAR(100),
                image_url TEXT,
                datasheet_url TEXT,
                specifications JSONB,
                tags TEXT[],
                is_featured BOOLEAN DEFAULT false,
                featured_date DATE,
                status VARCHAR(50) DEFAULT 'active',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        `);
        console.log('   ✅ Parts table created');
        
        // 3. Quote requests table
        await client.query(`
            CREATE TABLE IF NOT EXISTS quote_requests (
                id SERIAL PRIMARY KEY,
                user_id INTEGER REFERENCES users(id),
                part_id INTEGER REFERENCES parts(id),
                company_name VARCHAR(255) NOT NULL,
                contact_name VARCHAR(255) NOT NULL,
                email VARCHAR(255) NOT NULL,
                phone VARCHAR(50),
                part_name VARCHAR(500),
                quantity INTEGER,
                message TEXT,
                status VARCHAR(50) DEFAULT 'pending',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        `);
        console.log('   ✅ Quote requests table created');
        
        // 4. Part suggestions table
        await client.query(`
            CREATE TABLE IF NOT EXISTS part_suggestions (
                id SERIAL PRIMARY KEY,
                user_id INTEGER REFERENCES users(id),
                part_name VARCHAR(500) NOT NULL,
                manufacturer VARCHAR(255),
                part_number VARCHAR(255),
                description TEXT,
                reason TEXT,
                contact_name VARCHAR(255) NOT NULL,
                email VARCHAR(255) NOT NULL,
                status VARCHAR(50) DEFAULT 'pending',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        `);
        console.log('   ✅ Part suggestions table created');
        
        // 5. Analytics events table
        await client.query(`
            CREATE TABLE IF NOT EXISTS analytics_events (
                id SERIAL PRIMARY KEY,
                event_type VARCHAR(100) NOT NULL,
                user_id INTEGER REFERENCES users(id),
                part_id INTEGER REFERENCES parts(id),
                event_data JSONB,
                ip_address INET,
                user_agent TEXT,
                referrer TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        `);
        console.log('   ✅ Analytics events table created');
        
        // Create indexes for better performance
        console.log('📊 Creating database indexes...');
        
        const indexes = [
            'CREATE INDEX IF NOT EXISTS idx_users_email ON users(email)',
            'CREATE INDEX IF NOT EXISTS idx_users_created_at ON users(created_at)',
            'CREATE INDEX IF NOT EXISTS idx_parts_status ON parts(status)',
            'CREATE INDEX IF NOT EXISTS idx_parts_featured ON parts(is_featured, featured_date)',
            'CREATE INDEX IF NOT EXISTS idx_parts_manufacturer ON parts(manufacturer)',
            'CREATE INDEX IF NOT EXISTS idx_parts_category ON parts(category, subcategory)',
            'CREATE INDEX IF NOT EXISTS idx_quote_requests_status ON quote_requests(status)',
            'CREATE INDEX IF NOT EXISTS idx_quote_requests_created_at ON quote_requests(created_at)',
            'CREATE INDEX IF NOT EXISTS idx_part_suggestions_status ON part_suggestions(status)',
            'CREATE INDEX IF NOT EXISTS idx_part_suggestions_created_at ON part_suggestions(created_at)',
            'CREATE INDEX IF NOT EXISTS idx_analytics_events_type ON analytics_events(event_type)',
            'CREATE INDEX IF NOT EXISTS idx_analytics_events_created_at ON analytics_events(created_at)',
            'CREATE INDEX IF NOT EXISTS idx_analytics_events_user_id ON analytics_events(user_id)',
            'CREATE INDEX IF NOT EXISTS idx_analytics_events_part_id ON analytics_events(part_id)'
        ];
        
        for (const indexQuery of indexes) {
            try {
                await client.query(indexQuery);
                const indexName = indexQuery.match(/idx_[a-z_]+/)[0];
                console.log(`   ✅ Index created: ${indexName}`);
            } catch (error) {
                console.log(`   ⚠️  Index creation failed: ${error.message}`);
            }
        }
        
        // Insert sample data if tables are empty
        console.log('🌱 Checking for sample data...');
        
        const partCount = await client.query('SELECT COUNT(*) FROM parts');
        if (parseInt(partCount.rows[0].count) === 0) {
            console.log('📝 Inserting sample parts data...');
            
            await client.query(`
                INSERT INTO parts (name, description, manufacturer, part_number, category, subcategory, is_featured, featured_date, status)
                VALUES 
                ('Arduino Uno R3', 'Microcontroller board based on the ATmega328P', 'Arduino', 'A000066', 'Microcontrollers', 'Development Boards', true, CURRENT_DATE, 'active'),
                ('Raspberry Pi 4 Model B', '4GB ARM Cortex-A72 single-board computer', 'Raspberry Pi Foundation', 'RPI4-MODBP-4GB', 'Single Board Computers', 'ARM Processors', false, NULL, 'active'),
                ('STM32F103C8T6', '32-bit ARM Cortex-M3 microcontroller', 'STMicroelectronics', 'STM32F103C8T6', 'Microcontrollers', 'ARM MCU', false, NULL, 'active'),
                ('ESP32-WROOM-32', 'WiFi & Bluetooth SoC module', 'Espressif', 'ESP32-WROOM-32', 'Wireless Modules', 'WiFi/Bluetooth', false, NULL, 'active'),
                ('LM7805', '5V voltage regulator', 'Texas Instruments', 'LM7805CT', 'Power Management', 'Voltage Regulators', false, NULL, 'active')
            `);
            
            console.log('   ✅ Sample parts data inserted');
        } else {
            console.log('   ℹ️  Parts table already contains data, skipping sample data insertion');
        }
        
        // Commit transaction
        await client.query('COMMIT');
        console.log('✅ Transaction committed');
        
        // Get table statistics
        console.log('');
        console.log('📊 Database Statistics:');
        
        const stats = await Promise.all([
            client.query('SELECT COUNT(*) FROM users'),
            client.query('SELECT COUNT(*) FROM parts'),
            client.query('SELECT COUNT(*) FROM quote_requests'),
            client.query('SELECT COUNT(*) FROM part_suggestions'),
            client.query('SELECT COUNT(*) FROM analytics_events')
        ]);
        
        console.log(`   Users: ${stats[0].rows[0].count}`);
        console.log(`   Parts: ${stats[1].rows[0].count}`);
        console.log(`   Quote Requests: ${stats[2].rows[0].count}`);
        console.log(`   Part Suggestions: ${stats[3].rows[0].count}`);
        console.log(`   Analytics Events: ${stats[4].rows[0].count}`);
        
        client.release();
        await pool.end();
        
        console.log('');
        console.log('🎉 Database schema setup completed successfully!');
        return true;
        
    } catch (error) {
        console.error('');
        console.error('❌ Schema setup failed:');
        console.error('   Error:', error.message);
        
        // Try to rollback
        try {
            await client.query('ROLLBACK');
            console.error('   Transaction rolled back');
        } catch (rollbackError) {
            console.error('   Could not rollback transaction');
        }
        
        await pool.end();
        return false;
    }
}

// Run with force recreate flag if provided
setupSchema(forceRecreate).then(success => {
    process.exit(success ? 0 : 1);
});
EOF

echo -e "${YELLOW}🗄️  Running schema setup...${NC}"
echo ""

# Run the schema setup
if [ "$FORCE_RECREATE" = true ]; then
    echo -e "${YELLOW}⚠️  Force recreate mode enabled - existing tables will be dropped!${NC}"
    if node setup-schema.js --force; then
        echo ""
        echo -e "${GREEN}✅ Database schema setup successful!${NC}"
        echo -e "${GREEN}🎉 Database is ready for the application!${NC}"
        exit_code=0
    else
        echo ""
        echo -e "${RED}❌ Database schema setup failed${NC}"
        exit_code=1
    fi
else
    if node setup-schema.js; then
        echo ""
        echo -e "${GREEN}✅ Database schema setup successful!${NC}"
        echo -e "${GREEN}🎉 Database is ready for the application!${NC}"
        exit_code=0
    else
        echo ""
        echo -e "${RED}❌ Database schema setup failed${NC}"
        echo -e "${YELLOW}💡 Try running with --force to recreate tables:${NC}"
        echo "   ./scripts/setup-database-schema.sh --force"
        exit_code=1
    fi
fi

# Clean up
rm -f setup-schema.js

exit $exit_code 
