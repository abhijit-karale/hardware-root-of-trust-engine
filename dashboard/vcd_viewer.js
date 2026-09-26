/**
 * Interactive Digital Logic Analyzer & VCD Waveform Viewer
 * Hardware Root-of-Trust (RoT) Engine - SkyWater 130nm @ 200 MHz
 * Engineer: Abhijit Karale
 */

class VCDViewer {
    constructor(canvasId, timelineContainerId) {
        this.canvas = document.getElementById(canvasId);
        this.ctx = this.canvas.getContext('2d');
        this.signals = window.ROT_WAVEFORM_CONFIG.signals;
        this.events = window.ROT_WAVEFORM_EVENTS;
        this.clockPeriod = window.ROT_WAVEFORM_CONFIG.clock_period_ns; // 5.0 ns
        this.totalTime = window.ROT_WAVEFORM_CONFIG.total_time_ns;   // 250 ns
        
        // Viewport and zoom state
        this.zoom = 1.0;
        this.offsetX = 0; // in nanoseconds
        this.sidebarWidth = 240;
        this.rowHeight = 36;
        this.headerHeight = 40;
        
        // Time Cursors
        this.cursorT1 = 60.0;  // AES start
        this.cursorT2 = 130.0; // AES finish (Delta = 70.0 ns = 14 cycles)
        this.activeCursor = null;
        this.hoverTime = null;
        
        this.initEventListeners();
        this.resize();
    }

    resize() {
        const rect = this.canvas.parentElement.getBoundingClientRect();
        this.canvas.width = Math.max(900, rect.width);
        this.canvas.height = this.headerHeight + this.signals.length * this.rowHeight + 30;
        this.render();
    }

    initEventListeners() {
        window.addEventListener('resize', () => this.resize());
        
        // Mouse navigation
        let isDragging = false;
        let startX = 0;
        let startOffset = 0;

        this.canvas.addEventListener('mousedown', (e) => {
            const rect = this.canvas.getBoundingClientRect();
            const x = e.clientX - rect.left;
            if (x < this.sidebarWidth) return;

            const t = this.xToTime(x);
            // Check if clicking near T1 or T2 (within 8px)
            const xT1 = this.timeToX(this.cursorT1);
            const xT2 = this.timeToX(this.cursorT2);
            
            if (Math.abs(x - xT1) < 10) {
                this.activeCursor = 'T1';
            } else if (Math.abs(x - xT2) < 10) {
                this.activeCursor = 'T2';
            } else {
                isDragging = true;
                startX = x;
                startOffset = this.offsetX;
            }
        });

        window.addEventListener('mousemove', (e) => {
            const rect = this.canvas.getBoundingClientRect();
            const x = e.clientX - rect.left;
            
            if (this.activeCursor) {
                const t = Math.max(0, Math.min(this.totalTime, this.xToTime(x)));
                if (this.activeCursor === 'T1') this.cursorT1 = Math.round(t * 10) / 10;
                else this.cursorT2 = Math.round(t * 10) / 10;
                this.updateDeltaBadge();
                this.render();
            } else if (isDragging) {
                const dx = x - startX;
                const dt = dx / (this.getPixelsPerNs() * this.zoom);
                this.offsetX = Math.max(0, Math.min(this.totalTime * 0.7, startOffset - dt));
                this.render();
            } else if (x >= this.sidebarWidth) {
                this.hoverTime = Math.max(0, Math.min(this.totalTime, this.xToTime(x)));
                this.render();
            }
        });

        window.addEventListener('mouseup', () => {
            this.activeCursor = null;
            isDragging = false;
        });

        this.canvas.addEventListener('wheel', (e) => {
            e.preventDefault();
            const factor = e.deltaY < 0 ? 1.15 : 0.85;
            this.zoom = Math.max(0.5, Math.min(6.0, this.zoom * factor));
            this.render();
        });
    }

    getPixelsPerNs() {
        const plotWidth = this.canvas.width - this.sidebarWidth - 40;
        return (plotWidth / this.totalTime);
    }

    timeToX(t) {
        return this.sidebarWidth + (t - this.offsetX) * this.getPixelsPerNs() * this.zoom;
    }

    xToTime(x) {
        return ((x - this.sidebarWidth) / (this.getPixelsPerNs() * this.zoom)) + this.offsetX;
    }

    zoomIn() {
        this.zoom = Math.min(6.0, this.zoom * 1.3);
        this.render();
    }

    zoomOut() {
        this.zoom = Math.max(0.5, this.zoom / 1.3);
        this.render();
    }

    resetView() {
        this.zoom = 1.0;
        this.offsetX = 0;
        this.cursorT1 = 60.0;
        this.cursorT2 = 130.0;
        this.updateDeltaBadge();
        this.render();
    }

    setCursorToAES() {
        this.cursorT1 = 60.0;
        this.cursorT2 = 130.0;
        this.updateDeltaBadge();
        this.render();
    }

    setCursorToZeroize() {
        this.cursorT1 = 210.0;
        this.cursorT2 = 215.0;
        this.updateDeltaBadge();
        this.render();
    }

    updateDeltaBadge() {
        const deltaEl = document.getElementById('waveDeltaText');
        if (deltaEl) {
            const delta = Math.abs(this.cursorT2 - this.cursorT1);
            const cycles = Math.round(delta / this.clockPeriod);
            deltaEl.innerHTML = `T1: <b>${this.cursorT1.toFixed(1)} ns</b> | T2: <b>${this.cursorT2.toFixed(1)} ns</b> | &Delta;T: <span class="accent-text"><b>${delta.toFixed(1)} ns</b> (${cycles} cycles @ 200MHz)</span>`;
        }
    }

    // Lookup signal value at time t
    getValueAtTime(sigId, t) {
        let val = null;
        for (const ev of this.events) {
            if (ev.t <= t && ev.vals && ev.vals[sigId] !== undefined) {
                val = ev.vals[sigId];
            } else if (ev.t > t) {
                break;
            }
        }
        return val;
    }

    render() {
        const ctx = this.ctx;
        const width = this.canvas.width;
        const height = this.canvas.height;

        // Clear background
        ctx.fillStyle = '#0a0d14';
        ctx.fillRect(0, 0, width, height);

        // Grid Lines & Time Ruler
        this.renderGridAndRuler();

        // Render each signal trace
        this.signals.forEach((sig, index) => {
            const y = this.headerHeight + index * this.rowHeight;
            this.renderSignalRow(sig, y, index);
        });

        // Sidebar Background & Labels
        this.renderSidebar();

        // Render Time Cursors T1 and T2
        this.renderCursor(this.cursorT1, '#f59e0b', 'T1: ' + this.cursorT1.toFixed(1) + 'ns');
        this.renderCursor(this.cursorT2, '#06b6d4', 'T2: ' + this.cursorT2.toFixed(1) + 'ns');

        // Hover Line & Value Tooltip
        if (this.hoverTime !== null && this.hoverTime >= 0 && this.hoverTime <= this.totalTime) {
            const hx = this.timeToX(this.hoverTime);
            if (hx >= this.sidebarWidth) {
                ctx.strokeStyle = 'rgba(255, 255, 255, 0.2)';
                ctx.setLineDash([2, 4]);
                ctx.beginPath();
                ctx.moveTo(hx, this.headerHeight);
                ctx.lineTo(hx, height);
                ctx.stroke();
                ctx.setLineDash([]);
            }
        }
    }

    renderGridAndRuler() {
        const ctx = this.ctx;
        const height = this.canvas.height;
        
        ctx.fillStyle = '#0f1420';
        ctx.fillRect(0, 0, this.canvas.width, this.headerHeight);
        ctx.strokeStyle = '#1e293b';
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.moveTo(0, this.headerHeight);
        ctx.lineTo(this.canvas.width, this.headerHeight);
        ctx.stroke();

        // Major ticks every 10 ns, minor ticks every 5 ns (1 clock period)
        const step = 5.0; // 5 ns
        for (let t = 0; t <= this.totalTime; t += step) {
            const x = this.timeToX(t);
            if (x < this.sidebarWidth || x > this.canvas.width) continue;

            const isMajor = (t % 20 === 0);
            ctx.strokeStyle = isMajor ? '#1e293b' : '#141c2c';
            ctx.beginPath();
            ctx.moveTo(x, this.headerHeight);
            ctx.lineTo(x, height);
            ctx.stroke();

            // Ruler Labels
            if (isMajor) {
                ctx.fillStyle = '#94a3b8';
                ctx.font = '11px "JetBrains Mono", monospace';
                ctx.textAlign = 'center';
                ctx.fillText(`${t} ns`, x, this.headerHeight - 12);
                ctx.fillStyle = '#475569';
                ctx.fillText(`C${Math.round(t / this.clockPeriod)}`, x, this.headerHeight - 26);
            }
        }
    }

    renderSignalRow(sig, y, index) {
        const ctx = this.ctx;
        const plotStart = this.sidebarWidth;
        const plotEnd = this.canvas.width;
        const midY = y + this.rowHeight / 2;
        const highY = y + 8;
        const lowY = y + this.rowHeight - 8;

        // Row background alternating
        ctx.fillStyle = index % 2 === 0 ? 'rgba(15, 23, 42, 0.4)' : 'rgba(10, 13, 20, 0.4)';
        ctx.fillRect(plotStart, y, plotEnd - plotStart, this.rowHeight);

        // Divider
        ctx.strokeStyle = '#161f30';
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.moveTo(plotStart, y + this.rowHeight);
        ctx.lineTo(plotEnd, y + this.rowHeight);
        ctx.stroke();

        ctx.strokeStyle = sig.color;
        ctx.lineWidth = 1.8;

        if (sig.type === 'clock') {
            // Draw clock toggling every 2.5 ns (half period of 5ns = 200 MHz)
            ctx.beginPath();
            let isHigh = false;
            for (let t = 0; t <= this.totalTime; t += 2.5) {
                const x = this.timeToX(t);
                const cy = isHigh ? highY : lowY;
                if (t === 0) ctx.moveTo(x, cy);
                else {
                    ctx.lineTo(x, cy); // horizontal to transition
                    isHigh = !isHigh;
                    ctx.lineTo(x, isHigh ? highY : lowY); // vertical transition
                }
            }
            ctx.stroke();
        } else if (sig.type === 'wire') {
            // Single-bit binary wire
            ctx.beginPath();
            let lastVal = '0';
            let curY = lowY;
            ctx.moveTo(this.timeToX(0), curY);

            // Collect time-sorted transitions
            const transitions = [];
            for (const ev of this.events) {
                if (ev.vals && ev.vals[sig.id] !== undefined) {
                    transitions.push({ t: ev.t, val: ev.vals[sig.id] });
                }
            }

            let currentT = 0;
            for (const tr of transitions) {
                const xPrev = this.timeToX(tr.t);
                ctx.lineTo(xPrev, curY);
                curY = (tr.val === '1') ? highY : lowY;
                ctx.lineTo(xPrev, curY);
                lastVal = tr.val;
                currentT = tr.t;
            }
            ctx.lineTo(this.timeToX(this.totalTime), curY);
            ctx.stroke();
        } else if (sig.type === 'bus') {
            // Multi-bit bus with hexagon boundaries and hex labels
            const busTransitions = [];
            for (const ev of this.events) {
                if (ev.vals && ev.vals[sig.id] !== undefined) {
                    busTransitions.push({ t: ev.t, val: ev.vals[sig.id] });
                }
            }

            for (let i = 0; i < busTransitions.length; i++) {
                const tr = busTransitions[i];
                const nextT = (i + 1 < busTransitions.length) ? busTransitions[i + 1].t : this.totalTime;
                const x1 = this.timeToX(tr.t);
                const x2 = this.timeToX(nextT);
                if (x2 < plotStart || x1 > plotEnd) continue;

                const bWidth = Math.max(1, x2 - x1);
                const taper = Math.min(6, bWidth / 4);

                // Draw hexagon bus shape
                ctx.fillStyle = 'rgba(30, 41, 59, 0.4)';
                ctx.strokeStyle = sig.color;
                ctx.beginPath();
                ctx.moveTo(x1 + taper, highY);
                ctx.lineTo(x2 - taper, highY);
                ctx.lineTo(x2, midY);
                ctx.lineTo(x2 - taper, lowY);
                ctx.lineTo(x1 + taper, lowY);
                ctx.lineTo(x1, midY);
                ctx.closePath();
                ctx.fill();
                ctx.stroke();

                // Bus label text
                if (bWidth > 28) {
                    ctx.fillStyle = '#f8fafc';
                    ctx.font = '10px "JetBrains Mono", monospace';
                    ctx.textAlign = 'center';
                    let text = tr.val;
                    if (bWidth < 80 && text.length > 8) text = text.substring(0, 6) + '..';
                    ctx.fillText(text, (x1 + x2) / 2, midY + 3);
                }
            }
        }
    }

    renderSidebar() {
        const ctx = this.ctx;
        
        // Sidebar panel
        ctx.fillStyle = '#0b0f19';
        ctx.fillRect(0, 0, this.sidebarWidth, this.canvas.height);
        
        // Vertical divider
        ctx.strokeStyle = '#1e293b';
        ctx.lineWidth = 1.5;
        ctx.beginPath();
        ctx.moveTo(this.sidebarWidth, 0);
        ctx.lineTo(this.sidebarWidth, this.canvas.height);
        ctx.stroke();

        // Header label
        ctx.fillStyle = '#64748b';
        ctx.font = '11px "Inter", sans-serif';
        ctx.textAlign = 'left';
        ctx.fillText('SIGNAL NAME', 16, this.headerHeight - 20);
        ctx.fillText('VALUE @ T1', 160, this.headerHeight - 20);

        // Signal names & current T1 value
        this.signals.forEach((sig, index) => {
            const y = this.headerHeight + index * this.rowHeight;
            const midY = y + this.rowHeight / 2;

            // Signal Color Indicator Dot
            ctx.fillStyle = sig.color;
            ctx.beginPath();
            ctx.arc(20, midY, 3.5, 0, Math.PI * 2);
            ctx.fill();

            // Name
            ctx.fillStyle = '#e2e8f0';
            ctx.font = '11px "JetBrains Mono", monospace';
            ctx.textAlign = 'left';
            ctx.fillText(sig.name, 32, midY + 4);

            // Value at T1
            const val = this.getValueAtTime(sig.id, this.cursorT1) || '0';
            ctx.fillStyle = '#38bdf8';
            let dispVal = val;
            if (dispVal.length > 8) dispVal = dispVal.substring(0, 7) + '..';
            ctx.textAlign = 'right';
            ctx.fillText(dispVal, this.sidebarWidth - 14, midY + 4);

            // Row divider in sidebar
            ctx.strokeStyle = '#131b2c';
            ctx.beginPath();
            ctx.moveTo(0, y + this.rowHeight);
            ctx.lineTo(this.sidebarWidth, y + this.rowHeight);
            ctx.stroke();
        });
    }

    renderCursor(timeNs, color, label) {
        const ctx = this.ctx;
        const x = this.timeToX(timeNs);
        if (x < this.sidebarWidth || x > this.canvas.width) return;

        // Line
        ctx.strokeStyle = color;
        ctx.lineWidth = 2;
        ctx.beginPath();
        ctx.moveTo(x, this.headerHeight);
        ctx.lineTo(x, this.canvas.height);
        ctx.stroke();

        // Flag / Badge at top
        ctx.fillStyle = color;
        ctx.beginPath();
        ctx.roundRect(x - 30, this.headerHeight - 24, 60, 20, 4);
        ctx.fill();

        ctx.fillStyle = '#0f172a';
        ctx.font = 'bold 10px "JetBrains Mono", monospace';
        ctx.textAlign = 'center';
        ctx.fillText(label, x, this.headerHeight - 10);
    }
}

window.VCDViewer = VCDViewer;
