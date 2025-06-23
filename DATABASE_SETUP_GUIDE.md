# Database Setup Guide

## Prerequisites
- PostgreSQL 14+ installed
- Node.js 18+ installed
- Access to database server
- SSL certificate (if required)

## Environment Configuration

Create a `.env` file in the `database-proxy-starter` directory:

```env
# Database Configuration
DATABASE_URL=postgres://username:password@host:port/database_name
DATABASE_SSL_CERT=./ca-certificate.crt

# Server Configuration
PORT=3001
NODE_ENV=development

# Security
JWT_SECRET=your-secret-key-here
ADMIN_EMAIL=admin@sourcepartsinc.com

# Email Configuration (optional)
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=your-email@gmail.com
SMTP_PASS=your-app-password
EMAIL_FROM=noreply@sourcepartsinc.com

# Rate Limiting
RATE_LIMIT_WINDOW_MS=900000
RATE_LIMIT_MAX_REQUESTS=100
```

## Database Setup Steps

### 1. Create Database

```bash
# Connect to PostgreSQL
psql -U postgres

# Create database
CREATE DATABASE sourceparts_db;

# Create user (if needed)
CREATE USER sourceparts_user WITH PASSWORD 'your-secure-password';

# Grant privileges
GRANT ALL PRIVILEGES ON DATABASE sourceparts_db TO sourceparts_user;

# Exit
\q
```

### 2. Run Migrations

```bash
# Navigate to proxy directory
cd database-proxy-starter

# Make migration script executable
chmod +x scripts/run-migrations.sh

# Run migrations
./scripts/run-migrations.sh
```

### 3. Create Initial Admin User

```bash
# Run the admin user creation script
node scripts/create-admin.js
```

Or manually:

```sql
-- Connect to database
psql -U sourceparts_user -d sourceparts_db

-- Create admin user (password should be hashed)
INSERT INTO admin_users (email, password_hash, role)
VALUES ('admin@sourcepartsinc.com', '$2b$10$...', 'super_admin');
```

### 4. Verify Installation

```bash
# Test database connection
node scripts/test-db-connection.js

# Check tables were created
psql -U sourceparts_user -d sourceparts_db -c "\dt"
```

## Migration Management

### Running Migrations

```bash
# Run all pending migrations
./scripts/run-migrations.sh

# Check migration status
psql -U sourceparts_user -d sourceparts_db -c "SELECT * FROM schema_migrations ORDER BY executed_at DESC;"
```

### Creating New Migrations

1. Create a new SQL file in the `migrations` folder:
   ```
   migrations/002_add_new_feature.sql
   ```

2. Add your SQL commands:
   ```sql
   -- Add new column
   ALTER TABLE users ADD COLUMN timezone VARCHAR(50);
   
   -- Create new table
   CREATE TABLE user_preferences (
     id SERIAL PRIMARY KEY,
     user_id INTEGER REFERENCES users(id),
     preference_key VARCHAR(100),
     preference_value TEXT,
     created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
   );
   ```

3. Run migrations:
   ```bash
   ./scripts/run-migrations.sh
   ```

## Seed Data (Development)

Create a seed data script for development:

```bash
# Create seed script
cat > scripts/seed-data.js << 'EOF'
const dbPool = require('../dist/database/connection').default;

async function seedData() {
  const client = await dbPool.getPool().connect();
  
  try {
    await client.query('BEGIN');
    
    // Create test users
    const users = [
      ['test1@example.com', 'John', 'Doe', 'Acme Corp', '555-0100'],
      ['test2@example.com', 'Jane', 'Smith', 'Tech Inc', '555-0200']
    ];
    
    for (const user of users) {
      await client.query(
        'INSERT INTO users (email, first_name, last_name, company, phone) VALUES ($1, $2, $3, $4, $5) ON CONFLICT (email) DO NOTHING',
        user
      );
    }
    
    // Create test quote requests
    const result = await client.query('SELECT id FROM users WHERE email = $1', ['test1@example.com']);
    const userId = result.rows[0].id;
    
    await client.query(
      `INSERT INTO quote_requests 
       (user_id, reference_id, part_type, part_number, manufacturer, quantity, urgency, status)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
      [userId, 'QR-TEST-001', 'Bearing', 'SKF-6205', 'SKF', 10, 'within_week', 'submitted']
    );
    
    await client.query('COMMIT');
    console.log('✅ Seed data created successfully');
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('❌ Error creating seed data:', error);
  } finally {
    client.release();
    process.exit();
  }
}

seedData();
EOF

# Run seed script
node scripts/seed-data.js
```

## Backup and Restore

### Backup Database

```bash
# Full backup
pg_dump -U sourceparts_user -h localhost sourceparts_db > backup_$(date +%Y%m%d_%H%M%S).sql

# Compressed backup
pg_dump -U sourceparts_user -h localhost sourceparts_db | gzip > backup_$(date +%Y%m%d_%H%M%S).sql.gz
```

### Restore Database

```bash
# From SQL file
psql -U sourceparts_user -h localhost sourceparts_db < backup_20240115_120000.sql

# From compressed file
gunzip -c backup_20240115_120000.sql.gz | psql -U sourceparts_user -h localhost sourceparts_db
```

## Troubleshooting

### Common Issues

1. **Connection Refused**
   - Check PostgreSQL is running: `sudo systemctl status postgresql`
   - Verify connection details in `.env`
   - Check firewall settings

2. **SSL Certificate Error**
   - Ensure certificate path is correct
   - Check certificate permissions: `chmod 600 ca-certificate.crt`

3. **Migration Fails**
   - Check SQL syntax
   - Verify user has necessary permissions
   - Look for constraint violations

### Debug Commands

```bash
# Test connection
psql $DATABASE_URL -c "SELECT version();"

# Check table structure
psql $DATABASE_URL -c "\d+ users"

# View recent errors
psql $DATABASE_URL -c "SELECT * FROM pg_stat_activity WHERE state = 'idle in transaction';"

# Check database size
psql $DATABASE_URL -c "SELECT pg_database_size('sourceparts_db');"
```

## Performance Optimization

### Indexes

The migration already creates necessary indexes. Monitor and add more as needed:

```sql
-- Check index usage
SELECT schemaname, tablename, indexname, idx_scan
FROM pg_stat_user_indexes
ORDER BY idx_scan;

-- Create additional indexes if needed
CREATE INDEX CONCURRENTLY idx_quote_requests_part_number 
ON quote_requests(part_number) 
WHERE part_number IS NOT NULL;
```

### Connection Pooling

The application uses connection pooling. Adjust settings in `src/database/connection.ts`:

```typescript
{
  max: 20,          // Maximum connections
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
}
```

## Security Best Practices

1. **Use Strong Passwords**
   - Minimum 16 characters
   - Mix of letters, numbers, symbols

2. **Limit Access**
   - Use firewall rules
   - Restrict database user permissions
   - Use SSL for connections

3. **Regular Updates**
   - Keep PostgreSQL updated
   - Update Node.js dependencies
   - Review and update migrations

4. **Monitoring**
   - Set up logging
   - Monitor connection counts
   - Track slow queries

## Next Steps

1. Complete environment setup
2. Run initial migrations
3. Create admin user
4. Test all endpoints
5. Set up monitoring
6. Configure backups