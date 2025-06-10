import { Pool, PoolConfig } from "pg";
import { readFileSync } from "fs";
import { join } from "path";
import { URL } from "url";

class DatabasePool {
  private pool: Pool;
  private static instance: DatabasePool;

  private constructor() {
    // Validate required environment variables
    if (!process.env.DATABASE_URL) {
      throw new Error("DATABASE_URL environment variable is required");
    }

    // Prepare SSL configuration
    let sslConfig: any = false;
    let connectionString = process.env.DATABASE_URL;

    if (
      connectionString.includes("sslmode=require") ||
      process.env.NODE_ENV === "production"
    ) {
      // Enhanced DigitalOcean detection logic (generic patterns)
      const dbUrl = connectionString || "";
      const isDigitalOceanManaged =
        dbUrl.includes(".db.ondigitalocean.com") ||
        dbUrl.includes("ondigitalocean.com") ||
        dbUrl.includes("db-postgresql-") || // Generic DO database pattern
        process.env.NODE_ENV === "production";

      if (isDigitalOceanManaged) {
        // For DigitalOcean/production, we must use SSL, but we disable
        // the certificate verification because it's a self-signed cert.
        sslConfig = {
          rejectUnauthorized: false,
        };
        console.log(
          "🔒 Using DigitalOcean/production mode - SSL enabled, verification disabled."
        );
      } else {
        // For external databases, use strict SSL validation
        sslConfig = {
          rejectUnauthorized: true,
        };

        // Add CA certificate if provided (for external connections)
        let caCert: string | undefined;

        // Check for certificate file first
        if (process.env.DATABASE_CA_CERT_FILE) {
          try {
            const certPath = join(
              process.cwd(),
              process.env.DATABASE_CA_CERT_FILE
            );
            caCert = readFileSync(certPath, "utf8");
            console.log(
              "🔒 Using CA certificate from file:",
              process.env.DATABASE_CA_CERT_FILE
            );
          } catch (error) {
            console.error("❌ Failed to read CA certificate file:", error);
          }
        }

        // Fall back to inline certificate
        if (!caCert && process.env.DATABASE_CA_CERT) {
          // Handle both single-line and multi-line certificate formats
          caCert = process.env.DATABASE_CA_CERT;

          // Replace literal \n with actual newlines if needed
          if (caCert.includes("\\n")) {
            caCert = caCert.replace(/\\n/g, "\n");
          }

          console.log("🔒 Using inline CA certificate for SSL connection");
        }

        if (caCert) {
          sslConfig.ca = caCert;
        } else {
          console.warn("⚠️  SSL required but no CA certificate provided");
        }
      }
    }

    // Manually parse the DATABASE_URL to have more control over the configuration,
    // especially to ensure our SSL settings are not overridden by the connection string.
    const dbUrl = new URL(connectionString);

    const config: PoolConfig = {
      user: dbUrl.username,
      password: dbUrl.password,
      host: dbUrl.hostname,
      port: parseInt(dbUrl.port, 10),
      database: dbUrl.pathname.slice(1), // Remove the leading '/'
      ssl: sslConfig,
      // Connection pool settings optimized for App Platform
      min: parseInt(process.env.MIN_CONNECTIONS || "2"),
      max: parseInt(process.env.MAX_CONNECTIONS || "20"),
      idleTimeoutMillis: parseInt(process.env.IDLE_TIMEOUT || "30000"),
      connectionTimeoutMillis: parseInt(
        process.env.CONNECTION_TIMEOUT || "10000"
      ),
    };

    this.pool = new Pool(config);

    // Handle pool errors
    this.pool.on("error", (err: Error) => {
      console.error("🔥 Database pool error:", err);
    });

    this.pool.on("connect", () => {
      console.log("✅ Database client connected");
    });

    // Log pool stats periodically in development
    if (process.env.NODE_ENV !== "production") {
      setInterval(() => {
        console.log("📊 Pool stats:", {
          totalCount: this.pool.totalCount,
          idleCount: this.pool.idleCount,
          waitingCount: this.pool.waitingCount,
        });
      }, 60000); // Every minute
    }
  }

  public static getInstance(): DatabasePool {
    if (!DatabasePool.instance) {
      DatabasePool.instance = new DatabasePool();
    }
    return DatabasePool.instance;
  }

  public getPool(): Pool {
    return this.pool;
  }

  public async query(text: string, params?: any[]) {
    const start = Date.now();
    try {
      const result = await this.pool.query(text, params);
      const duration = Date.now() - start;

      if (process.env.NODE_ENV !== "production") {
        console.log("📝 Query executed:", {
          query: text.substring(0, 100) + (text.length > 100 ? "..." : ""),
          duration: `${duration}ms`,
          rowCount: result.rowCount,
        });
      }

      return result;
    } catch (error) {
      const duration = Date.now() - start;
      console.error("❌ Query failed:", {
        duration: `${duration}ms`,
        error: error instanceof Error ? error.message : error,
      });
      throw error;
    }
  }

  public async healthCheck(): Promise<{
    status: string;
    latency: number;
    poolStats: any;
  }> {
    const start = Date.now();
    try {
      await this.pool.query("SELECT 1 as health_check");
      const latency = Date.now() - start;

      return {
        status: "healthy",
        latency,
        poolStats: {
          totalCount: this.pool.totalCount,
          idleCount: this.pool.idleCount,
          waitingCount: this.pool.waitingCount,
        },
      };
    } catch (error) {
      const latency = Date.now() - start;
      console.error("💔 Database health check failed:", error);

      return {
        status: "unhealthy",
        latency,
        poolStats: {
          totalCount: this.pool.totalCount,
          idleCount: this.pool.idleCount,
          waitingCount: this.pool.waitingCount,
        },
      };
    }
  }

  public async close(): Promise<void> {
    console.log("🔌 Closing database pool...");
    await this.pool.end();
  }
}

// Export singleton instance
export default DatabasePool.getInstance();

// Handle graceful shutdown
process.on("SIGTERM", async () => {
  console.log("📡 SIGTERM received, closing database connections...");
  await DatabasePool.getInstance().close();
  process.exit(0);
});

process.on("SIGINT", async () => {
  console.log("⚡ SIGINT received, closing database connections...");
  await DatabasePool.getInstance().close();
  process.exit(0);
});
