CREATE TABLE IF NOT EXISTS deployments (
    id SERIAL PRIMARY KEY,
    version VARCHAR(50) NOT NULL,
    environment VARCHAR(20) NOT NULL,
    deployed_at TIMESTAMP DEFAULT NOW(),
    status VARCHAR(20) DEFAULT 'active',
    rollback_version VARCHAR(50),
    deployment_id VARCHAR(100) UNIQUE,
    created_by VARCHAR(100) DEFAULT 'system'
);

-- Create backup_logs table
CREATE TABLE IF NOT EXISTS backup_logs (
    id SERIAL PRIMARY KEY,
    backup_type VARCHAR(50) NOT NULL,
    backup_location VARCHAR(500),
    created_at TIMESTAMP DEFAULT NOW(),
    status VARCHAR(20) DEFAULT 'completed',
    size_mb INTEGER,
    retention_days INTEGER DEFAULT 30
);

-- Create deployment_metrics table
CREATE TABLE IF NOT EXISTS deployment_metrics (
    id SERIAL PRIMARY KEY,
    deployment_id VARCHAR(100),
    metric_name VARCHAR(100),
    metric_value DECIMAL,
    recorded_at TIMESTAMP DEFAULT NOW()
);

-- Insert sample data
INSERT INTO deployments (version, environment, status, deployment_id) VALUES
    ('0.9.0', 'production', 'active', 'deploy-001'),
    ('0.8.5', 'production', 'rolled-back', 'deploy-002'),
    ('0.8.0', 'staging', 'active', 'deploy-003');

INSERT INTO backup_logs (backup_type, backup_location, size_mb) VALUES
    ('database', 's3://gitops-backups/db-2024-01-15.sql', 245),
    ('application', 's3://gitops-backups/app-2024-01-15.tar.gz', 156),
    ('full-system', 's3://gitops-backups/full-2024-01-14.tar.gz', 1024);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_deployments_environment ON deployments(environment);
CREATE INDEX IF NOT EXISTS idx_deployments_deployed_at ON deployments(deployed_at);
CREATE INDEX IF NOT EXISTS idx_backup_logs_created_at ON backup_logs(created_at);
