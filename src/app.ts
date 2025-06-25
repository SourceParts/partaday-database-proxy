// Load environment variables first, before any other imports
import { config } from "dotenv";
config();

import express from "express";
import cors from "cors";
import helmet from "helmet";
import rateLimit from "express-rate-limit";
import { authenticateRequest } from "./middleware/auth";
import { errorHandler } from "./middleware/errorHandler";
import healthRouter from "./routes/health";
import quotesRouter from "./routes/quotes";
import suggestionsRouter from "./routes/suggestions";
import contactSupportRouter from "./routes/contact-support";
import adminRouter from "./routes/admin";
import partsRouter from "./routes/parts";

const app = express();
const PORT = process.env.PORT || 3000;

// Security middleware
app.use(
  helmet({
    contentSecurityPolicy: false, // Disable CSP for API
    crossOriginEmbedderPolicy: false,
  })
);

app.use(
  cors({
    origin: process.env.ALLOWED_ORIGINS?.split(",") || [
      "https://partaday.com",
      "http://localhost:3000", // For development
    ],
    credentials: true,
    methods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allowedHeaders: [
      "Content-Type",
      "Authorization",
      "x-api-key",
      "x-signature",
      "x-timestamp",
    ],
  })
);

// Rate limiting
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100, // limit each IP to 100 requests per windowMs
  message: {
    error: "Too many requests from this IP, please try again later.",
  },
  standardHeaders: true,
  legacyHeaders: false,
});
app.use(limiter);

// Body parsing
app.use(express.json({ limit: "10mb" }));
app.use(express.urlencoded({ extended: true, limit: "10mb" }));

// Health check route (no auth required)
app.use("/health", healthRouter);

// Admin routes (no auth middleware - handled internally)
app.use("/api/admin", adminRouter);

// Authentication for all other API routes
app.use("/api", authenticateRequest);

// API routes
app.use("/api/quotes", quotesRouter);
app.use("/api/suggestions", suggestionsRouter);
app.use("/api/contact-support", contactSupportRouter);
app.use("/api/parts", partsRouter);

// Root endpoint
app.get("/", (req, res) => {
  res.json({
    name: "PartADay Database Proxy",
    version: "1.0.0",
    status: "operational",
    endpoints: {
      health: "/health",
      admin: "/api/admin",
      quotes: "/api/quotes",
      suggestions: "/api/suggestions",
      contactSupport: "/api/contact-support",
      parts: "/api/parts",
    },
  });
});

// Error handling middleware (must be last)
app.use(errorHandler);

// Start server
app.listen(PORT, () => {
  console.log(`🚀 Database proxy server running on port ${PORT}`);
  console.log(`📊 Health check: http://localhost:${PORT}/health`);
  console.log(`🔗 API base URL: http://localhost:${PORT}/api`);
  console.log(`🌍 Environment: ${process.env.NODE_ENV || 'development'}`);
  
  // Log environment variable status (without exposing values)
  const envVars = {
    DATABASE_URL: !!process.env.DATABASE_URL,
    DATABASE_CA_CERT: !!process.env.DATABASE_CA_CERT,
    DATABASE_CA_CERT_FILE: !!process.env.DATABASE_CA_CERT_FILE,
    PROXY_API_KEY: !!process.env.PROXY_API_KEY,
    PROXY_SECRET_KEY: !!process.env.PROXY_SECRET_KEY,
    NODE_ENV: process.env.NODE_ENV || 'not set',
    PORT: process.env.PORT || 'not set (using 3000)'
  };
  
  console.log('🔧 Environment variables status:', envVars);
  
  // Test database connection on startup
  import('./database/connection').then(({ default: dbPool }) => {
    dbPool.healthCheck().then(result => {
      console.log('✅ Database connection successful:', result);
    }).catch(error => {
      console.error('❌ Database connection failed on startup:', error.message);
    });
  });
});

export default app;
