-- Migration: Featured Parts System
-- Description: Add support for scheduling featured parts by date

-- Create a featured_parts table to track which parts are featured on specific dates
CREATE TABLE IF NOT EXISTS featured_parts (
    id SERIAL PRIMARY KEY,
    part_id INTEGER NOT NULL REFERENCES parts(id) ON DELETE CASCADE,
    featured_date DATE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(featured_date) -- Only one featured part per day
);

-- Create index for fast lookups by date
CREATE INDEX idx_featured_parts_date ON featured_parts(featured_date);

-- Create a function to get or set today's featured part
CREATE OR REPLACE FUNCTION get_or_set_todays_featured_part()
RETURNS INTEGER AS $$
DECLARE
    today_date DATE := CURRENT_DATE;
    part_id_result INTEGER;
BEGIN
    -- Check if we already have a featured part for today
    SELECT part_id INTO part_id_result
    FROM featured_parts
    WHERE featured_date = today_date;
    
    -- If we found one, return it
    IF FOUND THEN
        RETURN part_id_result;
    END IF;
    
    -- Otherwise, select a random part that hasn't been featured recently
    SELECT id INTO part_id_result
    FROM parts
    WHERE availability_status != 'discontinued'
        AND id NOT IN (
            -- Exclude parts featured in the last 30 days
            SELECT part_id 
            FROM featured_parts 
            WHERE featured_date > today_date - INTERVAL '30 days'
        )
    ORDER BY RANDOM()
    LIMIT 1;
    
    -- If we found a part, insert it as today's featured part
    IF part_id_result IS NOT NULL THEN
        INSERT INTO featured_parts (part_id, featured_date)
        VALUES (part_id_result, today_date);
    END IF;
    
    RETURN part_id_result;
END;
$$ LANGUAGE plpgsql;

-- Update trigger for updated_at
CREATE TRIGGER update_featured_parts_updated_at BEFORE UPDATE ON featured_parts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Insert some sample featured parts for testing (optional)
-- You can comment this out if you don't want sample data
DO $$
BEGIN
    -- Only insert if parts table has data and featured_parts is empty
    IF EXISTS (SELECT 1 FROM parts LIMIT 1) AND NOT EXISTS (SELECT 1 FROM featured_parts LIMIT 1) THEN
        -- Insert today's featured part
        INSERT INTO featured_parts (part_id, featured_date)
        SELECT id, CURRENT_DATE
        FROM parts
        WHERE availability_status != 'discontinued'
        ORDER BY RANDOM()
        LIMIT 1;
        
        -- Insert yesterday's featured part
        INSERT INTO featured_parts (part_id, featured_date)
        SELECT id, CURRENT_DATE - INTERVAL '1 day'
        FROM parts
        WHERE availability_status != 'discontinued'
            AND id NOT IN (SELECT part_id FROM featured_parts)
        ORDER BY RANDOM()
        LIMIT 1;
    END IF;
END $$;

-- Add comment
COMMENT ON TABLE featured_parts IS 'Tracks which parts are featured on specific dates for the daily part feature';
COMMENT ON FUNCTION get_or_set_todays_featured_part() IS 'Gets today''s featured part or randomly selects one if not set';