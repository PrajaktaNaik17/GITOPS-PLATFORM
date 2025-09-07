// app.js - Simple Node.js application for our GitOps demo
const express = require('express');
const { Pool } = require('pg');
const path = require('path');

const app = express();
const port = process.env.PORT || 3000;

// Database connection - FIXED: Added SSL configuration for AWS RDS
const pool = new Pool({
    host: dbHost,
    port: parseInt(dbPort),
    database: process.env.DB_NAME || 'gitopsdb',
    user: process.env.DB_USER || 'postgres',
    password: process.env.DB_PASSWORD || 'password',
    ssl: true  // Simple boolean, not an object
  });

app.use(express.json());
app.use(express.static('public'));

// Health check endpoint (critical for blue-green deployments)
app.get('/health', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.status(200).json({ 
      status: 'healthy', 
      version: process.env.APP_VERSION || '1.0.0',
      timestamp: new Date().toISOString(),
      environment: process.env.ENVIRONMENT || 'development'
    });
  } catch (error) {
    res.status(500).json({ 
      status: 'unhealthy', 
      error: error.message 
    });
  }
});

// Version endpoint (useful for verifying deployments)
app.get('/version', (req, res) => {
  res.json({
    version: process.env.APP_VERSION || '1.0.0',
    environment: process.env.ENVIRONMENT || 'development',
    deployment_id: process.env.DEPLOYMENT_ID || 'local'
  });
});

// Simple data endpoint
app.get('/api/deployments', async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT id, version, environment, deployed_at, status 
      FROM deployments 
      ORDER BY deployed_at DESC 
      LIMIT 10
    `);
    res.json(result.rows);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Record deployment
app.post('/api/deployments', async (req, res) => {
  try {
    const { version, environment } = req.body;
    const result = await pool.query(`
      INSERT INTO deployments (version, environment, deployed_at, status)
      VALUES ($1, $2, NOW(), 'active')
      RETURNING *
    `, [version, environment]);
    res.json(result.rows[0]);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Serve frontend
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// Initialize database
async function initializeDatabase() {
  try {
    console.log(`Attempting to connect to database at ${dbHost}:${dbPort} with SSL`);
    await pool.query(`
      CREATE TABLE IF NOT EXISTS deployments (
        id SERIAL PRIMARY KEY,
        version VARCHAR(50) NOT NULL,
        environment VARCHAR(20) NOT NULL,
        deployed_at TIMESTAMP DEFAULT NOW(),
        status VARCHAR(20) DEFAULT 'active'
      )
    `);
    console.log('Database initialized successfully');
  } catch (error) {
    console.error('Database initialization failed:', error);
  }
}

app.listen(port, () => {
  console.log(`GitOps Demo App running on port ${port}`);
  console.log(`Version: ${process.env.APP_VERSION || '1.0.0'}`);
  console.log(`Environment: ${process.env.ENVIRONMENT || 'development'}`);
  console.log(`Database Host: ${dbHost}:${dbPort} (SSL: enabled)`);
  initializeDatabase();
});

module.exports = app;