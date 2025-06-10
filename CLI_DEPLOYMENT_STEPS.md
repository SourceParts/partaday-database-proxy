# 🚀 CLI Deployment Steps

## Step 1: Authorize GitHub Access

To deploy via CLI, DigitalOcean needs permission to access GitHub first.

**Option A - Direct Authorization:**
1. Open: https://cloud.digitalocean.com/apps/github/install
2. Authorize DigitalOcean to access **SourceParts** organization
3. Return here for CLI deployment

**Option B - Via App Creation:**
1. Go to: https://cloud.digitalocean.com/apps/new
2. Choose GitHub as source
3. Authorize when prompted
4. Cancel the app creation (we'll use CLI instead)

## Step 2: Deploy via CLI

Once GitHub is authorized, run:

```bash
doctl apps create --spec .do/app.yaml --wait
```

## Step 3: Set Environment Variables

After the app is created, add environment variables:

```bash
# Get the app ID from the output, then:
doctl apps update <APP_ID> --spec .do/app.yaml

# Or set them manually in the DigitalOcean dashboard
```

## Step 4: Verify Deployment

Check the deployment status:

```bash
doctl apps list
doctl apps get <APP_ID>
```

## 🎯 Expected Result

- ✅ App deployed to DigitalOcean App Platform
- ✅ Static IP addresses assigned
- ✅ HTTPS endpoint available
- ✅ Auto-deployment on git push enabled

Let me know when you've completed Step 1 (GitHub authorization) and we can proceed with the CLI deployment! 
