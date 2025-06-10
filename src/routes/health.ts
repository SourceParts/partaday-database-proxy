import express from 'express'
import dbPool from '../database/connection'

const router = express.Router()

// Basic health check
router.get('/', async (req, res) => {
  const startTime = Date.now()
  
  try {
    // Check database connectivity
    const dbHealth = await dbPool.healthCheck()
    
    const response = {
      status: dbHealth.status === 'healthy' ? 'healthy' : 'unhealthy',
      timestamp: new Date().toISOString(),
      uptime: process.uptime(),
      memory: {
        used: Math.round(process.memoryUsage().heapUsed / 1024 / 1024),
        total: Math.round(process.memoryUsage().heapTotal / 1024 / 1024),
        external: Math.round(process.memoryUsage().external / 1024 / 1024)
      },
      database: {
        status: dbHealth.status,
        latency: dbHealth.latency,
        connections: dbHealth.poolStats
      },
      environment: process.env.NODE_ENV || 'development',
      version: '1.0.0',
      responseTime: Date.now() - startTime
    }

    // Return appropriate status code
    const statusCode = dbHealth.status === 'healthy' ? 200 : 503
    res.status(statusCode).json(response)

  } catch (error) {
    console.error('❌ Health check failed:', error)
    
    res.status(503).json({
      status: 'unhealthy',
      timestamp: new Date().toISOString(),
      error: error instanceof Error ? error.message : 'Unknown error',
      uptime: process.uptime(),
      memory: {
        used: Math.round(process.memoryUsage().heapUsed / 1024 / 1024),
        total: Math.round(process.memoryUsage().heapTotal / 1024 / 1024)
      },
      database: {
        status: 'unhealthy',
        error: 'Database connection failed'
      },
      environment: process.env.NODE_ENV || 'development',
      version: '1.0.0',
      responseTime: Date.now() - startTime
    })
  }
})

// Detailed health check with more comprehensive testing
router.get('/detailed', async (req, res) => {
  const startTime = Date.now()
  const checks: any = {}

  try {
    // Database connectivity check
    console.log('🔍 Running detailed health checks...')
    
    checks.database = await dbPool.healthCheck()
    
    // Memory check
    const memUsage = process.memoryUsage()
    checks.memory = {
      status: memUsage.heapUsed < 500 * 1024 * 1024 ? 'healthy' : 'warning', // 500MB threshold
      used: Math.round(memUsage.heapUsed / 1024 / 1024),
      total: Math.round(memUsage.heapTotal / 1024 / 1024),
      external: Math.round(memUsage.external / 1024 / 1024)
    }

    // Disk space check (if available)
    checks.disk = {
      status: 'healthy',
      message: 'Disk space check not implemented for serverless environment'
    }

    // Environment variables check
    const requiredEnvVars = [
      'DATABASE_URL',
      'PROXY_API_KEY',
      'PROXY_SECRET_KEY'
    ]
    
    const missingEnvVars = requiredEnvVars.filter(envVar => !process.env[envVar])
    checks.environment = {
      status: missingEnvVars.length === 0 ? 'healthy' : 'unhealthy',
      missing: missingEnvVars,
      nodeVersion: process.version,
      platform: process.platform
    }

    // Overall status
    const allHealthy = Object.values(checks).every(
      (check: any) => check.status === 'healthy'
    )

    const response = {
      status: allHealthy ? 'healthy' : 'unhealthy',
      timestamp: new Date().toISOString(),
      uptime: process.uptime(),
      checks,
      version: '1.0.0',
      responseTime: Date.now() - startTime
    }

    const statusCode = allHealthy ? 200 : 503
    res.status(statusCode).json(response)

  } catch (error) {
    console.error('❌ Detailed health check failed:', error)
    
    res.status(503).json({
      status: 'unhealthy',
      timestamp: new Date().toISOString(),
      error: error instanceof Error ? error.message : 'Unknown error',
      uptime: process.uptime(),
      checks,
      version: '1.0.0',
      responseTime: Date.now() - startTime
    })
  }
})

// Simple readiness probe
router.get('/ready', async (req, res) => {
  try {
    // Quick database ping
    await dbPool.healthCheck()
    res.status(200).json({ status: 'ready' })
  } catch {
    res.status(503).json({ status: 'not ready' })
  }
})

// Simple liveness probe
router.get('/live', (req, res) => {
  res.status(200).json({ 
    status: 'alive',
    timestamp: new Date().toISOString(),
    uptime: process.uptime()
  })
})

export default router 
