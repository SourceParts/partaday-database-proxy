#!/bin/bash

# Database migration script for Source Parts Inc Database Proxy

set -e

echo "🚀 Running database migrations..."

# Load environment variables
if [ -f .env ]; then
    export $(cat .env | xargs)
fi

# Check if required environment variables are set
if [ -z "$DATABASE_URL" ]; then
    echo "❌ ERROR: DATABASE_URL environment variable is not set"
    exit 1
fi

# Parse DATABASE_URL to extract components
if [[ $DATABASE_URL =~ postgres://([^:]+):([^@]+)@([^:]+):([^/]+)/(.+) ]]; then
    DB_USER="${BASH_REMATCH[1]}"
    DB_PASS="${BASH_REMATCH[2]}"
    DB_HOST="${BASH_REMATCH[3]}"
    DB_PORT="${BASH_REMATCH[4]}"
    DB_NAME="${BASH_REMATCH[5]}"
else
    echo "❌ ERROR: Invalid DATABASE_URL format"
    exit 1
fi

# Export individual components for psql
export PGUSER=$DB_USER
export PGPASSWORD=$DB_PASS
export PGHOST=$DB_HOST
export PGPORT=$DB_PORT
export PGDATABASE=$DB_NAME

# SSL settings
if [ ! -z "$DATABASE_SSL_CERT" ]; then
    export PGSSLMODE=require
    export PGSSLCERT=$DATABASE_SSL_CERT
fi

# Create migrations table if it doesn't exist
echo "📋 Creating migrations table..."
psql << EOF
CREATE TABLE IF NOT EXISTS schema_migrations (
    id SERIAL PRIMARY KEY,
    filename VARCHAR(255) UNIQUE NOT NULL,
    executed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
EOF

# Get list of migration files
MIGRATION_DIR="./migrations"
if [ ! -d "$MIGRATION_DIR" ]; then
    echo "❌ ERROR: Migration directory $MIGRATION_DIR does not exist"
    exit 1
fi

# Run migrations
for migration in $(ls $MIGRATION_DIR/*.sql | sort); do
    filename=$(basename $migration)
    
    # Check if migration has already been executed
    result=$(psql -t -c "SELECT COUNT(*) FROM schema_migrations WHERE filename = '$filename'")
    
    if [ $result -eq 0 ]; then
        echo "🔄 Running migration: $filename"
        
        # Execute migration
        psql < $migration
        
        # Record migration
        psql -c "INSERT INTO schema_migrations (filename) VALUES ('$filename')"
        
        echo "✅ Migration $filename completed"
    else
        echo "⏭️  Migration $filename already executed, skipping..."
    fi
done

echo "✨ All migrations completed successfully!"

# Show current schema version
echo ""
echo "📊 Current schema version:"
psql -c "SELECT filename, executed_at FROM schema_migrations ORDER BY executed_at DESC LIMIT 5"