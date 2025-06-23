import express, { Request, Response } from 'express'
import { asyncHandler } from '../middleware/errorHandler'
import dbPool from '../database/connection'
import { 
  quoteRequestSchema, 
  quoteFiltersSchema, 
  updateQuoteStatusSchema,
  QuoteRequest,
  QuoteFilters,
  UpdateQuoteStatus
} from '../schemas/validation-schemas'
import { z } from 'zod'

const router = express.Router()

// Create quote request
router.post('/', asyncHandler(async (req: Request, res: Response) => {
  try {
    console.log('📝 Creating quote request:', req.body)

    // Validate request body
    const validatedData = quoteRequestSchema.parse(req.body)
    const referenceId = `QR-${Date.now()}`

    // Begin transaction
    const client = await dbPool.getPool().connect()
    try {
      await client.query('BEGIN')

      // Create or get user
      const userQuery = `
        INSERT INTO users (email, first_name, last_name, company, phone)
        VALUES ($1, $2, $3, $4, $5)
        ON CONFLICT (email) DO UPDATE SET
          first_name = EXCLUDED.first_name,
          last_name = EXCLUDED.last_name,
          company = EXCLUDED.company,
          phone = EXCLUDED.phone,
          updated_at = NOW()
        RETURNING id
      `
      const userResult = await client.query(userQuery, [
        validatedData.email,
        validatedData.firstName,
        validatedData.lastName,
        validatedData.company || null,
        validatedData.phone || null
      ])

      // Create quote request
      const quoteQuery = `
        INSERT INTO quote_requests (
          user_id, part_type, part_number, manufacturer, quantity,
          description, urgency, budget_range, additional_notes,
          email_updates, newsletter, reference_id, source,
          user_agent, ip_address, status
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, 'submitted')
        RETURNING id, reference_id, status, created_at
      `
      const quoteResult = await client.query(quoteQuery, [
        userResult.rows[0].id,
        validatedData.partType,
        validatedData.partNumber || null,
        validatedData.manufacturer || null,
        validatedData.quantity,
        validatedData.description || null,
        validatedData.urgency,
        validatedData.budget || null,
        validatedData.additionalNotes || null,
        validatedData.emailUpdates,
        validatedData.newsletter,
        referenceId,
        validatedData.source || null,
        validatedData.userAgent || null,
        validatedData.ipAddress || null
      ])

      await client.query('COMMIT')

      const result = quoteResult.rows[0]
      res.json({
        success: true,
        message: 'Quote request created successfully',
        data: {
          id: result.reference_id,
          status: result.status,
          created_at: result.created_at
        }
      })

    } catch (error) {
      await client.query('ROLLBACK')
      throw error
    } finally {
      client.release()
    }

  } catch (error) {
    console.error('❌ Error creating quote request:', error)
    
    if (error instanceof z.ZodError) {
      res.status(400).json({
        success: false,
        message: 'Validation error',
        errors: error.errors
      })
    } else {
      res.status(500).json({
        success: false,
        message: 'Failed to create quote request'
      })
    }
  }
}))

// Get quote requests (for admin)
router.get('/', asyncHandler(async (req: Request, res: Response) => {
  try {
    // Validate query parameters
    const filters = quoteFiltersSchema.parse(req.query)
    const offset = (filters.page - 1) * filters.limit

    // Build WHERE clause
    const whereClauses: string[] = []
    const params: any[] = []
    let paramCount = 1

    if (filters.status) {
      whereClauses.push(`qr.status = $${paramCount}`)
      params.push(filters.status)
      paramCount++
    }

    if (filters.urgency) {
      whereClauses.push(`qr.urgency = $${paramCount}`)
      params.push(filters.urgency)
      paramCount++
    }

    if (filters.startDate) {
      whereClauses.push(`qr.created_at >= $${paramCount}`)
      params.push(filters.startDate)
      paramCount++
    }

    if (filters.endDate) {
      whereClauses.push(`qr.created_at <= $${paramCount}`)
      params.push(filters.endDate)
      paramCount++
    }

    const whereClause = whereClauses.length > 0 ? `WHERE ${whereClauses.join(' AND ')}` : ''

    // Get total count
    const countQuery = `
      SELECT COUNT(*) as total
      FROM quote_requests qr
      ${whereClause}
    `
    const countResult = await dbPool.query(countQuery, params)
    const total = parseInt(countResult.rows[0].total)

    // Get paginated results
    params.push(filters.limit, offset)
    const query = `
      SELECT 
        qr.id,
        qr.reference_id,
        qr.part_type,
        qr.part_number,
        qr.manufacturer,
        qr.quantity,
        qr.description,
        qr.urgency,
        qr.budget_range,
        qr.additional_notes,
        qr.email_updates,
        qr.newsletter,
        qr.status,
        qr.quoted_price,
        qr.quote_valid_until,
        qr.admin_notes,
        qr.source,
        qr.created_at,
        qr.updated_at,
        u.email,
        u.first_name,
        u.last_name,
        u.company,
        u.phone
      FROM quote_requests qr
      JOIN users u ON qr.user_id = u.id
      ${whereClause}
      ORDER BY qr.created_at DESC
      LIMIT $${paramCount} OFFSET $${paramCount + 1}
    `
    const result = await dbPool.query(query, params)

    res.json({
      success: true,
      data: result.rows,
      pagination: {
        page: filters.page,
        limit: filters.limit,
        total,
        totalPages: Math.ceil(total / filters.limit)
      }
    })

  } catch (error) {
    console.error('❌ Error fetching quote requests:', error)
    
    if (error instanceof z.ZodError) {
      res.status(400).json({
        success: false,
        message: 'Validation error',
        errors: error.errors
      })
    } else {
      res.status(500).json({
        success: false,
        message: 'Failed to fetch quote requests'
      })
    }
  }
}))

// Get quote by ID
router.get('/:id', asyncHandler(async (req: Request, res: Response) => {
  try {
    const { id } = req.params

    const query = `
      SELECT 
        qr.id,
        qr.reference_id,
        qr.part_type,
        qr.part_number,
        qr.manufacturer,
        qr.quantity,
        qr.description,
        qr.urgency,
        qr.budget_range,
        qr.additional_notes,
        qr.email_updates,
        qr.newsletter,
        qr.status,
        qr.quoted_price,
        qr.quote_valid_until,
        qr.admin_notes,
        qr.source,
        qr.user_agent,
        qr.ip_address,
        qr.created_at,
        qr.updated_at,
        u.email,
        u.first_name,
        u.last_name,
        u.company,
        u.phone
      FROM quote_requests qr
      JOIN users u ON qr.user_id = u.id
      WHERE qr.reference_id = $1
    `
    const result = await dbPool.query(query, [id])

    if (result.rows.length === 0) {
      res.status(404).json({
        success: false,
        message: 'Quote request not found'
      })
      return
    }

    res.json({
      success: true,
      data: result.rows[0]
    })

  } catch (error) {
    console.error('❌ Error fetching quote:', error)
    res.status(500).json({
      success: false,
      message: 'Failed to fetch quote'
    })
  }
}))

// Update quote status (for admin)
router.patch('/:id', asyncHandler(async (req: Request, res: Response) => {
  try {
    const { id } = req.params
    
    // Validate request body
    const validatedData = updateQuoteStatusSchema.parse(req.body)

    // Build update query
    const setClauses: string[] = ['status = $2', 'updated_at = NOW()']
    const params: any[] = [id, validatedData.status]
    let paramCount = 3

    if (validatedData.quotedPrice !== undefined) {
      setClauses.push(`quoted_price = $${paramCount}`)
      params.push(validatedData.quotedPrice)
      paramCount++
    }

    if (validatedData.quoteValidUntil !== undefined) {
      setClauses.push(`quote_valid_until = $${paramCount}`)
      params.push(validatedData.quoteValidUntil)
      paramCount++
    }

    if (validatedData.adminNotes !== undefined) {
      setClauses.push(`admin_notes = $${paramCount}`)
      params.push(validatedData.adminNotes)
      paramCount++
    }

    const updateQuery = `
      UPDATE quote_requests
      SET ${setClauses.join(', ')}
      WHERE reference_id = $1
      RETURNING id, reference_id, status, updated_at
    `

    const result = await dbPool.query(updateQuery, params)

    if (result.rows.length === 0) {
      res.status(404).json({
        success: false,
        message: 'Quote request not found'
      })
      return
    }

    // Log the update in audit table
    await dbPool.query(`
      INSERT INTO audit_logs (
        table_name, record_id, action, changed_by, changes
      ) VALUES ('quote_requests', $1, 'update', $2, $3)
    `, [
      result.rows[0].id,
      'admin', // This should come from authenticated user
      JSON.stringify({ status: validatedData.status, ...validatedData })
    ])

    res.json({
      success: true,
      message: 'Quote request updated successfully',
      data: result.rows[0]
    })

  } catch (error) {
    console.error('❌ Error updating quote:', error)
    
    if (error instanceof z.ZodError) {
      res.status(400).json({
        success: false,
        message: 'Validation error',
        errors: error.errors
      })
    } else {
      res.status(500).json({
        success: false,
        message: 'Failed to update quote'
      })
    }
  }
}))

export default router 
