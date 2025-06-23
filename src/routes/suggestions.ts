import express, { Request, Response } from 'express'
import { asyncHandler } from '../middleware/errorHandler'
import dbPool from '../database/connection'
import { 
  partSuggestionSchema, 
  suggestionFiltersSchema, 
  updateSuggestionStatusSchema,
  PartSuggestion,
  SuggestionFilters,
  UpdateSuggestionStatus
} from '../schemas/validation-schemas'
import { z } from 'zod'

const router = express.Router()

// Create part suggestion
router.post('/', asyncHandler(async (req: Request, res: Response) => {
  try {
    console.log('💡 Creating part suggestion:', req.body)
    
    // Validate request body
    const validatedData = partSuggestionSchema.parse(req.body)
    const referenceId = `PS-${Date.now()}`

    // Begin transaction
    const client = await dbPool.getPool().connect()
    try {
      await client.query('BEGIN')

      // Create or get user
      const userQuery = `
        INSERT INTO users (email, first_name, last_name, company)
        VALUES ($1, $2, $3, $4)
        ON CONFLICT (email) DO UPDATE SET
          first_name = EXCLUDED.first_name,
          last_name = EXCLUDED.last_name,
          company = EXCLUDED.company,
          updated_at = NOW()
        RETURNING id
      `
      const userResult = await client.query(userQuery, [
        validatedData.email,
        validatedData.firstName,
        validatedData.lastName,
        validatedData.company || null
      ])

      // Create part suggestion
      const suggestionQuery = `
        INSERT INTO part_suggestions (
          user_id, part_name, part_number, manufacturer, category,
          description, why_important, availability_info,
          additional_notes, reference_id, source, user_agent,
          ip_address, status
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, 'submitted')
        RETURNING id, reference_id, status, created_at
      `
      const suggestionResult = await client.query(suggestionQuery, [
        userResult.rows[0].id,
        validatedData.partName,
        validatedData.partNumber || null,
        validatedData.manufacturer || null,
        validatedData.category || null,
        validatedData.description || null,
        validatedData.whyImportant || null,
        validatedData.availabilityInfo || null,
        validatedData.additionalNotes || null,
        referenceId,
        validatedData.source || null,
        validatedData.userAgent || null,
        validatedData.ipAddress || null
      ])

      await client.query('COMMIT')

      const result = suggestionResult.rows[0]
      res.json({
        success: true,
        message: 'Part suggestion submitted successfully',
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
    console.error('❌ Error creating part suggestion:', error)
    
    if (error instanceof z.ZodError) {
      res.status(400).json({
        success: false,
        message: 'Validation error',
        errors: error.errors
      })
    } else {
      res.status(500).json({
        success: false,
        message: 'Failed to submit part suggestion'
      })
    }
  }
}))

// Get part suggestions (for admin)
router.get('/', asyncHandler(async (req: Request, res: Response) => {
  try {
    // Validate query parameters
    const filters = suggestionFiltersSchema.parse(req.query)
    const offset = (filters.page - 1) * filters.limit

    // Build WHERE clause
    const whereClauses: string[] = []
    const params: any[] = []
    let paramCount = 1

    if (filters.status) {
      whereClauses.push(`ps.status = $${paramCount}`)
      params.push(filters.status)
      paramCount++
    }

    if (filters.category) {
      whereClauses.push(`ps.category = $${paramCount}`)
      params.push(filters.category)
      paramCount++
    }

    if (filters.startDate) {
      whereClauses.push(`ps.created_at >= $${paramCount}`)
      params.push(filters.startDate)
      paramCount++
    }

    if (filters.endDate) {
      whereClauses.push(`ps.created_at <= $${paramCount}`)
      params.push(filters.endDate)
      paramCount++
    }

    const whereClause = whereClauses.length > 0 ? `WHERE ${whereClauses.join(' AND ')}` : ''

    // Get total count
    const countQuery = `
      SELECT COUNT(*) as total
      FROM part_suggestions ps
      ${whereClause}
    `
    const countResult = await dbPool.query(countQuery, params)
    const total = parseInt(countResult.rows[0].total)

    // Get paginated results
    params.push(filters.limit, offset)
    const query = `
      SELECT 
        ps.id,
        ps.reference_id,
        ps.part_name,
        ps.part_number,
        ps.manufacturer,
        ps.category,
        ps.description,
        ps.why_important,
        ps.availability_info,
        ps.additional_notes,
        ps.status,
        ps.admin_notes,
        ps.source,
        ps.created_at,
        ps.updated_at,
        u.email,
        u.first_name,
        u.last_name,
        u.company
      FROM part_suggestions ps
      JOIN users u ON ps.user_id = u.id
      ${whereClause}
      ORDER BY ps.created_at DESC
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
    console.error('❌ Error fetching part suggestions:', error)
    
    if (error instanceof z.ZodError) {
      res.status(400).json({
        success: false,
        message: 'Validation error',
        errors: error.errors
      })
    } else {
      res.status(500).json({
        success: false,
        message: 'Failed to fetch part suggestions'
      })
    }
  }
}))

// Get suggestion by ID
router.get('/:id', asyncHandler(async (req: Request, res: Response) => {
  try {
    const { id } = req.params

    const query = `
      SELECT 
        ps.id,
        ps.reference_id,
        ps.part_name,
        ps.part_number,
        ps.manufacturer,
        ps.category,
        ps.description,
        ps.why_important,
        ps.availability_info,
        ps.additional_notes,
        ps.status,
        ps.admin_notes,
        ps.source,
        ps.user_agent,
        ps.ip_address,
        ps.created_at,
        ps.updated_at,
        u.email,
        u.first_name,
        u.last_name,
        u.company
      FROM part_suggestions ps
      JOIN users u ON ps.user_id = u.id
      WHERE ps.reference_id = $1
    `
    const result = await dbPool.query(query, [id])

    if (result.rows.length === 0) {
      res.status(404).json({
        success: false,
        message: 'Part suggestion not found'
      })
      return
    }

    res.json({
      success: true,
      data: result.rows[0]
    })

  } catch (error) {
    console.error('❌ Error fetching suggestion:', error)
    res.status(500).json({
      success: false,
      message: 'Failed to fetch suggestion'
    })
  }
}))

// Update suggestion status (for admin)
router.patch('/:id', asyncHandler(async (req: Request, res: Response) => {
  try {
    const { id } = req.params
    
    // Validate request body
    const validatedData = updateSuggestionStatusSchema.parse(req.body)

    // Build update query
    const setClauses: string[] = ['status = $2', 'updated_at = NOW()']
    const params: any[] = [id, validatedData.status]
    let paramCount = 3

    if (validatedData.adminNotes !== undefined) {
      setClauses.push(`admin_notes = $${paramCount}`)
      params.push(validatedData.adminNotes)
      paramCount++
    }

    const updateQuery = `
      UPDATE part_suggestions
      SET ${setClauses.join(', ')}
      WHERE reference_id = $1
      RETURNING id, reference_id, status, updated_at
    `

    const result = await dbPool.query(updateQuery, params)

    if (result.rows.length === 0) {
      res.status(404).json({
        success: false,
        message: 'Part suggestion not found'
      })
      return
    }

    // Log the update in audit table
    await dbPool.query(`
      INSERT INTO audit_logs (
        table_name, record_id, action, changed_by, changes
      ) VALUES ('part_suggestions', $1, 'update', $2, $3)
    `, [
      result.rows[0].id,
      'admin', // This should come from authenticated user
      JSON.stringify({ status: validatedData.status, ...validatedData })
    ])

    res.json({
      success: true,
      message: 'Suggestion status updated successfully',
      data: result.rows[0]
    })

  } catch (error) {
    console.error('❌ Error updating suggestion status:', error)
    
    if (error instanceof z.ZodError) {
      res.status(400).json({
        success: false,
        message: 'Validation error',
        errors: error.errors
      })
    } else {
      res.status(500).json({
        success: false,
        message: 'Failed to update suggestion status'
      })
    }
  }
}))

export default router 
