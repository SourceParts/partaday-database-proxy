import express, { Request, Response } from 'express'
import { asyncHandler } from '../middleware/errorHandler'
import dbPool from '../database/connection'
import { z } from 'zod'

const router = express.Router()

// Parts query schema
const partsQuerySchema = z.object({
  page: z.coerce.number().int().positive().default(1),
  limit: z.coerce.number().int().positive().max(100).default(50),
  search: z.string().optional(),
  category: z.string().optional(),
  manufacturer: z.string().optional(),
  minPrice: z.coerce.number().optional(),
  maxPrice: z.coerce.number().optional(),
  availability: z.string().optional(),
  featured: z.coerce.boolean().optional()
})

// Get parts with search and filters
router.get('/', asyncHandler(async (req: Request, res: Response) => {
  try {
    const filters = partsQuerySchema.parse(req.query)
    const offset = (filters.page - 1) * filters.limit

    // Build WHERE clause
    const whereClauses: string[] = []
    const params: any[] = []
    let paramCount = 1

    if (filters.search) {
      whereClauses.push(`
        to_tsvector('english', 
          COALESCE(name, '') || ' ' || 
          COALESCE(description, '') || ' ' || 
          COALESCE(manufacturer, '') || ' ' ||
          COALESCE(category, '')
        ) @@ plainto_tsquery('english', $${paramCount})
      `)
      params.push(filters.search)
      paramCount++
    }

    if (filters.category) {
      whereClauses.push(`category = $${paramCount}`)
      params.push(filters.category)
      paramCount++
    }

    if (filters.manufacturer) {
      whereClauses.push(`manufacturer = $${paramCount}`)
      params.push(filters.manufacturer)
      paramCount++
    }

    if (filters.minPrice !== undefined) {
      whereClauses.push(`base_price >= $${paramCount}`)
      params.push(filters.minPrice)
      paramCount++
    }

    if (filters.maxPrice !== undefined) {
      whereClauses.push(`base_price <= $${paramCount}`)
      params.push(filters.maxPrice)
      paramCount++
    }

    if (filters.availability) {
      whereClauses.push(`availability_status = $${paramCount}`)
      params.push(filters.availability)
      paramCount++
    }

    if (filters.featured !== undefined) {
      whereClauses.push(`featured = $${paramCount}`)
      params.push(filters.featured)
      paramCount++
    }

    const whereClause = whereClauses.length > 0 ? `WHERE ${whereClauses.join(' AND ')}` : ''

    // Get total count
    const countQuery = `
      SELECT COUNT(*) as total
      FROM parts
      ${whereClause}
    `
    const countResult = await dbPool.query(countQuery, params)
    const total = parseInt(countResult.rows[0].total)

    // Get paginated results
    params.push(filters.limit, offset)
    const query = `
      SELECT 
        id,
        sku,
        name,
        description,
        category,
        manufacturer,
        specifications,
        image_urls,
        base_price,
        currency,
        availability_status,
        stock_quantity,
        featured,
        featured_date,
        tags,
        created_at,
        updated_at
      FROM parts
      ${whereClause}
      ORDER BY 
        ${filters.featured !== undefined ? 'featured DESC,' : ''}
        ${filters.search ? `ts_rank(
          to_tsvector('english', 
            COALESCE(name, '') || ' ' || 
            COALESCE(description, '') || ' ' || 
            COALESCE(manufacturer, '') || ' ' ||
            COALESCE(category, '')
          ),
          plainto_tsquery('english', '${filters.search.replace("'", "''")}')
        ) DESC,` : ''}
        created_at DESC
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
    console.error('❌ Error fetching parts:', error)
    
    if (error instanceof z.ZodError) {
      res.status(400).json({
        success: false,
        message: 'Validation error',
        errors: error.errors
      })
    } else {
      res.status(500).json({
        success: false,
        message: 'Failed to fetch parts'
      })
    }
  }
}))

// Get featured parts
router.get('/featured', asyncHandler(async (req: Request, res: Response) => {
  try {
    const limit = parseInt(req.query.limit as string) || 10

    const query = `
      SELECT 
        id,
        sku,
        name,
        description,
        category,
        manufacturer,
        specifications,
        image_urls,
        base_price,
        currency,
        availability_status,
        featured_date
      FROM parts
      WHERE featured = TRUE
      ORDER BY featured_date DESC NULLS LAST, created_at DESC
      LIMIT $1
    `
    const result = await dbPool.query(query, [limit])

    res.json({
      success: true,
      data: result.rows
    })

  } catch (error) {
    console.error('❌ Error fetching featured parts:', error)
    res.status(500).json({
      success: false,
      message: 'Failed to fetch featured parts'
    })
  }
}))

// Get part by ID or SKU
router.get('/:identifier', asyncHandler(async (req: Request, res: Response) => {
  try {
    const { identifier } = req.params
    
    // Check if identifier is numeric (ID) or string (SKU)
    const isNumeric = /^\d+$/.test(identifier)
    
    const query = `
      SELECT 
        id,
        sku,
        name,
        description,
        category,
        manufacturer,
        specifications,
        image_urls,
        base_price,
        currency,
        availability_status,
        stock_quantity,
        featured,
        featured_date,
        tags,
        created_at,
        updated_at
      FROM parts
      WHERE ${isNumeric ? 'id' : 'sku'} = $1
    `
    const result = await dbPool.query(query, [isNumeric ? parseInt(identifier) : identifier])

    if (result.rows.length === 0) {
      res.status(404).json({
        success: false,
        message: 'Part not found'
      })
      return
    }

    res.json({
      success: true,
      data: result.rows[0]
    })

  } catch (error) {
    console.error('❌ Error fetching part:', error)
    res.status(500).json({
      success: false,
      message: 'Failed to fetch part'
    })
  }
}))

// Get categories
router.get('/meta/categories', asyncHandler(async (req: Request, res: Response) => {
  try {
    const query = `
      SELECT DISTINCT category, COUNT(*) as count
      FROM parts
      WHERE category IS NOT NULL
      GROUP BY category
      ORDER BY category
    `
    const result = await dbPool.query(query)

    res.json({
      success: true,
      data: result.rows
    })

  } catch (error) {
    console.error('❌ Error fetching categories:', error)
    res.status(500).json({
      success: false,
      message: 'Failed to fetch categories'
    })
  }
}))

// Get manufacturers
router.get('/meta/manufacturers', asyncHandler(async (req: Request, res: Response) => {
  try {
    const query = `
      SELECT DISTINCT manufacturer, COUNT(*) as count
      FROM parts
      WHERE manufacturer IS NOT NULL
      GROUP BY manufacturer
      ORDER BY manufacturer
    `
    const result = await dbPool.query(query)

    res.json({
      success: true,
      data: result.rows
    })

  } catch (error) {
    console.error('❌ Error fetching manufacturers:', error)
    res.status(500).json({
      success: false,
      message: 'Failed to fetch manufacturers'
    })
  }
}))

// Get recent parts for RSS feed
router.get('/feed/recent', asyncHandler(async (req: Request, res: Response) => {
  try {
    const limit = parseInt(req.query.limit as string) || 50
    const tier = req.query.tier as string || 'public'

    // Build query based on tier
    let query = `
      SELECT 
        id,
        sku,
        name,
        description,
        category,
        manufacturer,
        base_price,
        availability_status,
        created_at,
        updated_at
    `

    // Add additional fields for higher tiers
    if (tier === 'pro' || tier === 'enterprise') {
      query = `
        SELECT 
          id,
          sku,
          name,
          description,
          category,
          manufacturer,
          specifications,
          base_price,
          currency,
          availability_status,
          stock_quantity,
          created_at,
          updated_at
      `
    }

    query += `
      FROM parts
      WHERE availability_status != 'discontinued'
      ORDER BY created_at DESC
      LIMIT $1
    `

    const result = await dbPool.query(query, [limit])

    res.json({
      success: true,
      data: result.rows,
      tier: tier
    })

  } catch (error) {
    console.error('❌ Error fetching recent parts:', error)
    res.status(500).json({
      success: false,
      message: 'Failed to fetch recent parts'
    })
  }
}))

export default router