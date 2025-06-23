-- Initial database schema for Source Parts Inc Database Proxy

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create users table
CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  email VARCHAR(255) UNIQUE NOT NULL,
  first_name VARCHAR(100),
  last_name VARCHAR(100),
  company VARCHAR(255),
  phone VARCHAR(50),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);

-- Create quote_requests table
CREATE TABLE IF NOT EXISTS quote_requests (
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

CREATE INDEX IF NOT EXISTS idx_quote_requests_reference_id ON quote_requests(reference_id);
CREATE INDEX IF NOT EXISTS idx_quote_requests_user_id ON quote_requests(user_id);
CREATE INDEX IF NOT EXISTS idx_quote_requests_status ON quote_requests(status);
CREATE INDEX IF NOT EXISTS idx_quote_requests_created_at ON quote_requests(created_at DESC);

-- Create part_suggestions table
CREATE TABLE IF NOT EXISTS part_suggestions (
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

CREATE INDEX IF NOT EXISTS idx_part_suggestions_reference_id ON part_suggestions(reference_id);
CREATE INDEX IF NOT EXISTS idx_part_suggestions_user_id ON part_suggestions(user_id);
CREATE INDEX IF NOT EXISTS idx_part_suggestions_status ON part_suggestions(status);
CREATE INDEX IF NOT EXISTS idx_part_suggestions_created_at ON part_suggestions(created_at DESC);

-- Create contact_support_requests table
CREATE TABLE IF NOT EXISTS contact_support_requests (
  id SERIAL PRIMARY KEY,
  user_id INTEGER REFERENCES users(id),
  reference_id VARCHAR(50) UNIQUE NOT NULL,
  subject VARCHAR(255) NOT NULL,
  message TEXT NOT NULL,
  category VARCHAR(50) DEFAULT 'general' CHECK (category IN ('general', 'technical', 'order', 'quote', 'other')),
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

CREATE INDEX IF NOT EXISTS idx_contact_support_reference_id ON contact_support_requests(reference_id);
CREATE INDEX IF NOT EXISTS idx_contact_support_user_id ON contact_support_requests(user_id);
CREATE INDEX IF NOT EXISTS idx_contact_support_status ON contact_support_requests(status);
CREATE INDEX IF NOT EXISTS idx_contact_support_priority ON contact_support_requests(priority);
CREATE INDEX IF NOT EXISTS idx_contact_support_created_at ON contact_support_requests(created_at DESC);

-- Create admin_users table
CREATE TABLE IF NOT EXISTS admin_users (
  id SERIAL PRIMARY KEY,
  email VARCHAR(255) UNIQUE NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  role VARCHAR(50) DEFAULT 'admin' CHECK (role IN ('admin', 'super_admin')),
  is_active BOOLEAN DEFAULT true,
  last_login TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_admin_users_email ON admin_users(email);

-- Create audit_logs table
CREATE TABLE IF NOT EXISTS audit_logs (
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

CREATE INDEX IF NOT EXISTS idx_audit_logs_admin_user_id ON audit_logs(admin_user_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_entity ON audit_logs(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON audit_logs(created_at DESC);

-- Create update timestamp function
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Create triggers for updated_at
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_quote_requests_updated_at BEFORE UPDATE ON quote_requests
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_part_suggestions_updated_at BEFORE UPDATE ON part_suggestions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_contact_support_requests_updated_at BEFORE UPDATE ON contact_support_requests
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_admin_users_updated_at BEFORE UPDATE ON admin_users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();