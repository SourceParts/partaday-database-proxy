import express, { Request, Response } from "express";
import { asyncHandler } from "../middleware/errorHandler";
import dbPool from "../database/connection";
import { 
  contactSupportSchema, 
  contactFiltersSchema, 
  updateContactStatusSchema,
  ContactSupport,
  ContactFilters,
  UpdateContactStatus
} from '../schemas/validation-schemas'
import { z } from 'zod'

const router = express.Router();

// Create contact support request
router.post(
  "/",
  asyncHandler(async (req: Request, res: Response) => {
    try {
      console.log("📞 Creating contact support request:", req.body);

      // Validate request body
      const validatedData = contactSupportSchema.parse(req.body);
      const referenceId = `CS-${Date.now()}`;

      // Begin transaction
      const client = await dbPool.getPool().connect();
      try {
        await client.query("BEGIN");

        // Create or get user
        // Note: contact support uses 'name' field instead of first_name/last_name
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
        // Split name into first and last name
        const nameParts = validatedData.name.trim().split(' ')
        const firstName = nameParts[0] || validatedData.name
        const lastName = nameParts.slice(1).join(' ') || ''
        
        const userResult = await client.query(userQuery, [
          validatedData.email,
          firstName,
          lastName,
          validatedData.company || null,
          validatedData.phone || null
        ])

        // Create contact support request
        const contactQuery = `
          INSERT INTO contact_support_requests (
            user_id, subject, message, category, priority,
            part_id, part_name, source, user_agent, ip_address,
            reference_id, status
          ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, 'open')
          RETURNING id, reference_id, status, created_at
        `
        const contactResult = await client.query(contactQuery, [
          userResult.rows[0].id,
          validatedData.subject,
          validatedData.message,
          validatedData.category,
          validatedData.priority,
          validatedData.partId || null,
          validatedData.partName || null,
          validatedData.source || null,
          validatedData.userAgent || null,
          validatedData.ipAddress || null,
          referenceId
        ])

        await client.query("COMMIT");

        const result = contactResult.rows[0]
        res.json({
          success: true,
          message: "Contact support request created successfully",
          data: {
            id: result.reference_id,
            status: result.status,
            created_at: result.created_at,
          },
        });
      } catch (error) {
        await client.query("ROLLBACK");
        throw error;
      } finally {
        client.release();
      }
    } catch (error) {
      console.error("❌ Error creating contact support request:", error);
      
      if (error instanceof z.ZodError) {
        res.status(400).json({
          success: false,
          message: 'Validation error',
          errors: error.errors
        })
      } else {
        res.status(500).json({
          success: false,
          message: "Failed to create contact support request",
        });
      }
    }
  })
);

// Get contact support requests (for admin)
router.get(
  "/",
  asyncHandler(async (req: Request, res: Response) => {
    try {
      // Validate query parameters
      const filters = contactFiltersSchema.parse(req.query);
      const offset = (filters.page - 1) * filters.limit;

      // Build WHERE clause
      const whereClauses: string[] = [];
      const params: any[] = [];
      let paramCount = 1;

      if (filters.status) {
        whereClauses.push(`csr.status = $${paramCount}`);
        params.push(filters.status);
        paramCount++;
      }

      if (filters.priority) {
        whereClauses.push(`csr.priority = $${paramCount}`);
        params.push(filters.priority);
        paramCount++;
      }

      if (filters.category) {
        whereClauses.push(`csr.category = $${paramCount}`);
        params.push(filters.category);
        paramCount++;
      }

      if (filters.assignedTo) {
        whereClauses.push(`csr.assigned_to = $${paramCount}`);
        params.push(filters.assignedTo);
        paramCount++;
      }

      if (filters.startDate) {
        whereClauses.push(`csr.created_at >= $${paramCount}`);
        params.push(filters.startDate);
        paramCount++;
      }

      if (filters.endDate) {
        whereClauses.push(`csr.created_at <= $${paramCount}`);
        params.push(filters.endDate);
        paramCount++;
      }

      const whereClause = whereClauses.length > 0 ? `WHERE ${whereClauses.join(' AND ')}` : '';

      // Get total count
      const countQuery = `
        SELECT COUNT(*) as total
        FROM contact_support_requests csr
        ${whereClause}
      `;
      const countResult = await dbPool.query(countQuery, params);
      const total = parseInt(countResult.rows[0].total);

      // Get paginated results
      params.push(filters.limit, offset);
      const query = `
        SELECT 
          csr.id,
          csr.reference_id,
          csr.subject,
          csr.message,
          csr.category,
          csr.priority,
          csr.status,
          csr.part_id,
          csr.part_name,
          csr.assigned_to,
          csr.response_message,
          csr.source,
          csr.created_at,
          csr.updated_at,
          u.email,
          u.first_name,
          u.last_name,
          u.company,
          u.phone
        FROM contact_support_requests csr
        JOIN users u ON csr.user_id = u.id
        ${whereClause}
        ORDER BY 
          CASE csr.priority 
            WHEN 'urgent' THEN 1
            WHEN 'high' THEN 2
            WHEN 'normal' THEN 3
            WHEN 'low' THEN 4
          END,
          csr.created_at DESC
        LIMIT $${paramCount} OFFSET $${paramCount + 1}
      `;
      const result = await dbPool.query(query, params);

      res.json({
        success: true,
        data: result.rows,
        pagination: {
          page: filters.page,
          limit: filters.limit,
          total,
          totalPages: Math.ceil(total / filters.limit),
        },
      });
    } catch (error) {
      console.error("❌ Error fetching contact support requests:", error);
      
      if (error instanceof z.ZodError) {
        res.status(400).json({
          success: false,
          message: 'Validation error',
          errors: error.errors
        })
      } else {
        res.status(500).json({
          success: false,
          message: "Failed to fetch contact support requests",
        });
      }
    }
  })
);

// Get contact support request by ID
router.get(
  "/:id",
  asyncHandler(async (req: Request, res: Response) => {
    try {
      const { id } = req.params;

      const query = `
        SELECT 
          csr.id,
          csr.reference_id,
          csr.subject,
          csr.message,
          csr.category,
          csr.priority,
          csr.status,
          csr.part_id,
          csr.part_name,
          csr.assigned_to,
          csr.response_message,
          csr.source,
          csr.user_agent,
          csr.ip_address,
          csr.created_at,
          csr.updated_at,
          u.email,
          u.first_name,
          u.last_name,
          u.company,
          u.phone
        FROM contact_support_requests csr
        JOIN users u ON csr.user_id = u.id
        WHERE csr.reference_id = $1
      `;
      const result = await dbPool.query(query, [id]);

      if (result.rows.length === 0) {
        res.status(404).json({
          success: false,
          message: "Contact support request not found",
        });
        return;
      }

      res.json({
        success: true,
        data: result.rows[0],
      });
    } catch (error) {
      console.error("❌ Error fetching contact support request:", error);
      res.status(500).json({
        success: false,
        message: "Failed to fetch contact support request",
      });
    }
  })
);

// Update contact support request status (for admin)
router.patch(
  "/:id",
  asyncHandler(async (req: Request, res: Response) => {
    try {
      const { id } = req.params;
      
      // Validate request body
      const validatedData = updateContactStatusSchema.parse(req.body);

      // Build update query
      const setClauses: string[] = ['status = $2', 'updated_at = NOW()'];
      const params: any[] = [id, validatedData.status];
      let paramCount = 3;

      if (validatedData.assignedTo !== undefined) {
        setClauses.push(`assigned_to = $${paramCount}`);
        params.push(validatedData.assignedTo);
        paramCount++;
      }

      if (validatedData.responseMessage !== undefined) {
        setClauses.push(`response_message = $${paramCount}`);
        params.push(validatedData.responseMessage);
        paramCount++;
      }

      const updateQuery = `
        UPDATE contact_support_requests
        SET ${setClauses.join(', ')}
        WHERE reference_id = $1
        RETURNING id, reference_id, status, updated_at
      `;

      const result = await dbPool.query(updateQuery, params);

      if (result.rows.length === 0) {
        res.status(404).json({
          success: false,
          message: "Contact support request not found",
        });
        return;
      }

      // Log the update in audit table
      await dbPool.query(`
        INSERT INTO audit_logs (
          table_name, record_id, action, changed_by, changes
        ) VALUES ('contact_support_requests', $1, 'update', $2, $3)
      `, [
        result.rows[0].id,
        'admin', // This should come from authenticated user
        JSON.stringify(validatedData)
      ]);

      res.json({
        success: true,
        message: "Contact support request updated successfully",
        data: result.rows[0],
      });
    } catch (error) {
      console.error("❌ Error updating contact support request:", error);
      
      if (error instanceof z.ZodError) {
        res.status(400).json({
          success: false,
          message: 'Validation error',
          errors: error.errors
        })
      } else {
        res.status(500).json({
          success: false,
          message: "Failed to update contact support request",
        });
      }
    }
  })
);

export default router;
