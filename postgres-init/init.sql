-- Initialize databases for Beer Tracker application
-- This script runs once when the PostgreSQL container is first created.
-- PostgreSQL does not support CREATE DATABASE IF NOT EXISTS, so we use
-- the DO block pattern to avoid errors on re-runs.

SELECT 'CREATE DATABASE auth_db'
  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'auth_db')\gexec

SELECT 'CREATE DATABASE tracking_db'
  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'tracking_db')\gexec

SELECT 'CREATE DATABASE notifications_db'
  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'notifications_db')\gexec

SELECT 'CREATE DATABASE statistics_db'
  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'statistics_db')\gexec
