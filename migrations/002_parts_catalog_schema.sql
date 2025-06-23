-- Migration: Add parts catalog and RSS subscription tables
-- Date: 2025-01-23
-- Description: Creates tables for parts catalog, RSS subscriptions, and search functionality

-- Parts catalog table
CREATE TABLE IF NOT EXISTS parts (
    id SERIAL PRIMARY KEY,
    sku VARCHAR(100) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    category VARCHAR(100),
    manufacturer VARCHAR(255),
    specifications JSONB DEFAULT '{}',
    image_urls TEXT[] DEFAULT '{}',
    base_price DECIMAL(10, 2),
    currency VARCHAR(3) DEFAULT 'USD',
    availability_status VARCHAR(50) DEFAULT 'available',
    stock_quantity INTEGER DEFAULT 0,
    featured BOOLEAN DEFAULT FALSE,
    featured_date DATE,
    tags TEXT[] DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- RSS subscriptions table
CREATE TABLE IF NOT EXISTS rss_subscriptions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    tier VARCHAR(50) NOT NULL CHECK (tier IN ('public', 'registered', 'pro', 'enterprise')),
    api_key VARCHAR(255) UNIQUE,
    active BOOLEAN DEFAULT TRUE,
    rate_limit INTEGER DEFAULT 100,
    last_accessed TIMESTAMP WITH TIME ZONE,
    access_count INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP WITH TIME ZONE
);

-- API keys table for RSS access
CREATE TABLE IF NOT EXISTS api_keys (
    id SERIAL PRIMARY KEY,
    key_hash VARCHAR(255) UNIQUE NOT NULL,
    subscription_id INTEGER REFERENCES rss_subscriptions(id) ON DELETE CASCADE,
    name VARCHAR(255),
    last_used TIMESTAMP WITH TIME ZONE,
    use_count INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    revoked_at TIMESTAMP WITH TIME ZONE
);

-- RSS feed access logs
CREATE TABLE IF NOT EXISTS feed_access_logs (
    id SERIAL PRIMARY KEY,
    subscription_id INTEGER REFERENCES rss_subscriptions(id) ON DELETE CASCADE,
    api_key_id INTEGER REFERENCES api_keys(id) ON DELETE CASCADE,
    ip_address INET,
    user_agent TEXT,
    endpoint VARCHAR(255),
    response_code INTEGER,
    response_time_ms INTEGER,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Part pricing tiers
CREATE TABLE IF NOT EXISTS part_pricing_tiers (
    id SERIAL PRIMARY KEY,
    part_id INTEGER REFERENCES parts(id) ON DELETE CASCADE,
    tier VARCHAR(50) NOT NULL,
    price DECIMAL(10, 2) NOT NULL,
    min_quantity INTEGER DEFAULT 1,
    max_quantity INTEGER,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for better performance
CREATE INDEX idx_parts_sku ON parts(sku);
CREATE INDEX idx_parts_category ON parts(category);
CREATE INDEX idx_parts_manufacturer ON parts(manufacturer);
CREATE INDEX idx_parts_featured ON parts(featured) WHERE featured = TRUE;
CREATE INDEX idx_parts_availability ON parts(availability_status);
CREATE INDEX idx_parts_created_at ON parts(created_at DESC);

-- Full-text search index
CREATE INDEX idx_parts_search ON parts USING gin(
    to_tsvector('english', 
        COALESCE(name, '') || ' ' || 
        COALESCE(description, '') || ' ' || 
        COALESCE(manufacturer, '') || ' ' ||
        COALESCE(category, '')
    )
);

-- GIN index for JSONB specifications
CREATE INDEX idx_parts_specifications ON parts USING gin(specifications);

-- Index for tags array
CREATE INDEX idx_parts_tags ON parts USING gin(tags);

-- RSS subscription indexes
CREATE INDEX idx_rss_subscriptions_user_id ON rss_subscriptions(user_id);
CREATE INDEX idx_rss_subscriptions_api_key ON rss_subscriptions(api_key);
CREATE INDEX idx_rss_subscriptions_tier ON rss_subscriptions(tier);

-- API keys indexes
CREATE INDEX idx_api_keys_subscription_id ON api_keys(subscription_id);
CREATE INDEX idx_api_keys_hash ON api_keys(key_hash);

-- Feed access logs indexes
CREATE INDEX idx_feed_access_logs_subscription_id ON feed_access_logs(subscription_id);
CREATE INDEX idx_feed_access_logs_created_at ON feed_access_logs(created_at DESC);

-- Update trigger for parts table
CREATE OR REPLACE FUNCTION update_parts_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_parts_updated_at
    BEFORE UPDATE ON parts
    FOR EACH ROW
    EXECUTE FUNCTION update_parts_updated_at();

-- Function to get featured parts
CREATE OR REPLACE FUNCTION get_featured_parts(limit_count INTEGER DEFAULT 10)
RETURNS TABLE (
    id INTEGER,
    sku VARCHAR,
    name VARCHAR,
    description TEXT,
    category VARCHAR,
    manufacturer VARCHAR,
    base_price DECIMAL,
    featured_date DATE
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p.id,
        p.sku,
        p.name,
        p.description,
        p.category,
        p.manufacturer,
        p.base_price,
        p.featured_date
    FROM parts p
    WHERE p.featured = TRUE
    ORDER BY p.featured_date DESC NULLS LAST, p.created_at DESC
    LIMIT limit_count;
END;
$$ LANGUAGE plpgsql;

-- Function to search parts
CREATE OR REPLACE FUNCTION search_parts(
    search_query TEXT,
    category_filter VARCHAR DEFAULT NULL,
    manufacturer_filter VARCHAR DEFAULT NULL,
    min_price DECIMAL DEFAULT NULL,
    max_price DECIMAL DEFAULT NULL,
    availability_filter VARCHAR DEFAULT NULL,
    limit_count INTEGER DEFAULT 50,
    offset_count INTEGER DEFAULT 0
)
RETURNS TABLE (
    id INTEGER,
    sku VARCHAR,
    name VARCHAR,
    description TEXT,
    category VARCHAR,
    manufacturer VARCHAR,
    base_price DECIMAL,
    availability_status VARCHAR,
    relevance REAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p.id,
        p.sku,
        p.name,
        p.description,
        p.category,
        p.manufacturer,
        p.base_price,
        p.availability_status,
        ts_rank(
            to_tsvector('english', 
                COALESCE(p.name, '') || ' ' || 
                COALESCE(p.description, '') || ' ' || 
                COALESCE(p.manufacturer, '') || ' ' ||
                COALESCE(p.category, '')
            ),
            plainto_tsquery('english', search_query)
        ) AS relevance
    FROM parts p
    WHERE 
        (search_query IS NULL OR search_query = '' OR
            to_tsvector('english', 
                COALESCE(p.name, '') || ' ' || 
                COALESCE(p.description, '') || ' ' || 
                COALESCE(p.manufacturer, '') || ' ' ||
                COALESCE(p.category, '')
            ) @@ plainto_tsquery('english', search_query)
        )
        AND (category_filter IS NULL OR p.category = category_filter)
        AND (manufacturer_filter IS NULL OR p.manufacturer = manufacturer_filter)
        AND (min_price IS NULL OR p.base_price >= min_price)
        AND (max_price IS NULL OR p.base_price <= max_price)
        AND (availability_filter IS NULL OR p.availability_status = availability_filter)
    ORDER BY relevance DESC, p.created_at DESC
    LIMIT limit_count
    OFFSET offset_count;
END;
$$ LANGUAGE plpgsql;

-- Sample data for testing (remove in production)
INSERT INTO parts (sku, name, description, category, manufacturer, base_price, availability_status, featured, featured_date, tags, specifications)
VALUES 
    ('SENS-TEMP-001', 'Industrial Temperature Sensor', 'High-precision temperature sensor for industrial applications', 'Sensors', 'TechSense Corp', 149.99, 'available', TRUE, CURRENT_DATE, ARRAY['temperature', 'sensor', 'industrial'], '{"range": "-50°C to 200°C", "accuracy": "±0.1°C", "output": "4-20mA"}'),
    ('MOTOR-AC-002', 'AC Induction Motor 5HP', 'Energy-efficient 5HP AC induction motor', 'Motors', 'PowerDrive Industries', 899.99, 'available', TRUE, CURRENT_DATE - INTERVAL '1 day', ARRAY['motor', 'ac', '5hp'], '{"power": "5HP", "voltage": "230/460V", "rpm": "1750", "efficiency": "95%"}'),
    ('VALVE-BALL-003', 'Stainless Steel Ball Valve', '2-inch stainless steel ball valve for high-pressure applications', 'Valves', 'FlowControl Systems', 125.50, 'available', FALSE, NULL, ARRAY['valve', 'stainless steel', '2 inch'], '{"size": "2 inch", "material": "316 SS", "pressure": "1000 PSI", "temperature": "500°F"}'),
    ('PLC-MOD-004', 'Programmable Logic Controller Module', 'Advanced PLC module with Ethernet connectivity', 'Controllers', 'AutomateX', 1299.99, 'limited', TRUE, CURRENT_DATE - INTERVAL '2 days', ARRAY['plc', 'controller', 'ethernet'], '{"inputs": "16 DI", "outputs": "8 DO", "communication": "Ethernet, RS485", "memory": "256KB"}'),
    ('PUMP-CENT-005', 'Centrifugal Water Pump', 'High-flow centrifugal pump for water transfer', 'Pumps', 'HydroFlow Solutions', 549.99, 'available', FALSE, NULL, ARRAY['pump', 'centrifugal', 'water'], '{"flow": "500 GPM", "head": "100 ft", "inlet": "4 inch", "outlet": "3 inch"}');

-- Grant permissions (adjust as needed for your setup)
GRANT SELECT, INSERT, UPDATE ON parts TO partaday_app;
GRANT SELECT, INSERT, UPDATE ON rss_subscriptions TO partaday_app;
GRANT SELECT, INSERT, UPDATE ON api_keys TO partaday_app;
GRANT SELECT, INSERT ON feed_access_logs TO partaday_app;
GRANT SELECT, INSERT, UPDATE ON part_pricing_tiers TO partaday_app;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO partaday_app;