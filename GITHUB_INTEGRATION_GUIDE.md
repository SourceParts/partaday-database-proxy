# GitHub Integration Setup for DigitalOcean App Platform

## 🔗 GitHub Authentication Required

The CLI deployment failed because DigitalOcean App Platform needs permission to access the SourceParts GitHub repository.

## ✅ SOLUTION - Web Interface Deployment

### Step 1: Access DigitalOcean App Platform
1. Go to: https://cloud.digitalocean.com/apps/new
2. Click **"Create App"**

### Step 2: Connect GitHub Repository
1. Choose **"GitHub"** as the source
2. Click **"Authorize DigitalOcean"** if prompted
3. Select the **"SourceParts"** organization
4. Choose repository: **"partaday-database-proxy"**
5. Select branch: **"main"**
6. Source directory: **"/"** (root)

### Step 3: Configure Application
1. DigitalOcean will auto-detect the `app.yaml` configuration
2. Review the settings:
   - **Name**: partaday-database-proxy
   - **Environment**: Node.js
   - **Build Command**: npm run build
   - **Run Command**: npm start
   - **Port**: 3000

### Step 4: Set Environment Variables
You'll need to add these environment variables in the DigitalOcean interface:

**Required Secrets:**
- `DATABASE_URL` = (your PostgreSQL connection string)
- `DATABASE_CA_CERT` = (your CA certificate)
- `PROXY_API_KEY` = (generated API key from .env file)
- `PROXY_SECRET_KEY` = (generated secret key from .env file)

**Regular Variables:**
- `NODE_ENV` = production
- `PORT` = 3000
- `ALLOWED_ORIGINS` = https://partaday.com,https://www.partaday.com

### Step 5: Deploy
1. Review all settings
2. Click **"Create Resources"**
3. Wait for deployment (5-10 minutes)
4. Get the app URL (will have static IP addresses)

## 🎯 Expected Result

Once deployed, you'll get:
- ✅ **Static IP addresses** for database whitelisting
- ✅ **HTTPS endpoint** for the database proxy
- ✅ **Auto-deployment** on git push
- ✅ **Health monitoring** and scaling

## 📋 Environment Variables Reference

Copy these values from your local `.env` file:

```bash
# From database-proxy-starter/.env
DATABASE_URL="postgresql://username:password@your-database-host:25060/defaultdb?sslmode=require"

DATABASE_CA_CERT="-----BEGIN CERTIFICATE-----
[Your CA Certificate Content]
-----END CERTIFICATE-----"

PROXY_API_KEY="[Your generated API key]"
PROXY_SECRET_KEY="[Your generated secret key]"
```

**⚠️ Security Note:** Copy the actual values from your local `.env` file, not these placeholders.

## 🔄 Alternative: CLI with GitHub Token

If you prefer CLI deployment, you can:
1. Set up a GitHub personal access token
2. Configure DigitalOcean GitHub integration via CLI
3. Then retry `doctl apps create --spec .do/app.yaml`

For now, the web interface approach is recommended for initial setup. 
