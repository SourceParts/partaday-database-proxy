import express, { Request, Response } from 'express'
import { asyncHandler } from '../middleware/errorHandler'
import dbPool from '../database/connection'
import { 
  adminLoginSchema,
  AdminLogin
} from '../schemas/validation-schemas'
import { z } from 'zod'
import bcrypt from 'bcrypt'
import jwt from 'jsonwebtoken'

const router = express.Router()

// Admin login
router.post('/login', asyncHandler(async (req: Request, res: Response) => {
  try {
    console.log('🔐 Admin login attempt:', req.body.email)
    
    // Validate request body
    const validatedData = adminLoginSchema.parse(req.body)

    // Query for admin user
    const query = `
      SELECT 
        id,
        email,
        password_hash,
        is_active,
        last_login
      FROM admin_users
      WHERE email = $1
    `
    const result = await dbPool.query(query, [validatedData.email])

    if (result.rows.length === 0) {
      res.status(401).json({
        success: false,
        message: 'Invalid credentials'
      })
      return
    }

    const admin = result.rows[0]

    // Check if admin is active
    if (!admin.is_active) {
      res.status(401).json({
        success: false,
        message: 'Account is disabled'
      })
      return
    }

    // Verify password
    const isPasswordValid = await bcrypt.compare(validatedData.password, admin.password_hash)
    
    if (!isPasswordValid) {
      res.status(401).json({
        success: false,
        message: 'Invalid credentials'
      })
      return
    }

    // Update last login
    await dbPool.query(
      'UPDATE admin_users SET last_login = NOW() WHERE id = $1',
      [admin.id]
    )

    // Generate JWT token
    const token = jwt.sign(
      { 
        id: admin.id,
        email: admin.email,
        role: 'admin'
      },
      process.env.JWT_SECRET || 'your-secret-key',
      { expiresIn: '24h' }
    )

    // Log the login
    await dbPool.query(`
      INSERT INTO audit_logs (
        table_name, record_id, action, changed_by, changes
      ) VALUES ('admin_users', $1, 'login', $2, $3)
    `, [
      admin.id,
      admin.email,
      JSON.stringify({ ip: req.ip, userAgent: req.headers['user-agent'] })
    ])

    res.json({
      success: true,
      message: 'Login successful',
      data: {
        token,
        admin: {
          id: admin.id,
          email: admin.email
        }
      }
    })

  } catch (error) {
    console.error('❌ Error during admin login:', error)
    
    if (error instanceof z.ZodError) {
      res.status(400).json({
        success: false,
        message: 'Validation error',
        errors: error.errors
      })
    } else {
      res.status(500).json({
        success: false,
        message: 'Failed to process login'
      })
    }
  }
}))

// Admin logout (optional - mainly for audit logging)
router.post('/logout', asyncHandler(async (req: Request, res: Response) => {
  try {
    // In a real implementation, you might want to:
    // 1. Invalidate the token (if using a token blacklist)
    // 2. Clear any server-side sessions
    // 3. Log the logout event

    // For now, we'll just log the logout
    const authHeader = req.headers.authorization
    if (authHeader && authHeader.startsWith('Bearer ')) {
      const token = authHeader.substring(7)
      
      try {
        const decoded = jwt.verify(
          token, 
          process.env.JWT_SECRET || 'your-secret-key'
        ) as any

        // Log the logout
        await dbPool.query(`
          INSERT INTO audit_logs (
            table_name, record_id, action, changed_by, changes
          ) VALUES ('admin_users', $1, 'logout', $2, $3)
        `, [
          decoded.id,
          decoded.email,
          JSON.stringify({ timestamp: new Date().toISOString() })
        ])
      } catch (err) {
        // Token might be invalid, but we still return success
        console.log('Invalid token during logout')
      }
    }

    res.json({
      success: true,
      message: 'Logout successful'
    })

  } catch (error) {
    console.error('❌ Error during admin logout:', error)
    res.status(500).json({
      success: false,
      message: 'Failed to process logout'
    })
  }
}))

// Verify admin token
router.get('/verify', asyncHandler(async (req: Request, res: Response) => {
  try {
    const authHeader = req.headers.authorization
    
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      res.status(401).json({
        success: false,
        message: 'No token provided'
      })
      return
    }

    const token = authHeader.substring(7)
    
    try {
      const decoded = jwt.verify(
        token, 
        process.env.JWT_SECRET || 'your-secret-key'
      ) as any

      // Optionally check if admin still exists and is active
      const query = `
        SELECT id, email, is_active
        FROM admin_users
        WHERE id = $1 AND is_active = true
      `
      const result = await dbPool.query(query, [decoded.id])

      if (result.rows.length === 0) {
        res.status(401).json({
          success: false,
          message: 'Invalid or inactive admin'
        })
        return
      }

      res.json({
        success: true,
        message: 'Token is valid',
        data: {
          admin: {
            id: decoded.id,
            email: decoded.email,
            role: decoded.role
          }
        }
      })

    } catch (err) {
      res.status(401).json({
        success: false,
        message: 'Invalid token'
      })
    }

  } catch (error) {
    console.error('❌ Error verifying admin token:', error)
    res.status(500).json({
      success: false,
      message: 'Failed to verify token'
    })
  }
}))

// Create new admin (only super admins can do this)
router.post('/create', asyncHandler(async (req: Request, res: Response) => {
  try {
    // This should be protected by auth middleware
    // and only accessible to super admins
    
    const { email, password } = req.body

    // Validate input
    if (!email || !password || password.length < 8) {
      res.status(400).json({
        success: false,
        message: 'Invalid email or password (min 8 characters)'
      })
      return
    }

    // Check if admin already exists
    const existingQuery = 'SELECT id FROM admin_users WHERE email = $1'
    const existing = await dbPool.query(existingQuery, [email])
    
    if (existing.rows.length > 0) {
      res.status(409).json({
        success: false,
        message: 'Admin with this email already exists'
      })
      return
    }

    // Hash password
    const saltRounds = 10
    const passwordHash = await bcrypt.hash(password, saltRounds)

    // Create admin
    const createQuery = `
      INSERT INTO admin_users (email, password_hash, is_active)
      VALUES ($1, $2, true)
      RETURNING id, email, created_at
    `
    const result = await dbPool.query(createQuery, [email, passwordHash])

    res.json({
      success: true,
      message: 'Admin created successfully',
      data: result.rows[0]
    })

  } catch (error) {
    console.error('❌ Error creating admin:', error)
    res.status(500).json({
      success: false,
      message: 'Failed to create admin'
    })
  }
}))

export default router