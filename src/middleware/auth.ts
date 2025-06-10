import { Request, Response, NextFunction } from 'express'
import crypto from 'crypto'

interface AuthenticatedRequest extends Request {
  clientId?: string
}

export function authenticateRequest(req: AuthenticatedRequest, res: Response, next: NextFunction) {
  try {
    // Extract authentication headers
    const apiKey = req.headers['x-api-key'] as string
    const signature = req.headers['x-signature'] as string
    const timestamp = req.headers['x-timestamp'] as string

    // Check for required headers
    if (!apiKey || !signature || !timestamp) {
      return res.status(401).json({ 
        success: false,
        error: 'Missing authentication headers',
        required: ['x-api-key', 'x-signature', 'x-timestamp']
      })
    }

    // Verify API key
    if (apiKey !== process.env.PROXY_API_KEY) {
      console.warn('🔒 Invalid API key attempt:', { 
        ip: req.ip, 
        userAgent: req.get('User-Agent'),
        apiKey: apiKey.substring(0, 8) + '...' 
      })
      return res.status(401).json({ 
        success: false,
        error: 'Invalid API key' 
      })
    }

    // Verify timestamp to prevent replay attacks
    const now = Date.now()
    const requestTime = parseInt(timestamp)
    const timeDifference = Math.abs(now - requestTime)
    
    if (isNaN(requestTime) || timeDifference > 300000) { // 5 minutes
      console.warn('🕰️  Request timestamp too old:', { 
        ip: req.ip,
        timeDifference: `${timeDifference}ms`,
        requestTime: new Date(requestTime).toISOString(),
        currentTime: new Date(now).toISOString()
      })
      return res.status(401).json({ 
        success: false,
        error: 'Request timestamp too old or invalid' 
      })
    }

    // Generate expected signature
    const payload = JSON.stringify(req.body) + timestamp
    const expectedSignature = crypto
      .createHmac('sha256', process.env.PROXY_SECRET_KEY!)
      .update(payload)
      .digest('hex')

    // Verify signature using timing-safe comparison
    if (!crypto.timingSafeEqual(Buffer.from(signature, 'hex'), Buffer.from(expectedSignature, 'hex'))) {
      console.warn('🔐 Invalid signature attempt:', { 
        ip: req.ip,
        method: req.method,
        path: req.path,
        bodyLength: JSON.stringify(req.body).length
      })
      return res.status(401).json({ 
        success: false,
        error: 'Invalid signature' 
      })
    }

    // Authentication successful
    req.clientId = 'partaday-vercel'
    
    if (process.env.NODE_ENV !== 'production') {
      console.log('✅ Authentication successful:', {
        clientId: req.clientId,
        method: req.method,
        path: req.path,
        ip: req.ip
      })
    }

    next()
  } catch (error) {
    console.error('🚨 Authentication error:', error)
    res.status(500).json({ 
      success: false,
      error: 'Authentication failed' 
    })
  }
}

// Helper function for clients to generate authentication headers
export function generateAuthHeaders(body: any, apiKey: string, secretKey: string) {
  const timestamp = Date.now().toString()
  const payload = JSON.stringify(body) + timestamp
  const signature = crypto
    .createHmac('sha256', secretKey)
    .update(payload)
    .digest('hex')

  return {
    'x-api-key': apiKey,
    'x-signature': signature,
    'x-timestamp': timestamp,
    'content-type': 'application/json'
  }
}

// Middleware for rate limiting per API key
export function createApiKeyRateLimit(windowMs: number = 60000, max: number = 20) {
  const store = new Map<string, { count: number; resetTime: number }>()
  
  return (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
    const apiKey = req.headers['x-api-key'] as string
    const now = Date.now()
    
    if (!apiKey) {
      return next()
    }

    const keyData = store.get(apiKey)
    
    if (!keyData || now > keyData.resetTime) {
      // Reset or initialize counter
      store.set(apiKey, { count: 1, resetTime: now + windowMs })
      return next()
    }

    if (keyData.count >= max) {
      return res.status(429).json({
        success: false,
        error: 'Rate limit exceeded for this API key',
        retryAfter: Math.ceil((keyData.resetTime - now) / 1000)
      })
    }

    keyData.count++
    next()
  }
} 
