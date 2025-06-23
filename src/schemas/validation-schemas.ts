import { z } from 'zod'

// Common schemas
export const emailSchema = z.string().email('Invalid email address')
export const phoneSchema = z.string().regex(/^[\d\s\-\+\(\)]+$/, 'Invalid phone number').optional()

// User schema
export const userSchema = z.object({
  email: emailSchema,
  firstName: z.string().min(1, 'First name is required').max(100),
  lastName: z.string().min(1, 'Last name is required').max(100),
  company: z.string().max(255).optional(),
  phone: phoneSchema
})

// Quote request schema
export const quoteRequestSchema = z.object({
  // User info
  email: emailSchema,
  firstName: z.string().min(1, 'First name is required').max(100),
  lastName: z.string().min(1, 'Last name is required').max(100),
  company: z.string().max(255).optional(),
  phone: phoneSchema,
  
  // Part info
  partType: z.string().min(1, 'Part type is required').max(100),
  partNumber: z.string().max(100).optional(),
  manufacturer: z.string().max(255).optional(),
  quantity: z.number().int().positive('Quantity must be a positive number'),
  description: z.string().optional(),
  
  // Request details
  urgency: z.enum(['immediate', 'within_week', 'within_month', 'flexible']),
  budget: z.string().max(100).optional(),
  additionalNotes: z.string().optional(),
  
  // Preferences
  emailUpdates: z.boolean().default(true),
  newsletter: z.boolean().default(false),
  
  // Tracking
  source: z.string().max(50).optional(),
  userAgent: z.string().optional(),
  ipAddress: z.string().max(45).optional()
})

// Part suggestion schema
export const partSuggestionSchema = z.object({
  // User info
  email: emailSchema,
  firstName: z.string().min(1, 'First name is required').max(100),
  lastName: z.string().min(1, 'Last name is required').max(100),
  company: z.string().max(255).optional(),
  
  // Part info
  partName: z.string().min(1, 'Part name is required').max(255),
  partNumber: z.string().max(100).optional(),
  manufacturer: z.string().max(255).optional(),
  category: z.string().max(100).optional(),
  description: z.string().optional(),
  
  // Suggestion details
  whyImportant: z.string().optional(),
  availabilityInfo: z.string().optional(),
  additionalNotes: z.string().optional(),
  
  // Tracking
  source: z.string().max(50).optional(),
  userAgent: z.string().optional(),
  ipAddress: z.string().max(45).optional()
})

// Contact support schema
export const contactSupportSchema = z.object({
  // User info
  email: emailSchema,
  name: z.string().min(1, 'Name is required').max(200),
  company: z.string().max(255).optional(),
  phone: phoneSchema,
  
  // Request info
  subject: z.string().min(1, 'Subject is required').max(255),
  message: z.string().min(1, 'Message is required'),
  category: z.enum(['general', 'technical', 'order', 'quote', 'other']).default('general'),
  priority: z.enum(['low', 'normal', 'high', 'urgent']).default('normal'),
  
  // Related part (optional)
  partId: z.string().max(50).optional(),
  partName: z.string().max(255).optional(),
  
  // Tracking
  source: z.string().max(50).optional(),
  userAgent: z.string().optional(),
  ipAddress: z.string().max(45).optional()
})

// Admin schemas
export const adminLoginSchema = z.object({
  email: emailSchema,
  password: z.string().min(8, 'Password must be at least 8 characters')
})

export const updateQuoteStatusSchema = z.object({
  status: z.enum(['submitted', 'reviewing', 'quoted', 'accepted', 'rejected', 'expired']),
  quotedPrice: z.number().positive().optional(),
  quoteValidUntil: z.string().datetime().optional(),
  adminNotes: z.string().optional()
})

export const updateSuggestionStatusSchema = z.object({
  status: z.enum(['submitted', 'reviewing', 'approved', 'rejected', 'implemented']),
  adminNotes: z.string().optional()
})

export const updateContactStatusSchema = z.object({
  status: z.enum(['open', 'in_progress', 'resolved', 'closed']),
  assignedTo: z.string().max(100).optional(),
  responseMessage: z.string().optional()
})

// Query parameter schemas
export const paginationSchema = z.object({
  page: z.coerce.number().int().positive().default(1),
  limit: z.coerce.number().int().positive().max(100).default(50)
})

export const quoteFiltersSchema = paginationSchema.extend({
  status: z.enum(['submitted', 'reviewing', 'quoted', 'accepted', 'rejected', 'expired']).optional(),
  urgency: z.enum(['immediate', 'within_week', 'within_month', 'flexible']).optional(),
  startDate: z.string().datetime().optional(),
  endDate: z.string().datetime().optional()
})

export const suggestionFiltersSchema = paginationSchema.extend({
  status: z.enum(['submitted', 'reviewing', 'approved', 'rejected', 'implemented']).optional(),
  category: z.string().optional(),
  startDate: z.string().datetime().optional(),
  endDate: z.string().datetime().optional()
})

export const contactFiltersSchema = paginationSchema.extend({
  status: z.enum(['open', 'in_progress', 'resolved', 'closed']).optional(),
  priority: z.enum(['low', 'normal', 'high', 'urgent']).optional(),
  category: z.enum(['general', 'technical', 'order', 'quote', 'other']).optional(),
  assignedTo: z.string().optional(),
  startDate: z.string().datetime().optional(),
  endDate: z.string().datetime().optional()
})

// Type exports
export type QuoteRequest = z.infer<typeof quoteRequestSchema>
export type PartSuggestion = z.infer<typeof partSuggestionSchema>
export type ContactSupport = z.infer<typeof contactSupportSchema>
export type AdminLogin = z.infer<typeof adminLoginSchema>
export type UpdateQuoteStatus = z.infer<typeof updateQuoteStatusSchema>
export type UpdateSuggestionStatus = z.infer<typeof updateSuggestionStatusSchema>
export type UpdateContactStatus = z.infer<typeof updateContactStatusSchema>
export type QuoteFilters = z.infer<typeof quoteFiltersSchema>
export type SuggestionFilters = z.infer<typeof suggestionFiltersSchema>
export type ContactFilters = z.infer<typeof contactFiltersSchema>