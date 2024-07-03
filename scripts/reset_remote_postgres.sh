#!/bin/bash
# prerequirement: psql must already be installed

PGPASSWORD='postgres' psql -h <your-server-ip> -p 5432 -U postgres -d postgres <<EOF
-- Drop and recreate the event_db
DROP DATABASE IF EXISTS event_db;
CREATE DATABASE event_db;
\c event_db
-- Grant permissions to event_user
GRANT USAGE ON SCHEMA public TO event_user;
GRANT CREATE ON SCHEMA public TO event_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO event_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO event_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO event_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO event_user;

-- Drop and recreate the pool_db
DROP DATABASE IF EXISTS pool_db;
CREATE DATABASE pool_db;
\c pool_db
-- Grant permissions to pool_user
GRANT USAGE ON SCHEMA public TO pool_user;
GRANT CREATE ON SCHEMA public TO pool_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO pool_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO pool_user;

-- Drop and recreate the prover_db
DROP DATABASE IF EXISTS prover_db;
CREATE DATABASE prover_db;
\c prover_db
-- Create state schema and grant permissions to prover_user
CREATE SCHEMA state;
GRANT USAGE ON SCHEMA public TO prover_user;
GRANT CREATE ON SCHEMA public TO prover_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO prover_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO prover_user;
GRANT USAGE ON SCHEMA state TO prover_user;
GRANT CREATE ON SCHEMA state TO prover_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA state GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO prover_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA state GRANT EXECUTE ON FUNCTIONS TO prover_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA state TO prover_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA state TO prover_user;

-- Drop and recreate the state_db
DROP DATABASE IF EXISTS state_db;
CREATE DATABASE state_db;
\c state_db
-- Grant permissions to state_user
GRANT USAGE ON SCHEMA public TO state_user;
GRANT CREATE ON SCHEMA public TO state_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO state_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO state_user;

-- Drop and recreate the agglayer_db
DROP DATABASE IF EXISTS agglayer_db;
CREATE DATABASE agglayer_db;
\c agglayer_db
-- Grant permissions to agglayer_user
GRANT USAGE ON SCHEMA public TO agglayer_user;
GRANT CREATE ON SCHEMA public TO agglayer_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO agglayer_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO agglayer_user;

-- Drop and recreate the bridge_db
DROP DATABASE IF EXISTS bridge_db;
CREATE DATABASE bridge_db;
\c bridge_db
-- Grant permissions to bridge_user
GRANT USAGE ON SCHEMA public TO bridge_user;
GRANT CREATE ON SCHEMA public TO bridge_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO bridge_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO bridge_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO bridge_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO bridge_user;

-- Drop and recreate the dac_db
DROP DATABASE IF EXISTS dac_db;
CREATE DATABASE dac_db;
\c dac_db
-- Grant permissions to dac_user
GRANT USAGE ON SCHEMA public TO dac_user;
GRANT CREATE ON SCHEMA public TO dac_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO dac_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO dac_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO dac_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO dac_user;

EOF
