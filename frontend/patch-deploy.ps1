$file = "d:\DAB_Project\DAB Project\DAB_FULL\frontend\index.html"
$content = [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8)

$old = @'
                // Show animated progress bar (0 to 100% over 2 minutes)
                progressFill.style.width = '0%';
                progressFill.textContent = '0%';
                progressStatus.innerHTML = '<div class="spinner"></div>Deploying to Azure... Please wait (~2 minutes)';
                
                // Animate progress bar smoothly over 120 seconds
                let currentProgress = 0;
                const progressInterval = setInterval(() => {
                    currentProgress += 1;
                    if (currentProgress <= 100) {
                        progressFill.style.width = currentProgress + '%';
                        progressFill.textContent = currentProgress + '%';
                    }
                }, 1200); // 120 seconds / 100 steps = 1.2 seconds per step
                
                // Start deployment (blocks for ~2 minutes)
                const response = await fetch(`${API_URL}/deploy`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ version: version })
                });
                
                // Clear progress animation
                clearInterval(progressInterval);
'@

$new = @'
                // Real-time progress via polling /api/deploy/status
                progressFill.style.width = '0%';
                progressFill.textContent = '0%';
                progressStatus.innerHTML = '<div class="spinner"></div> Starting deployment...';

                const deployPromise = fetch(`${API_URL}/deploy`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ version: version })
                });

                // Poll every second for REAL step updates
                const pollInterval = setInterval(async () => {
                    try {
                        const sr = await fetch(`${API_URL}/deploy/status`);
                        if (!sr.ok) return;
                        const s = await sr.json();
                        if (s.progress !== undefined) {
                            progressFill.style.width = s.progress + '%';
                            progressFill.textContent = s.progress + '%';
                        }
                        if (s.step) {
                            const d = s.detail ? '<br><small style="color:#9ca3af">' + s.detail + '</small>' : '';
                            progressStatus.innerHTML = '<div class="spinner"></div> [' + (s.time||'') + '] ' + s.step + d;
                        }
                    } catch(e) {}
                }, 1000);

                const response = await deployPromise;
                clearInterval(pollInterval);
'@

# Also fix broken success/error toast lines
$oldSuccess = @'
                if (data.success) {
                    // Show completion
                    progressFill.style.width = '100%';
                    progressFill.textContent = '100%';
                    progressStatus.innerHTML = '<div class="spinner"></div>Deployment complete!';
                    
                    setTimeout(() => {
                        progressContainer.style.display = 'none';
                        progressFill.style.width = '0%';
                        showToast(`âœ… Deployment ${version} completed successfully!\nTotal entities deployed: ${displayEntities.length}`, 'success');
                    }, 2000);
                } else {
                    progressContainer.style.display = 'none';
                    showToast(`âŒ ${data.message || 'Deployment failed'}`, 'error');
                }
            } catch (error) {
                console.error('Deployment error:', error);
                progressContainer.style.display = 'none';
                showToast(`âŒ Failed to deploy: ${error.message}`, 'error');
            }
'@

$newSuccess = @'
                if (data.success) {
                    progressFill.style.width = '100%';
                    progressFill.textContent = '100%';
                    progressStatus.innerHTML = '&#10003; Deployment complete!';
                    setTimeout(() => {
                        progressContainer.style.display = 'none';
                        progressFill.style.width = '0%';
                        showToast('Deployment ' + version + ' completed! Entities: ' + displayEntities.length, 'success');
                    }, 3000);
                } else {
                    progressContainer.style.display = 'none';
                    showToast(data.message || 'Deployment failed', 'error');
                }
            } catch (error) {
                console.error('Deployment error:', error);
                progressContainer.style.display = 'none';
                showToast('Failed to deploy: ' + error.message, 'error');
            }
'@

if ($content.Contains($old)) {
    $content = $content.Replace($old, $new)
    Write-Host "Block 1 (progress) replaced OK" -ForegroundColor Green
} else {
    Write-Host "Block 1 NOT FOUND" -ForegroundColor Red
    exit 1
}

if ($content.Contains($oldSuccess)) {
    $content = $content.Replace($oldSuccess, $newSuccess)
    Write-Host "Block 2 (success/error) replaced OK" -ForegroundColor Green
} else {
    Write-Host "Block 2 NOT FOUND - toast lines may already be clean" -ForegroundColor Yellow
}

[System.IO.File]::WriteAllText($file, $content, [System.Text.Encoding]::UTF8)
Write-Host "Saved $file" -ForegroundColor Green

# Copy to IIS
Copy-Item $file "C:\inetpub\wwwroot\deployment-manager\index.html" -Force
Write-Host "Deployed to IIS" -ForegroundColor Green
