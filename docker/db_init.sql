-- Initialize the ModestInventary database schema

CREATE TABLE IF NOT EXISTS items (
    id       SERIAL PRIMARY KEY,
    name     VARCHAR(255) NOT NULL,
    quantity INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Seed data for development
INSERT INTO items (name, quantity) VALUES
    ('Widget Alpha', 42),
    ('Widget Beta',  17),
    ('Widget Gamma', 99)
ON CONFLICT DO NOTHING;
