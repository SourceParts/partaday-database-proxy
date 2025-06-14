import express from "express";
import cors from "cors";
import helmet from "helmet";
import rateLimit from "express-rate-limit";
import { config } from "dotenv";
import { authenticateRequest } from "./middleware/auth";
import { errorHandler } from "./middleware/errorHandler";
import healthRouter from "./routes/health";
import quotesRouter from "./routes/quotes";
import suggestionsRouter from "./routes/suggestions";
import contactSupportRouter from "./routes/contact-support";

// Load environment variables
config();

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

// Authentication for all API routes
app.use("/api", authenticateRequest);

// API routes
app.use("/api/quotes", quotesRouter);
app.use("/api/suggestions", suggestionsRouter);
app.use("/api/contact-support", contactSupportRouter);

// Root endpoint
app.get("/", (req, res) => {
  res.json({
    name: "PartADay Database Proxy",
    version: "1.0.0",
    status: "operational",
    endpoints: {
      health: "/health",
      quotes: "/api/quotes",
      suggestions: "/api/suggestions",
      contactSupport: "/api/contact-support",
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
});

export default app;
