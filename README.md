# PartADay Database Proxy

A secure intermediary service that runs on DigitalOcean App Platform to provide database access to the Vercel-hosted PartADay application. This architecture enables IP whitelisting for enhanced database security while maintaining the benefits of Vercel's edge deployment.

## Architecture

```
[Vercel App] --HTTPS--> [DO App Platform Proxy] --PostgreSQL--> [DO Database]
     |                           |                                    |
  - Frontend                - Static IP                        - Whitelisted
  - API Routes              - Connection Pool                  - SSL Required
  - Serverless             - Authentication                    - Restricted User
```

## Features

- 🔒 **Secure Authentication** - API key + HMAC signature verification
- 🌐 **Static IP Whitelisting** - DigitalOcean App Platform provides predictable IPs
- 🏊 **Connection Pooling** - Optimized PostgreSQL connection management
- 📊 **Health Monitoring** - Comprehensive health checks and metrics
- ⚡ **Rate Limiting** - Global and per-API key rate limiting
- 🛡️ **Error Handling** - Robust error handling and logging
- 🔄 **Transaction Support** - Database transactions for data integrity

## Quick Start

### 1. Clone and Setup

```bash
git clone <your-repo-url>
cd partaday-database-proxy
npm install
```

### 2. Environment Variables

Create a `.env` file:

```bash
# Database
DATABASE_URL=postgresql://user:pass@host:port/db?sslmode=require
DATABASE_CA_CERT="-----BEGIN CERTIFICATE-----..."

# Authentication
PROXY_API_KEY=your-strong-api-key-here
PROXY_SECRET_KEY=your-strong-secret-key-here

# CORS
ALLOWED_ORIGINS=https://partaday.com,https://www.partaday.com,http://localhost:3000

# Node
NODE_ENV=development
PORT=3000
```

### 3. Development

```bash
# Start development server
npm run dev

# Build for production
npm run build

# Start production server
npm start

# Run tests
npm test
```

### 4. Database Schema

The service expects the following database tables (create these manually or with migrations):

```sql
-- Users table
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    company VARCHAR(255),
    phone VARCHAR(20),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Quote requests table
CREATE TABLE quote_requests (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    part_type VARCHAR(100),
    part_number VARCHAR(100),
    manufacturer VARCHAR(100),
    quantity INTEGER,
    description TEXT,
    urgency VARCHAR(50),
    budget_range VARCHAR(50),
    additional_notes TEXT,
    email_updates BOOLEAN DEFAULT FALSE,
    newsletter BOOLEAN DEFAULT FALSE,
    reference_id VARCHAR(50) UNIQUE,
    status VARCHAR(50) DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Part suggestions table
CREATE TABLE part_suggestions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    part_name VARCHAR(255),
    part_number VARCHAR(100),
    manufacturer VARCHAR(100),
    category VARCHAR(100),
    description TEXT,
    why_important TEXT,
    availability_info TEXT,
    additional_notes TEXT,
    reference_id VARCHAR(50) UNIQUE,
    status VARCHAR(50) DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Indexes for performance
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_quote_requests_reference_id ON quote_requests(reference_id);
CREATE INDEX idx_quote_requests_created_at ON quote_requests(created_at);
CREATE INDEX idx_part_suggestions_reference_id ON part_suggestions(reference_id);
CREATE INDEX idx_part_suggestions_created_at ON part_suggestions(created_at);
```

## Deployment to DigitalOcean App Platform

### 1. Create Database

First, create a PostgreSQL database in DigitalOcean:

1. Go to DigitalOcean Control Panel
2. Create → Databases → PostgreSQL
3. Choose your configuration
4. Note the connection details and CA certificate

### 2. Deploy App Platform Service

1. Fork this repository to your GitHub account

2. Go to DigitalOcean Control Panel → Apps

3. Create App → GitHub → Select your forked repository

4. Configure the app:
   - Use the included `.do/app.yaml` specification
   - Update the GitHub repo URL in the YAML file
   - Add environment variables in the App Platform console

5. Set the following environment variables in the App Platform:
   ```
   NODE_ENV=production
   PORT=3000
   DATABASE_URL=<your-database-connection-string>
   DATABASE_CA_CERT=<your-database-ca-certificate>
   PROXY_API_KEY=<generate-strong-api-key>
   PROXY_SECRET_KEY=<generate-strong-secret-key>
   ALLOWED_ORIGINS=https://partaday.com,https://www.partaday.com
   ```

6. Deploy the app

### 3. Configure Database Whitelist

1. After deployment, note your App Platform's outbound IP address
2. Go to your database settings
3. Add the App Platform IP to the trusted sources
4. Test connectivity via `/health` endpoint

### 4. Update Vercel Environment

Add these variables to your Vercel project:

```bash
DATABASE_PROXY_URL=https://your-proxy-app.ondigitalocean.app
DATABASE_PROXY_API_KEY=<same-as-proxy-service>
DATABASE_PROXY_SECRET_KEY=<same-as-proxy-service>
```

## API Endpoints

### Health Checks

- `GET /health` - Basic health check
- `GET /health/detailed` - Comprehensive health check
- `GET /health/ready` - Readiness probe
- `GET /health/live` - Liveness probe

### Quotes API

- `POST /api/quotes` - Create quote request
- `GET /api/quotes` - List quote requests (paginated)
- `GET /api/quotes/:id` - Get specific quote

### Suggestions API

- `POST /api/suggestions` - Create part suggestion
- `GET /api/suggestions` - List suggestions (paginated)
- `GET /api/suggestions/:id` - Get specific suggestion
- `PUT /api/suggestions/:id/status` - Update suggestion status

## Authentication

All API endpoints (except health checks) require authentication via headers:

```typescript
const headers = {
  'x-api-key': 'your-api-key',
  'x-signature': 'hmac-sha256-signature',
  'x-timestamp': 'unix-timestamp-ms',
  'content-type': 'application/json'
}
```

The signature is calculated as:
```
HMAC-SHA256(JSON.stringify(body) + timestamp, secret_key)
```

## Vercel Integration

Use the provided client library in your Vercel app:

```typescript
// lib/database/proxy-client.ts
import dbProxy from '@/lib/database/proxy-client'

// Create quote request
const result = await dbProxy.createQuoteRequest(quoteData)

// Create suggestion
const result = await dbProxy.createSuggestion(suggestionData)

// Health check
const health = await dbProxy.healthCheck()
```

## Monitoring and Logging

The service provides comprehensive logging and monitoring:

- **Structured Logs** - JSON formatted logs for all operations
- **Performance Metrics** - Query timing and connection pool stats
- **Health Checks** - Multiple endpoints for different monitoring needs
- **Error Tracking** - Detailed error logging with context

## Security Features

- **HMAC Authentication** - Prevents unauthorized access
- **Timestamp Validation** - Prevents replay attacks (5-minute window)
- **Rate Limiting** - Global (100/15min) and per-key (20/min) limits
- **CORS Protection** - Configurable allowed origins
- **SQL Injection Prevention** - Parameterized queries only
- **Connection Security** - SSL-only database connections

## Production Considerations

1. **Scaling** - Increase instance count for higher load
2. **Monitoring** - Set up alerts for health check failures
3. **Backups** - Ensure database backups are configured
4. **SSL Certificates** - App Platform handles SSL automatically
5. **Logs** - Use DigitalOcean's log aggregation features

## Troubleshooting

### Common Issues

1. **Database Connection Failed**
   - Check DATABASE_URL format
   - Verify IP is whitelisted
   - Ensure SSL certificate is correct

2. **Authentication Errors**
   - Verify API keys match between services
   - Check timestamp is within 5-minute window
   - Ensure HMAC signature calculation is correct

3. **Rate Limiting**
   - Check if requests exceed limits
   - Implement exponential backoff in client

4. **Health Check Failures**
   - Check `/health/detailed` for specific issues
   - Verify database connectivity
   - Check memory usage

### Debug Mode

Set `NODE_ENV=development` for detailed logging:

```bash
# Enable debug logging
NODE_ENV=development npm run dev
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

MIT License - see LICENSE file for details.

---

## Support

For issues and questions:
- Check the health endpoints for system status
- Review logs for specific error messages
- Ensure all environment variables are set correctly
- Verify database schema matches expectations 
