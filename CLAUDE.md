# Database Proxy Project Guidelines

## Package Manager
**IMPORTANT**: This project uses `pnpm` as the package manager. Always use `pnpm` commands:
- `pnpm install` - Install dependencies
- `pnpm add <package>` - Add new dependencies
- `pnpm dev` - Run development server
- `pnpm build` - Build for production
- `pnpm lint` - Run linting
- `pnpm test` - Run tests
- Never use `npm` or `yarn` commands

## Project Overview
This is the database proxy server for the PartAday Landing Page project. It provides a secure API layer between the Next.js frontend and the PostgreSQL database.

## Architecture
- **Framework**: Express.js with TypeScript
- **Database**: PostgreSQL (hosted on DigitalOcean)
- **Validation**: Zod schemas
- **Authentication**: JWT tokens for admin, API keys for public access
- **Security**: Helmet, CORS, rate limiting

## Available Routes
1. **Health Check**: `/health`
2. **Admin Auth**: `/api/admin` (login, logout, verify)
3. **Quote Requests**: `/api/quotes`
4. **Part Suggestions**: `/api/suggestions`
5. **Contact Support**: `/api/contact-support`
6. **Parts Catalog**: `/api/parts`

## Development Commands
```bash
# Install dependencies
pnpm install

# Run development server with hot reload
pnpm dev

# Build for production
pnpm build

# Start production server
pnpm start

# Run linting
pnpm lint

# Run tests
pnpm test
```

## Environment Variables
Required variables in `.env`:
- `DATABASE_URL` - PostgreSQL connection string
- `DATABASE_CA_CERT` - SSL certificate for secure connection
- `JWT_SECRET` - Secret for JWT token generation
- `PORT` - Server port (default: 3000)
- `ALLOWED_ORIGINS` - CORS allowed origins (comma-separated)

## Database Migrations
Migrations are located in `/migrations/` directory:
- `001_initial_schema.sql` - Base tables
- `002_parts_catalog_schema.sql` - Parts catalog and RSS tables

## Testing
When making changes, always run:
1. `pnpm lint` - Ensure code style compliance
2. `pnpm build` - Verify TypeScript compilation
3. Test endpoints using tools like Postman or curl

## Security Notes
- All API routes except health and admin login require authentication
- Admin routes use JWT tokens
- Public API access uses API keys
- All database queries use parameterized statements to prevent SQL injection
- Rate limiting is applied to all endpoints

## Deployment
1. Build the project: `pnpm build`
2. Ensure all environment variables are set
3. Run migrations on the production database
4. Start the server: `pnpm start`