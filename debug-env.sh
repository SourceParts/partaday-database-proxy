#!/bin/bash
set -e

echo "=== Environment Debug ==="

# Check if .env file exists
if [ ! -f ".env" ]; then
    echo "❌ .env file not found"
    exit 1
fi

echo "✅ .env file exists"

# Load environment variables
set -a
source .env
set +a

echo "DATABASE_URL length: ${#DATABASE_URL}"
echo "DATABASE_URL starts with: ${DATABASE_URL:0:20}..."

# Check required variables
if [ -z "$DATABASE_URL" ]; then
    echo "❌ DATABASE_URL not set in .env file"
    exit 1
fi

echo "✅ DATABASE_URL is set correctly" 
