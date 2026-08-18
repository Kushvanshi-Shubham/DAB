# DATABASE ANALYSIS FINDINGS — `ROI_TREND_DATA_AKA` 500 error

**Date:** 2026-06-16
**Symptom:** `GET https://my-dab-app.azurewebsites.net/api/ROI_TREND_DATA_AKA` →
`500 { "code": "DatabaseOperationFailed", "message": "While processing your request the database ran into an error." }`

---

## TL;DR

DAB reads the SQL Server schema **once, at container startup**, and caches it.
`ROI_TREND_DATA_AKA` is a **rolling 19-month wide table** — every month the ETL
**drops the oldest month's 6 columns and adds a new month's 6 columns**. Since the
last DAB restart the table rolled forward one month, so DAB's cached column list no
longer matches the live table. DAB's default `SELECT` still asks for the dropped
columns → SQL fails → `DatabaseOperationFailed`.

**Not** a column-naming bug, connection issue, permission issue, or config error.

---

## Evidence (verified against live Azure service, 2026-06-16)

| Request | Result | Meaning |
|---|---|---|
| `GET .../ROI_TREND_DATA_AKA` (all cols) | **500** | default SELECT includes dropped columns |
| `?$select=ID` / `SEG` / `MRP` / `SUB-DIV` | **200** | stable columns work — not a connection/permission/name issue |
| `?$select=2024-10-31_SALE_QTY` | **500** | DAB still queries a column that no longer exists |
| `?$select=2026-05-31_SALE_QTY` | **400 "Invalid field"** | DAB does not know the newest columns |
| Raw `SELECT * ... FOR JSON PATH` on DB | **OK** | the DB and the table itself are fine |
| `SELECT COUNT(*) ... WHERE COLUMN_NAME LIKE '2024-10-31%'` | **0** | old columns genuinely dropped |

### Schema drift

| | Oldest month | Newest month |
|---|---|---|
| **DAB cached** (`/api/openapi`) | `2024-10-31_*` | `2026-04-30_*` |
| **Actual DB** (`INFORMATION_SCHEMA`) | `2024-11-30_*` | `2026-05-31_*` |

`dbo.ROI_TREND_DATA_AKA` = 128 columns: 13 dimension cols + `ID` + 114 metric cols
(19 months × 6 metrics: `STK_0001_QTY, SALE_QTY, SALE_VAL, GM_VAL, GRC_Q, CO_CL_STK_Q`).

---

## Blast radius

Of the **94 entities**, only **2** have date-named columns:

- **`ROI_TREND_DATA_AKA`** — rolls monthly → **BROKEN**, and will re-break on the 1st of every month.
- **`STORE_MAJ_CAT_BUDGET_FIXTURE_AKA`** — fixed future budget periods (2025-04 → 2029-07), unchanged since deploy → returns **200 (healthy)**.

All other 92 entities are unaffected.

---

## Fix 1 — Immediate (clears the 500 in ~2 min)

DAB re-introspects the live schema at boot, and the schema is **not** baked into the
Docker image (only the entity list is). So a plain **restart is enough — no rebuild/redeploy**.

Run on the deploy VM (`192.168.151.45`, where Azure CLI is installed & logged in):

```powershell
az webapp restart --name my-dab-app --resource-group dab-rg
# wait ~2 min, then verify:
curl.exe "https://my-dab-app.azurewebsites.net/api/ROI_TREND_DATA_AKA?$first=1"
```

⚠️ Temporary: this breaks again next month when the columns roll.

---

## Fix 2 — Permanent

### Option A (recommended — IMPLEMENTED): scheduled DAB restart on the VM
DAB re-reads the schema at every boot, so the permanent guard is simply to restart it
regularly. The external monthly roll job can't be located (it's not a stored proc, and
the `datalake` account can't read SQL Agent jobs), and editing a live ETL to call
Azure CLI is riskier than the problem — so this is decoupled into a scheduled task on
the deploy VM instead. Two scripts were added to `backend/`:

- **`restart-dab.ps1`** — restarts `my-dab-app`, waits, and verifies the entity returns 200. Logs to `restart-dab.log`.
- **`register-restart-task.ps1`** — registers a Windows Scheduled Task `DAB_Schema_Refresh_Restart` (daily 02:30) that runs the above.

**One-time setup (on VM `192.168.151.45`, elevated PowerShell, as `VM-HRMS\Administrator`):**
```powershell
cd D:\<path-to>\DAB\backend
.\register-restart-task.ps1
Start-ScheduledTask -TaskName "DAB_Schema_Refresh_Restart"   # test immediately
Get-Content .\restart-dab.log -Tail 10                        # confirm HTTP 200
```
Daily restart guarantees DAB picks up the monthly column roll within 24h, with zero
dependency on the ETL. (Tie it to the ETL instead only if a 24h worst-case window is
unacceptable — then call `az webapp restart --name my-dab-app --resource-group dab-rg`
as that job's final step.)

### Option B (most robust API contract): expose a stable-alias view
Keep the wide table for the ETL, but point the DAB entity at a view whose column
names **never change** (`M00_… = newest month, M18_… = oldest`). DAB's exposed schema
then stays constant and never 500s. The view must be recreated when columns roll
(part of the same monthly job), but its **public column names are fixed**.

A generator that (re)builds the view from whatever month columns currently exist:

```sql
-- Recreate VW_ROI_TREND_DATA_API with stable month-offset aliases (M00 = newest).
DECLARE @cols NVARCHAR(MAX) = N'';
DECLARE @metrics TABLE (m SYSNAME);
INSERT INTO @metrics(m) VALUES
  ('STK_0001_QTY'),('SALE_QTY'),('SALE_VAL'),('GM_VAL'),('GRC_Q'),('CO_CL_STK_Q');

;WITH months AS (
    SELECT DISTINCT LEFT(COLUMN_NAME,10) AS d
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA='dbo' AND TABLE_NAME='ROI_TREND_DATA_AKA'
      AND COLUMN_NAME LIKE '[12][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\_%' ESCAPE '\'
), ranked AS (
    SELECT d, RIGHT('00'+CAST(ROW_NUMBER() OVER (ORDER BY d DESC)-1 AS VARCHAR(2)),2) AS idx
    FROM months
)
SELECT @cols = @cols + ', ' + QUOTENAME(r.d+'_'+mt.m) + ' AS [M'+r.idx+'_'+mt.m+']'
FROM ranked r CROSS JOIN @metrics mt;

DECLARE @sql NVARCHAR(MAX) =
  N'CREATE OR ALTER VIEW dbo.VW_ROI_TREND_DATA_API AS
    SELECT [ID],[SEG],[DIV],[SUB-DIV],[MAJ-CAT],[GEN-ART],[GEN-DESC],[CLR],[MRP],
           [MACRO_MVGR],[MAIN_MVGR],[FAB],[ACT-VND-CD],[M-VND-CD]' + @cols + N'
    FROM dbo.ROI_TREND_DATA_AKA;';
EXEC sys.sp_executesql @sql;
```

Then in `backend/entities.json` keep the entity name but repoint it, and redeploy:

```json
{ "name": "ROI_TREND_DATA_AKA", "real-name": "[dbo].[VW_ROI_TREND_DATA_API]" }
```

(Consumers move from `2026-05-31_SALE_QTY` to the stable `M00_SALE_QTY`. Map M00…M18
to actual months via the existing dimension/date metadata.)

### Option C (cleanest data model, largest change): normalize to long format
Replace the column-per-month layout with rows: `(…dimensions…, MONTH_END date,
STK_0001_QTY, SALE_QTY, SALE_VAL, GM_VAL, GRC_Q, CO_CL_STK_Q)`. Schema becomes fully
static; filter by `?$filter=MONTH_END eq ...`. Requires ETL + downstream consumer changes.

---

## Recommendation
Restart now (Fix 1) to restore service, then adopt **Option A** as the permanent
guard (one line in the monthly roll job). Move to **Option B/C** if a stable public
API contract for this dataset is needed longer-term.
