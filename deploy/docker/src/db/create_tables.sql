CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255),
    description TEXT,
    price DECIMAL(10, 2)
);

CREATE TABLE orders (
    id UUID PRIMARY KEY,
    created_on TIMESTAMP,
    customer_id VARCHAR(255),
    total_amount DECIMAL(10, 2)
);