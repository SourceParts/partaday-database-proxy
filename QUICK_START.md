# 🚀 Quick Start - Deploy Database Proxy

## ⚡ URGENT: Database Trusted Sources

**You're creating `db-postgresql-sfo3-partaday` right now!**

### Add these to Trusted Sources:

```
143.198.0.0/16
134.122.0.0/16
157.245.0.0/16
```

_(See `TRUSTED_SOURCES.md` for details)_

## 📋 Prerequisites

1. **Install doctl CLI** (if not installed):

   ```bash
   # macOS
   brew install doctl

   # Linux
   wget https://github.com/digitalocean/doctl/releases/download/v1.104.0/doctl-1.104.0-linux-amd64.tar.gz
   tar xf doctl-*.tar.gz
   sudo mv doctl /usr/local/bin
   ```

2. **Authenticate doctl**:

   ```bash
   doctl auth init
   # Follow prompts to enter your API token
   ```

3. **Create GitHub repository** for the proxy service (fork or new repo)

## 🎯 Deploy in 4 Steps

### Step 1: Configure Database

```bash
# Configure your database credentials
./scripts/configure-db.sh
```

This will:

- Prompt for your DigitalOcean connection string
- Safely handle your CA certificate
- Generate secure API keys
- Create `.env` file with all configurations

### Step 2: Setup Environment

```bash
# Install dependencies and build
./scripts/setup.sh
```

This will:

- Install all Node.js dependencies
- Build the TypeScript project
- Verify the setup

### Step 3: Deploy to App Platform

```bash
# Deploy the application
./scripts/deploy.sh create
```

This will:

- Create the App Platform application
- Set environment variables
- Deploy the code
- Show you the outbound IP for database whitelisting

### Step 4: Get Connection Info

```bash
# Get app info and outbound IP
./scripts/deploy.sh info
```

Copy the outbound IP and **tighten your database trusted sources** to just that IP.

## 🔄 Daily Usage (like Vercel)

```bash
# Deploy updates
./scripts/deploy.sh deploy

# Check app status and IP
./scripts/deploy.sh info

# View logs
./scripts/deploy.sh logs

# Update environment variables
./scripts/deploy.sh env
```

## 🔧 Environment Variables Required

The setup script will prompt for these, but have them ready:

- `DATABASE_URL` - Your PostgreSQL connection string
- `DATABASE_CA_CERT` - The CA certificate from DigitalOcean
- `PROXY_API_KEY` - Generated automatically
- `PROXY_SECRET_KEY` - Generated automatically

## 🎯 For Your Vercel App

After deployment, add these to your Vercel environment variables:

```bash
DATABASE_PROXY_URL=https://your-app-url.ondigitalocean.app
DATABASE_PROXY_API_KEY=<from-setup-script>
DATABASE_PROXY_SECRET_KEY=<from-setup-script>
```

## 📞 Quick Commands Reference

```bash
# Configure database (first time)
./scripts/configure-db.sh

# Test database connection (optional)
./scripts/test-db-connection.sh          # Interactive
./scripts/test-db-connection.sh --auto   # Automatic IP whitelisting
./scripts/test-db-connection.sh --manual # Manual IP management

# Full deployment (first time)
./scripts/deploy.sh create

# Update existing app
./scripts/deploy.sh deploy

# Get app info and IP
./scripts/deploy.sh info

# Stream logs
./scripts/deploy.sh logs

# Delete app
./scripts/deploy.sh delete

# Help
./scripts/deploy.sh help
```

## ⚠️ Troubleshooting

### doctl not authenticated

```bash
doctl auth init
```

### Missing GitHub repo

Make sure you've pushed the proxy code to GitHub and provide the `username/repo-name` format.

### Deployment fails

Check logs:

```bash
./scripts/deploy.sh logs
```

### Health check fails

Usually means database connection issues. Verify:

1. Database URL is correct
2. Trusted sources include your app's IP
3. SSL certificate is valid

### Test database connection locally

The script now supports automatic IP whitelisting using `doctl`:

```bash
# Interactive mode - asks if you want auto-whitelisting
./scripts/test-db-connection.sh

# Automatic mode - uses auto-whitelisting without prompts
./scripts/test-db-connection.sh --auto

# Manual mode - you must whitelist your IP manually
./scripts/test-db-connection.sh --manual
```

**🤖 Automatic mode** will:
1. Get your public IP using `https://ipv4.icanhazip.com`
2. Find your database ID automatically 
3. Add your IP to the firewall rules
4. Run the connection test
5. Remove your IP from the firewall when done

**📝 Manual mode** requires you to add your IP to database trusted sources first.

---

**🎉 That's it! You now have a Vercel-like deployment workflow for your database proxy!**
