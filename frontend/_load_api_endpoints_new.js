        }

        function loadApiEndpoints() {
            const entity = document.getElementById('apiEntitySelect').value;
            if (!entity) {
                document.getElementById('apiEndpointsContainer').style.display = 'none';
                return;
            }

            Object.keys(_builtQueryUrls).forEach(k => delete _builtQueryUrls[k]);

            const baseUrl = 'https://my-dab-app.azurewebsites.net/api';
            const container = document.getElementById('apiEndpointsContainer');
            const operationsDiv = document.getElementById('apiOperations');
            const entityUrl = `${baseUrl}/${entity}`;
            const escapedUrl = entityUrl.replace(/'/g, "\\'");

            const operations = [
                {
                    method: 'GET',
                    color: '#10b981',
                    title: 'List All Records',
                    url: entityUrl,
                    description: 'Retrieve all records. Supports OData: <code style="background:#111827;padding:2px 5px;border-radius:3px;color:#10b981;font-size:11px;">$filter</code> <code style="background:#111827;padding:2px 5px;border-radius:3px;color:#10b981;font-size:11px;">$orderby</code> <code style="background:#111827;padding:2px 5px;border-radius:3px;color:#10b981;font-size:11px;">$first</code> <code style="background:#111827;padding:2px 5px;border-radius:3px;color:#10b981;font-size:11px;">$skip</code>',
                    examples: [
                        { label: 'First 10 records', param: '?$first=10' },
                        { label: 'Order by ID desc', param: '?$orderby=Id desc' },
                        { label: 'Filter active', param: "?$filter=status eq 'Active'" },
                        { label: 'Select fields', param: '?$select=Id,name' },
                        { label: 'Skip first 5', param: '?$skip=5' },
                        { label: 'First 5 ordered', param: '?$first=5&$orderby=Id desc' }
                    ]
                }
            ];

            let html = '';
            operations.forEach((op, opIndex) => {
                const opUrlEsc = op.url.replace(/'/g, "\\'");
                html += `
                    <div style="background: #1f2937; border-radius: 10px; padding: 18px 20px; margin-bottom: 16px; border: 1px solid #374151;">
                        <div style="display: flex; align-items: center; gap: 12px; margin-bottom: 10px;">
                            <span style="background: ${op.color}; color: white; padding: 4px 14px; border-radius: 5px; font-weight: 700; font-size: 12px; font-family: 'Courier New', monospace; letter-spacing: 0.05em;">${op.method}</span>
                            <h4 style="margin: 0; color: #f3f4f6; font-size: 15px; font-weight: 600; flex: 1;">${op.title}</h4>
                        </div>
                        <p style="color: #9ca3af; font-size: 13px; margin: 0 0 14px 0; line-height: 1.6;">${op.description}</p>

                        <div style="display: flex; align-items: center; gap: 10px; background: #111827; padding: 10px 14px; border-radius: 8px; margin-bottom: 16px; border: 1px solid #374151;">
                            <code style="color: #10b981; font-size: 13px; flex: 1; word-break: break-all; font-family: 'Courier New', monospace;">${op.url}</code>
                            <button class="btn-info" onclick="copyText('${opUrlEsc}')" style="padding: 6px 14px; font-size: 12px; white-space: nowrap; flex-shrink: 0;">
                                &#128203; Copy URL
                            </button>
                        </div>`;

                if (op.examples) {
                    html += `
                        <div style="margin-bottom: 16px;">
                            <div style="display: flex; align-items: center; gap: 10px; margin-bottom: 10px;">
                                <span style="color: #d1d5db; font-size: 13px; font-weight: 600;">&#128295; Filter Builder</span>
                                <button onclick="loadFieldNames(${opIndex}, '${opUrlEsc}')" class="btn-info" style="padding: 5px 12px; font-size: 12px;">
                                    Load Fields
                                </button>
                                <span id="fieldStatus_${opIndex}" style="color: #6b7280; font-size: 12px;"></span>
                            </div>
                            <div style="background: #111827; padding: 14px; border-radius: 8px; border: 1px solid #374151; margin-bottom: 12px;">
                                <div style="display: grid; grid-template-columns: 1fr 110px 1fr; gap: 8px; margin-bottom: 8px;">
                                    <select id="filterField_${opIndex}"
                                        style="padding: 7px 10px; background: #1f2937; border: 1px solid #4b5563; border-radius: 6px; color: #e5e7eb; font-size: 12px; outline: none;">
                                        <option value="">Click "Load Fields" first...</option>
                                    </select>
                                    <select id="filterOp_${opIndex}"
                                        style="padding: 7px 10px; background: #1f2937; border: 1px solid #4b5563; border-radius: 6px; color: #e5e7eb; font-size: 12px; outline: none;">
                                        <option value="eq">equals</option>
                                        <option value="ne">not equals</option>
                                        <option value="gt">greater than</option>
                                        <option value="lt">less than</option>
                                        <option value="ge">&ge; greater/equal</option>
                                        <option value="le">&le; less/equal</option>
                                        <option value="contains">contains</option>
                                    </select>
                                    <input type="text" id="filterValue_${opIndex}" placeholder="Value (e.g., 0000200003)"
                                        style="padding: 7px 10px; background: #1f2937; border: 1px solid #4b5563; border-radius: 6px; color: #e5e7eb; font-size: 12px; outline: none;">
                                </div>
                                <div style="display: grid; grid-template-columns: 1fr 1fr 90px; gap: 8px; margin-bottom: 10px;">
                                    <input type="number" id="filterTop_${opIndex}" placeholder="Limit (e.g. 100)" min="1"
                                        style="padding: 7px 10px; background: #1f2937; border: 1px solid #4b5563; border-radius: 6px; color: #e5e7eb; font-size: 12px; outline: none;">
                                    <select id="filterOrderBy_${opIndex}"
                                        style="padding: 7px 10px; background: #1f2937; border: 1px solid #4b5563; border-radius: 6px; color: #e5e7eb; font-size: 12px; outline: none;">
                                        <option value="">Order by field...</option>
                                    </select>
                                    <select id="filterOrderDir_${opIndex}"
                                        style="padding: 7px 10px; background: #1f2937; border: 1px solid #4b5563; border-radius: 6px; color: #e5e7eb; font-size: 12px; outline: none;">
                                        <option value="asc">&#8593; asc</option>
                                        <option value="desc">&#8595; desc</option>
                                    </select>
                                </div>
                                <div style="display: flex; gap: 8px;">
                                    <button onclick="buildFilter(${opIndex}, '${opUrlEsc}')" class="btn-info" style="flex: 1; padding: 7px 12px; font-size: 12px;">
                                        &#9881; Build Query URL
                                    </button>
                                    <button onclick="clearFilter(${opIndex})" class="btn-warning" style="padding: 7px 14px; font-size: 12px;">
                                        &#10005; Clear
                                    </button>
                                </div>
                                <div id="builtQuery_${opIndex}" style="display: none; margin-top: 12px; padding: 10px 12px; background: #0a1628; border-radius: 6px; border: 1px solid #10b981;">
                                    <div style="color: #6ee7b7; font-size: 11px; margin-bottom: 6px; font-weight: 600;">&#10003; Generated URL &mdash; click Test below to use it:</div>
                                    <div style="display: flex; align-items: flex-start; gap: 8px;">
                                        <code id="queryUrl_${opIndex}" style="color: #10b981; font-size: 12px; word-break: break-all; flex: 1; line-height: 1.6;"></code>
                                        <button onclick="copyText(document.getElementById('queryUrl_${opIndex}').textContent)" class="btn-info" style="padding: 4px 10px; font-size: 11px; flex-shrink: 0; white-space: nowrap;">&#128203; Copy</button>
                                    </div>
                                </div>
                            </div>
                            <div style="background: #111827; padding: 12px 14px; border-radius: 8px; border: 1px solid #374151;">
                                <div style="color: #9ca3af; font-size: 12px; font-weight: 600; margin-bottom: 8px; text-transform: uppercase; letter-spacing: 0.05em;">&#9889; Quick Examples:</div>
                                <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 6px;">`;

                    op.examples.forEach(ex => {
                        const epEsc = (op.url + ex.param).replace(/'/g, "\\'");
                        html += `
                                    <div style="display: flex; align-items: center; justify-content: space-between; background: #1f2937; padding: 7px 10px; border-radius: 6px; gap: 8px;">
                                        <span style="color: #9ca3af; font-size: 12px;">${ex.label}</span>
                                        <div style="display: flex; align-items: center; gap: 6px; flex-shrink: 0;">
                                            <code style="color: #10b981; font-size: 11px; font-family: 'Courier New', monospace; white-space: nowrap;">${ex.param}</code>
                                            <button onclick="copyText('${epEsc}')" title="Copy full URL" style="background: #374151; border: none; color: #9ca3af; cursor: pointer; border-radius: 4px; padding: 2px 6px; font-size: 11px;" onmouseover="this.style.color='#10b981'" onmouseout="this.style.color='#9ca3af'">&#128203;</button>
                                        </div>
                                    </div>`;
                    });
                    html += `
                                </div>
                            </div>
                        </div>`;
                }

                html += `
                        <button id="testBtn_${opIndex}" class="btn-success" onclick="testApiEndpoint('${op.method}', '${opUrlEsc}', '', '', ${opIndex})"
                            style="width: 100%; padding: 11px; font-size: 14px; font-weight: 600; letter-spacing: 0.02em;">
                            &#9654; Test This Endpoint
                        </button>
                    </div>`;
            });

            operationsDiv.innerHTML = html;
            container.style.display = 'flex';
            container.style.flexDirection = 'column';
            document.getElementById('apiTestResult').style.display = 'none';
        }

