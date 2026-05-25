# 🚀 DAB Project - Quick Reference

## 📅 Latest Update: January 28, 2026

### ✅ Swagger UI Integration Complete! (BUILT-IN TO DOCKER)

**Files Modified:**
- `backend/Dockerfile` - Added Swagger UI with nginx
- `backend/simple-deploy.ps1` - Auto-copies Dockerfile on deployment  
- `frontend/swagger.html` - Standalone Swagger viewer (backup option)
- `frontend/index.html` - Added Swagger UI button

**What's New:**
- ✅ Swagger UI now **built into Docker image** (like v18.3.11!)
- ✅ Uses nginx to serve Swagger UI at `/swagger`
- ✅ Auto-configured to fetch from `/api/swagger`
- ✅ Updated `dab-config.json` schema: v1.2.10 → v1.5.56
- ✅ GraphQL enabled with introspection
- ✅ Development mode for better API docs

**To Deploy with Swagger:**
```powershell
cd "d:\DAB_Project\DAB Project\DAB_FULL\backend"
.\simple-deploy.ps1 -Version "v19"
```

**After Deployment, Access Swagger at:**
```
https://my-dab-app.azurewebsites.net/swagger
```

---

## 🔧 If Service Does Not Work

1. **Check Task User:**

```powershell
    # Check status
    Get-ScheduledTask -TaskName "DAB_API_Backend"

    # Stop service
    Stop-ScheduledTask -TaskName "DAB_API_Backend"

    # Start service
    Start-ScheduledTask -TaskName "DAB_API_Backend"
    `Get-ScheduledTask -TaskName "DAB_API_Backend" | Select-Object State`
```

Should show: `Running`

2. **Check Azure CLI Login:**

   ```powershell
   az account show
   ```
   Should show your Azure subscription
   (If error re-login)

3. **Check Docker:**

   ```powershell
   docker ps
   ```
   Should show running containers
   (If error restart docker)

4. **Test API:**
   ```powershell
   curl.exe http://localhost:8888/api/version
   ```
   Should return: `{"version":" ","success":true}`

---

## 🌐 Swagger URLs

### Production (Azure)
- **Swagger UI**: `https://my-dab-app.azurewebsites.net/swagger.html`
- **OpenAPI JSON**: `https://my-dab-app.azurewebsites.net/api/swagger`

### Local Development
- **Swagger UI**: `file:///d:/DAB_Project/DAB Project/DAB_FULL/frontend/swagger.html`
- **OpenAPI JSON**: `http://localhost:5000/api/swagger`

---


Copy-Item "d:\DAB_Project\DAB Project\DAB_FULL\frontend\index.html" "C:\inetpub\wwwroot\deployment-manager\index.html" -Force