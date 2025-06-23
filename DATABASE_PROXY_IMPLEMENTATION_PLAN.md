# Database Proxy Implementation Plan

## Overview
This document outlines the complete implementation plan for the Source Parts Inc database proxy service. The proxy acts as an intermediary between the Next.js application and the PostgreSQL database, providing secure API endpoints for managing quotes, part suggestions, and contact support requests.

## Architecture Overview

### Current State
- Basic Express.js server with placeholder endpoints
- PostgreSQL connection configured but not utilized
- Three main route modules: quotes, suggestions, contact-support
- Basic error handling middleware
- No data validation or persistence

### Target State
- Fully functional REST API with PostgreSQL integration
- Comprehensive data validation using Zod schemas
- Transactional database operations
- Proper error handling and logging
- Rate limiting and security measures
- Admin authentication and authorization
- Automated email notifications
- Comprehensive testing suite

## Database Schema Design

### Core Tables

#### 1. users
```sql
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  email VARCHAR(255) UNIQUE NOT NULL,
  first_name VARCHAR(100),
  last_name VARCHAR(100),
  company VARCHAR(255),
  phone VARCHAR(50),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_users_email ON users(email);
```

#### 2. quote_requests
```sql
CREATE TABLE quote_requests (
  id SERIAL PRIMARY KEY,
  user_id INTEGER REFERENCES users(id),
  reference_id VARCHAR(50) UNIQUE NOT NULL,
  part_type VARCHAR(100),
  part_number VARCHAR(100),
  manufacturer VARCHAR(255),
  quantity INTEGER NOT NULL,
  description TEXT,
  urgency VARCHAR(50) CHECK (urgency IN ('immediate', 'within_week', 'within_month', 'flexible')),
  budget_range VARCHAR(100),
  additional_notes TEXT,
  status VARCHAR(50) DEFAULT 'submitted' CHECK (status IN ('submitted', 'reviewing', 'quoted', 'accepted', 'rejected', 'expired')),
  quoted_price DECIMAL(10, 2),
  quote_valid_until DATE,
  email_updates BOOLEAN DEFAULT true,
  newsletter BOOLEAN DEFAULT false,
  source VARCHAR(50),
  user_agent TEXT,
  ip_address VARCHAR(45),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_quote_requests_reference_id ON quote_requests(reference_id);
CREATE INDEX idx_quote_requests_user_id ON quote_requests(user_id);
CREATE INDEX idx_quote_requests_status ON quote_requests(status);
CREATE INDEX idx_quote_requests_created_at ON quote_requests(created_at DESC);
```

#### 3. part_suggestions
```sql
CREATE TABLE part_suggestions (
  id SERIAL PRIMARY KEY,
  user_id INTEGER REFERENCES users(id),
  reference_id VARCHAR(50) UNIQUE NOT NULL,
  part_name VARCHAR(255) NOT NULL,
  part_number VARCHAR(100),
  manufacturer VARCHAR(255),
  category VARCHAR(100),
  description TEXT,
  why_important TEXT,
  availability_info TEXT,
  additional_notes TEXT,
  status VARCHAR(50) DEFAULT 'submitted' CHECK (status IN ('submitted', 'reviewing', 'approved', 'rejected', 'implemented')),
  admin_notes TEXT,
  source VARCHAR(50),
  user_agent TEXT,
  ip_address VARCHAR(45),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_part_suggestions_reference_id ON part_suggestions(reference_id);
CREATE INDEX idx_part_suggestions_user_id ON part_suggestions(user_id);
CREATE INDEX idx_part_suggestions_status ON part_suggestions(status);
CREATE INDEX idx_part_suggestions_created_at ON part_suggestions(created_at DESC);
```

#### 4. contact_support_requests
```sql
CREATE TABLE contact_support_requests (
  id SERIAL PRIMARY KEY,
  user_id INTEGER REFERENCES users(id),
  reference_id VARCHAR(50) UNIQUE NOT NULL,
  subject VARCHAR(255) NOT NULL,
  message TEXT NOT NULL,
  category VARCHAR(50) CHECK (category IN ('general', 'technical', 'order', 'quote', 'other')),
  priority VARCHAR(20) DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
  status VARCHAR(50) DEFAULT 'open' CHECK (status IN ('open', 'in_progress', 'resolved', 'closed')),
  assigned_to VARCHAR(100),
  response_message TEXT,
  resolved_at TIMESTAMP WITH TIME ZONE,
  part_id VARCHAR(50),
  part_name VARCHAR(255),
  source VARCHAR(50),
  user_agent TEXT,
  ip_address VARCHAR(45),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_contact_support_reference_id ON contact_support_requests(reference_id);
CREATE INDEX idx_contact_support_user_id ON contact_support_requests(user_id);
CREATE INDEX idx_contact_support_status ON contact_support_requests(status);
CREATE INDEX idx_contact_support_priority ON contact_support_requests(priority);
CREATE INDEX idx_contact_support_created_at ON contact_support_requests(created_at DESC);
```

#### 5. admin_users
```sql
CREATE TABLE admin_users (
  id SERIAL PRIMARY KEY,
  email VARCHAR(255) UNIQUE NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  role VARCHAR(50) DEFAULT 'admin' CHECK (role IN ('admin', 'super_admin')),
  is_active BOOLEAN DEFAULT true,
  last_login TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_admin_users_email ON admin_users(email);
```

#### 6. audit_logs
```sql
CREATE TABLE audit_logs (
  id SERIAL PRIMARY KEY,
  admin_user_id INTEGER REFERENCES admin_users(id),
  action VARCHAR(100) NOT NULL,
  entity_type VARCHAR(50) NOT NULL,
  entity_id INTEGER,
  changes JSONB,
  ip_address VARCHAR(45),
  user_agent TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_audit_logs_admin_user_id ON audit_logs(admin_user_id);
CREATE INDEX idx_audit_logs_entity ON audit_logs(entity_type, entity_id);
CREATE INDEX idx_audit_logs_created_at ON audit_logs(created_at DESC);
```

## Implementation Tasks

### Phase 1: Foundation (Week 1)
1. **Database Setup**
   - Create database schema and migrations
   - Set up migration tool (e.g., node-pg-migrate)
   - Create seed data for testing
   - Document database setup procedures

2. **Validation Schemas**
   - Implement Zod schemas for all endpoints
   - Create shared validation utilities
   - Add request validation middleware

3. **Database Connection Enhancement**
   - Optimize connection pool settings
   - Add connection retry logic
   - Implement health check endpoint
   - Add database query logging

### Phase 2: Core Functionality (Week 2)
1. **Quote Requests Implementation**
   - Complete CRUD operations
   - Add status management
   - Implement quote expiration logic
   - Add email notification triggers

2. **Part Suggestions Implementation**
   - Complete CRUD operations
   - Add approval workflow
   - Implement status tracking
   - Add category management

3. **Contact Support Implementation**
   - Complete CRUD operations
   - Add ticket management
   - Implement priority system
   - Add response tracking

### Phase 3: Admin Features (Week 3)
1. **Authentication & Authorization**
   - Implement JWT-based auth
   - Add role-based access control
   - Create admin login endpoints
   - Add session management

2. **Admin Endpoints**
   - Create admin dashboard API
   - Add bulk operations
   - Implement search and filters
   - Add export functionality

3. **Audit & Logging**
   - Implement audit trail
   - Add activity logging
   - Create log rotation
   - Add monitoring hooks

### Phase 4: Integration & Testing (Week 4)
1. **Email Integration**
   - Set up email service
   - Create email templates
   - Add queue system
   - Implement retry logic

2. **Testing Suite**
   - Unit tests for all routes
   - Integration tests
   - Load testing
   - Security testing

3. **Documentation**
   - API documentation
   - Deployment guide
   - Admin user guide
   - Troubleshooting guide

## Technical Specifications

### API Endpoints

#### Quote Requests
- `POST /api/quotes` - Create new quote request
- `GET /api/quotes` - List quote requests (admin)
- `GET /api/quotes/:id` - Get quote by ID
- `PUT /api/quotes/:id` - Update quote (admin)
- `PUT /api/quotes/:id/status` - Update quote status (admin)
- `POST /api/quotes/:id/send-quote` - Send quote to customer (admin)

#### Part Suggestions
- `POST /api/suggestions` - Create new suggestion
- `GET /api/suggestions` - List suggestions (admin)
- `GET /api/suggestions/:id` - Get suggestion by ID
- `PUT /api/suggestions/:id` - Update suggestion (admin)
- `PUT /api/suggestions/:id/status` - Update status (admin)

#### Contact Support
- `POST /api/contact-support` - Create support request
- `GET /api/contact-support` - List requests (admin)
- `GET /api/contact-support/:id` - Get request by ID
- `PUT /api/contact-support/:id` - Update request (admin)
- `PUT /api/contact-support/:id/status` - Update status (admin)
- `POST /api/contact-support/:id/respond` - Send response (admin)

#### Admin
- `POST /api/admin/login` - Admin login
- `POST /api/admin/logout` - Admin logout
- `GET /api/admin/dashboard` - Dashboard stats
- `GET /api/admin/audit-logs` - View audit logs

### Security Measures
1. **API Security**
   - Rate limiting per IP
   - Request size limits
   - SQL injection prevention
   - XSS protection
   - CORS configuration

2. **Data Protection**
   - Encrypt sensitive data
   - Secure password hashing
   - Environment variable management
   - SSL/TLS enforcement

3. **Access Control**
   - JWT token validation
   - Role-based permissions
   - IP whitelisting for admin
   - Session timeout

## Development Workflow

### Local Development
1. Clone repository
2. Install dependencies: `npm install`
3. Set up PostgreSQL database
4. Run migrations: `npm run migrate`
5. Seed data: `npm run seed`
6. Start dev server: `npm run dev`

### Testing
1. Unit tests: `npm run test`
2. Integration tests: `npm run test:integration`
3. Load tests: `npm run test:load`
4. Coverage report: `npm run test:coverage`

### Deployment
1. Build application: `npm run build`
2. Run migrations: `npm run migrate:prod`
3. Start server: `npm start`
4. Monitor health: `/api/health`

## Monitoring & Maintenance

### Health Checks
- Database connectivity
- Memory usage
- Response times
- Error rates

### Logging
- Application logs
- Access logs
- Error logs
- Audit logs

### Backups
- Daily database backups
- Transaction log backups
- Backup testing procedures
- Recovery procedures

## Success Metrics
- API response time < 200ms
- 99.9% uptime
- Zero data loss
- < 0.1% error rate
- All tests passing
- Complete audit trail

## Timeline
- Week 1: Foundation setup
- Week 2: Core functionality
- Week 3: Admin features
- Week 4: Testing & deployment
- Week 5: Production launch

## Next Steps
1. Review and approve this plan
2. Set up development environment
3. Begin Phase 1 implementation
4. Schedule regular progress reviews