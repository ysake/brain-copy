document.addEventListener('DOMContentLoaded', function() {
    const fileInput = document.getElementById('fileInput');
    const clusterBtn = document.getElementById('clusterBtn');
    const kValue = document.getElementById('kValue');
    const svg = d3.select('#clusterMap');

    let rawPoints = [];
    let tooltip = null;

    fileInput.addEventListener('change', function(e) {
        const file = e.target.files[0];
        if (!file) return;
        const reader = new FileReader();
        reader.onload = function(e) {
            parseCSV(e.target.result);
        };
        reader.readAsText(file);
    });

    function parseCSVRow(line) {
        const out = [];
        let cur = '';
        let inQuote = false;
        for (let i = 0; i < line.length; i++) {
            const c = line[i];
            if (c === '"') inQuote = !inQuote;
            else if (c === ',' && !inQuote) {
                out.push(cur.trim());
                cur = '';
            } else cur += c;
        }
        out.push(cur.trim());
        return out;
    }

    function parseCSV(csvText) {
        const lines = csvText.split('\n').filter(line => line.trim() !== '');
        if (lines.length < 2) {
            alert('CSV に有効な行がありません');
            return;
        }
        const header = parseCSVRow(lines[0]);
        const xIndex = header.indexOf('x');
        const yIndex = header.indexOf('y');
        const textIndex = header.indexOf('text');
        const clusterIndex = header.indexOf('cluster');
        const connectedToIndex = header.indexOf('connected_to');
        if (xIndex === -1 || yIndex === -1) {
            alert('CSV のヘッダーに x, y 列が必要です');
            return;
        }
        rawPoints = [];
        for (let i = 1; i < lines.length; i++) {
            const values = parseCSVRow(lines[i]);
            const x = parseFloat(values[xIndex]);
            const y = parseFloat(values[yIndex]);
            if (Number.isNaN(x) || Number.isNaN(y)) continue;
            const text = textIndex !== -1 ? values[textIndex] : '';
            const cluster = clusterIndex !== -1 && !Number.isNaN(parseInt(values[clusterIndex], 10))
                ? parseInt(values[clusterIndex], 10) : 0;
            let connected_to = [];
            if (connectedToIndex !== -1 && values[connectedToIndex]) {
                connected_to = values[connectedToIndex].split(';')
                    .map(s => parseInt(s.trim(), 10))
                    .filter(n => !Number.isNaN(n));
            }
            rawPoints.push({ x, y, text, cluster, connected_to });
        }
        alert(`Loaded ${rawPoints.length} data points`);
        visualizeNetwork();
    }

    clusterBtn.addEventListener('click', function() {
        if (rawPoints.length === 0) {
            alert('まず CSV をアップロードしてください');
            return;
        }
        visualizeNetwork();
    });

    function visualizeNetwork() {
        svg.selectAll('*').remove();
        if (rawPoints.length === 0) return;

        const margin = 40;
        const width = Math.max(400, svg.node().getBoundingClientRect().width - margin * 2);
        const height = Math.max(400, svg.node().getBoundingClientRect().height - margin * 2);

        // Tooltip (HTML overlay)
        if (!tooltip) {
            tooltip = document.createElement('div');
            tooltip.className = 'node-tooltip';
            document.body.appendChild(tooltip);
        }
        const showTooltip = (event, text) => {
            if (!tooltip) return;
            tooltip.textContent = text || '';
            tooltip.style.display = 'block';
            const pad = 12;
            const x = Math.min(window.innerWidth - 40, event.clientX + pad);
            const y = Math.min(window.innerHeight - 40, event.clientY + pad);
            tooltip.style.left = `${x}px`;
            tooltip.style.top = `${y}px`;
        };
        const moveTooltip = (event) => {
            if (!tooltip || tooltip.style.display === 'none') return;
            const pad = 12;
            const x = Math.min(window.innerWidth - 40, event.clientX + pad);
            const y = Math.min(window.innerHeight - 40, event.clientY + pad);
            tooltip.style.left = `${x}px`;
            tooltip.style.top = `${y}px`;
        };
        const hideTooltip = () => {
            if (!tooltip) return;
            tooltip.style.display = 'none';
        };

        // リンク構築（重複なし: i < j のときだけ）
        const linkSet = new Set();
        const links = [];
        rawPoints.forEach((p, i) => {
            (p.connected_to || []).forEach(j => {
                if (j >= 0 && j < rawPoints.length) {
                    const key = i < j ? `${i}-${j}` : `${j}-${i}`;
                    if (!linkSet.has(key)) {
                        linkSet.add(key);
                        links.push({ source: i, target: j });
                    }
                }
            });
        });

        // 次数 = 接続数（無向なのでリンク数でカウント）
        const degree = rawPoints.map((_, i) => {
            let d = (rawPoints[i].connected_to || []).length;
            rawPoints.forEach((p, j) => {
                if ((p.connected_to || []).indexOf(i) >= 0) d++;
            });
            return d;
        });
        const minD = Math.min(...degree);
        const maxD = Math.max(...degree);
        const radiusScale = d3.scaleSqrt()
            .domain([minD, maxD])
            .range([2, 14]);
        if (minD === maxD) radiusScale.range([4, 10]);

        const nodes = rawPoints.map((p, i) => ({
            id: i,
            text: p.text,
            degree: degree[i],
            r: radiusScale(degree[i]),
        }));

        const linkObjs = links.map(l => ({
            source: l.source,
            target: l.target,
        }));

        const simulation = d3.forceSimulation(nodes)
            .force('link', d3.forceLink(linkObjs).id(d => d.id).distance(30).strength(0.5))
            .force('charge', d3.forceManyBody().strength(-400))
            .force('center', d3.forceCenter(width / 2 + margin, height / 2 + margin))
            .force('collision', d3.forceCollide().radius(d => d.r + 2));

        // Zoom / Pan
        const viewport = svg.append('g').attr('class', 'viewport');
        const zoom = d3.zoom()
            .scaleExtent([0.2, 6])
            .on('zoom', (event) => {
                viewport.attr('transform', event.transform);
            });
        svg.call(zoom);

        // Root group (kept inside zoomable viewport)
        const g = viewport.append('g').attr('transform', `translate(${margin},${margin})`);

        const link = g.append('g')
            .selectAll('line')
            .data(linkObjs)
            .join('line')
            .attr('stroke', '#999')
            .attr('stroke-opacity', 0.5)
            .attr('stroke-width', 1);

        // 常時ラベル（次数が高い上位ノードだけ）
        const degreesSorted = [...degree].sort(d3.ascending);
        const labelMin = d3.quantile(degreesSorted, 0.9) ?? 1; // 上位10%目安
        const labelNodes = nodes
            .filter(n => n.degree >= labelMin && n.degree > 0 && (n.text || '').trim() !== '')
            .sort((a, b) => b.degree - a.degree)
            .slice(0, 25);
        const labels = g.append('g')
            .selectAll('text')
            .data(labelNodes)
            .join('text')
            .attr('class', 'node-label')
            .text(d => {
                const t = (rawPoints[d.id] && rawPoints[d.id].text) ? rawPoints[d.id].text : '';
                return t.length > 24 ? t.slice(0, 24) + '…' : t;
            });

        const node = g.append('g')
            .selectAll('circle')
            .data(nodes)
            .join('circle')
            .attr('r', d => d.r)
            .attr('fill', '#333')
            .attr('stroke', '#555')
            .attr('stroke-width', 0.5)
            .attr('cursor', 'pointer')
            .on('mouseover', function(event, d) {
                d3.select(this).attr('stroke', '#111').attr('stroke-width', 2);
                const fullText = (rawPoints[d.id] && rawPoints[d.id].text) ? rawPoints[d.id].text : '';
                showTooltip(event, fullText);
            })
            .on('mousemove', function(event) {
                moveTooltip(event);
            })
            .on('mouseout', function() {
                d3.select(this).attr('stroke', '#555').attr('stroke-width', 0.5);
                hideTooltip();
            })
            .call(d3.drag()
                .on('start', dragstarted)
                .on('drag', dragged)
                .on('end', dragended));

        // 予備: ネイティブツールチップ（環境によってはHTML tooltipが出ない場合）
        node.append('title').text(d => (rawPoints[d.id] && rawPoints[d.id].text) || '');

        simulation.on('tick', () => {
            link
                .attr('x1', d => d.source.x)
                .attr('y1', d => d.source.y)
                .attr('x2', d => d.target.x)
                .attr('y2', d => d.target.y);
            node
                .attr('cx', d => d.x)
                .attr('cy', d => d.y);
            labels
                .attr('x', d => d.x + (d.r + 3))
                .attr('y', d => d.y + 3);
        });

        function dragstarted(event) {
            if (!event.active) simulation.alphaTarget(0.3).restart();
            if (event.sourceEvent) event.sourceEvent.stopPropagation(); // zoom と競合しないように
            event.subject.fx = event.subject.x;
            event.subject.fy = event.subject.y;
        }
        function dragged(event) {
            event.subject.fx = event.x;
            event.subject.fy = event.y;
        }
        function dragended(event) {
            if (!event.active) simulation.alphaTarget(0);
            event.subject.fx = null;
            event.subject.fy = null;
        }
    }
});
