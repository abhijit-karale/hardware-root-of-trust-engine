#!/usr/bin/env python3
"""
================================================================================
Hardware Root-of-Trust (RoT) Engine - Interactive Dashboard Server & Launcher
Target: SkyWater 130nm @ 200 MHz | Architect & DV Lead: Abhijit Karale
================================================================================
"""

import http.server
import socketserver
import webbrowser
import os
import sys

PORT = 8080

def main():
    # Ensure current directory is repository root
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(repo_root)

    dashboard_dir = os.path.join(repo_root, "dashboard")
    if not os.path.exists(dashboard_dir):
        print(f"[ERROR] Dashboard directory not found at {dashboard_dir}")
        sys.exit(1)

    print("=" * 80)
    print(" HARDWARE ROOT-OF-TRUST (RoT) ENGINE - INTERACTIVE DASHBOARD SERVER")
    print(" Target: SkyWater 130nm @ 200 MHz | Candidate: Abhijit Karale")
    print("=" * 80)
    print(f"[INFO] Serving repository at http://localhost:{PORT}/dashboard/")
    print(f"[INFO] Opening browser...")

    url = f"http://localhost:{PORT}/dashboard/"
    webbrowser.open(url)

    Handler = http.server.SimpleHTTPRequestHandler
    with socketserver.TCPServer(("", PORT), Handler) as httpd:
        print(f"[INFO] Server active on port {PORT}. Press Ctrl+C to terminate.")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\n[INFO] Dashboard server stopped.")

if __name__ == '__main__':
    main()
