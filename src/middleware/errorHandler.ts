import { Request, Response, NextFunction } from 'express'

interface ErrorWithStatus extends Error {
  status?: number
  statusCode?: number
}

export function errorHandler(
  error: ErrorWithStatus,
  req: Request,
  res: Response,
  next: NextFunction
) {
  // Log the error
  console.error('🚨 Unhandled error:', {
    error: error.message,
    stack: error.stack,
    method: req.method,
    path: req.path,
    ip: req.ip,
    userAgent: req.get('User-Agent'),
    timestamp: new Date().toISOString()
  })

  // Don't respond if headers already sent
  if (res.headersSent) {
    return next(error)
  }

  // Determine status code
  const statusCode = error.status || error.statusCode || 500

  // Don't leak internal errors in production
  const isDevelopment = process.env.NODE_ENV !== 'production'
  
  const response: any = {
    success: false,
    error: 'Internal server error',
    timestamp: new Date().toISOString()
  }

  // Add detailed error info in development
  if (isDevelopment) {
    response.error = error.message
    response.stack = error.stack
    response.details = {
      method: req.method,
      path: req.path,
      body: req.body,
      headers: req.headers
    }
  }

  // Send error response
  res.status(statusCode).json(response)
}

// Async error wrapper for route handlers
export function asyncHandler(fn: Function) {
  return (req: Request, res: Response, next: NextFunction) => {
    Promise.resolve(fn(req, res, next)).catch(next)
  }
}

// Not found handler
export function notFoundHandler(req: Request, res: Response) {
  res.status(404).json({
    success: false,
    error: 'Route not found',
    path: req.path,
    method: req.method,
    timestamp: new Date().toISOString()
  })
} 
