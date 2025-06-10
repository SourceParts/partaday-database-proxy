# Database Trusted Sources - Quick Reference

## For Immediate Database Creation

Since you're creating the database **right now**, here are the recommended trusted sources to add:

### Option 1: DigitalOcean App Platform IP Ranges (Recommended for now)

Add these CIDR blocks to your database trusted sources:

```
# DigitalOcean App Platform Outbound IP Ranges (SFO3 region)
143.198.0.0/16
134.122.0.0/16
157.245.0.0/16
```

### Option 2: Broader DigitalOcean Range (More permissive)

If you want to be extra safe during setup:

```
# Broader DigitalOcean range
64.225.0.0/16
143.198.0.0/16
134.122.0.0/16
157.245.0.0/16
```

## After App Deployment

Once your app is deployed, get the specific outbound IP:

```bash
# Run this after deployment
./scripts/deploy.sh info
```

This will show you the exact IP address to whitelist, and you can then:

1. **Tighten the trusted sources** to only that specific IP/32
2. **Remove the broader ranges** for better security

## Security Note

- The broader ranges are **temporary** for initial setup
- Always tighten to specific IPs once you know them
- Use `/32` CIDR notation for single IP addresses

## Current Status

Your database: `db-postgresql-sfo3-partaday`
Region: SFO3 (San Francisco)

**For now, add the Option 1 ranges above to complete your database creation.** 
