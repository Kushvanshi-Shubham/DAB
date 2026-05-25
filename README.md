# 🚀 DAB Deployment Manager

Complete web-based UI for managing Azure Data API Builder entities and deployments.

## 📂 Structure

```
DAB_FULL/
├── START.ps1              - Run this to start everything
├── backend/
│   ├── api-server.ps1     - Backend API server
│   ├── entities.json      - Entity configuration
│   ├── simple-deploy.ps1  - Azure deployment script
│   ├── generate-dab-config.ps1
│   └── backups/           - Auto-created entity backups
└── frontend/
    └── index.html         - Web UI
```

## 🚀 Quick Start

1. **Start the application:**
   ```powershell
   cd DAB_FULL
   .\START.ps1
   ```

2. **Two windows will open:**
   - PowerShell console (Backend API)
   - Browser (Frontend UI)

3. **Use the UI!**

## ✨ Features

### 📋 Current Entities Table
- View all entities from `entities.json`
- See entity name and database mapping
- Delete entities (automatic backup created)
- Real-time entity count

### ➕ Add Entities
- Click "Add Entities" button
- Shows all tables from `API_Master_AKA`
- Select multiple tables
- Search/filter functionality
- Shows which tables are already added
- Select All / Deselect All buttons
- Auto-backup before adding

### 📄 JSON Viewer
- Live preview of entities.json
- Syntax highlighted
- Copy to clipboard
- Download as file

### 🚀 Deploy to Azure
- One-click deployment
- Enter version number (e.g., v18)
- Automatically:
  - Creates backup
  - Regenerates dab-config.json
  - Builds Docker image
  - Pushes to Azure Container Registry
  - Updates App Service
  - Restarts service

## 🔧 Backend API Endpoints

The backend API runs on `http://localhost:8888`:

- `GET /api/entities` - Get all entities
- `GET /api/tables` - Get tables from API_Master_AKA
- `POST /api/entities/add` - Add new entities
- `POST /api/entities/delete` - Delete entity
- `POST /api/deploy` - Deploy to Azure

## 💾 Automatic Backups

Every time you add or delete entities, a backup is created in `backend/backups/`:
- Format: `entities_YYYYMMDD_HHMMSS.json`
- Backups are never deleted automatically
- Restore by copying backup to `entities.json`

## 📊 Workflow

### Adding New Tables

1. DB Developer creates table
2. Table appears in `API_Master_AKA`
3. Open Deployment Manager
4. Click "Add Entities"
5. Select tables from list
6. Click "Add Selected"
7. Backup is created automatically
8. entities.json is updated
9. Review in JSON viewer
10. Click "Push to Azure"
11. Enter version (e.g., v18)
12. Deployment starts!

### Removing Tables

1. Find entity in table
2. Click "Delete" button
3. Confirm deletion
4. Backup is created automatically
5. Entity removed from entities.json
6. Deploy to Azure to sync

## ⚙️ Requirements

- Windows PowerShell
- Docker Desktop (for local testing)
- Azure CLI (for deployment)
- Modern web browser (Chrome/Edge/Firefox)

## 🔐 Security Notes

- This tool is for **admin use only**
- Runs on localhost (not publicly accessible)
- No authentication (assumes trusted local environment)
- For production deployment on VM:
  - Add IIS hosting
  - Add authentication
  - Use HTTPS
  - Restrict network access

## 🎯 Next Steps for VM Deployment

To deploy on Windows VM with IIS:

1. Copy `DAB_FULL` folder to VM
2. Install IIS + ASP.NET Core Hosting Bundle
3. Create IIS site pointing to `frontend` folder
4. Set up IIS Application for backend API
5. Configure Windows Service for backend
6. Add Windows Authentication
7. Configure firewall rules

## 📝 Notes

- Always test locally before deploying to Azure
- Backup files are in `backend/backups/`
- Deployment logs in PowerShell console
- Wait 2-3 minutes after deployment for Azure to update

## ❓ Troubleshooting

**Frontend shows errors:**
- Check if backend API is running
- Look at PowerShell console for errors
- Try refreshing the page

**Can't load tables:**
- Ensure Docker is running
- Check if `API_Master_AKA` is accessible
- Verify local DAB instance is running

**Deployment fails:**
- Check Azure CLI is logged in
- Verify credentials in backend scripts
- Check PowerShell console for errors

---

**Built with ❤️ for easy DAB management**
