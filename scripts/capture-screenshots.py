"""Capture README demo screenshots from staging HTML pages."""

from __future__ import annotations

import http.server
import socketserver
import threading
from pathlib import Path

from playwright.sync_api import sync_playwright

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
STAGING_DIR = SCRIPT_DIR / "screenshot-staging"
OUTPUT_DIR = REPO_ROOT / "ReadmeFiles"

CAPTURES = [
    ("01-agent-start.html", "demo-01-agent-start.png"),
    ("02-agent-verify.html", "demo-02-agent-verify.png"),
    ("03-agent-share-link.html", "demo-03-agent-share-link.png"),
    ("04-agent-complete.html", "demo-04-agent-complete.png"),
    ("05-caller-confirm-agent.html", "demo-05-caller-confirm-agent.png"),
    ("06-caller-verify.html", "demo-06-caller-verify.png"),
    ("07-caller-complete.html", "demo-07-caller-complete.png"),
]

MIME_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".map": "application/json",
    ".woff": "font/woff",
    ".woff2": "font/woff2",
    ".ttf": "font/ttf",
    ".svg": "image/svg+xml",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".ico": "image/x-icon",
}


class RepoHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(REPO_ROOT), **kwargs)

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if not (
            path.startswith("/scripts/screenshot-staging/")
            or path.startswith("/wwwroot/")
        ):
            self.send_error(404)
            return

        file_path = (REPO_ROOT / path.lstrip("/")).resolve()
        if not str(file_path).startswith(str(REPO_ROOT.resolve())):
            self.send_error(403)
            return
        if not file_path.is_file():
            self.send_error(404)
            return

        content_type = MIME_TYPES.get(file_path.suffix.lower(), "application/octet-stream")
        data = file_path.read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, format, *args):
        return


def start_server() -> tuple[socketserver.TCPServer, str]:
    server = socketserver.TCPServer(("127.0.0.1", 0), RepoHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    host, port = server.server_address
    return server, f"http://{host}:{port}"


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    server, base_url = start_server()

    try:
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch()
            context = browser.new_context(
                viewport={"width": 1280, "height": 900},
                device_scale_factor=2,
            )
            page = context.new_page()

            for staging, output in CAPTURES:
                url = f"{base_url}/scripts/screenshot-staging/{staging}"
                page.goto(url, wait_until="networkidle")
                page.wait_for_timeout(300)
                out_path = OUTPUT_DIR / output
                page.screenshot(path=str(out_path), full_page=True)
                print(f"Wrote {out_path}")

            browser.close()
    finally:
        server.shutdown()


if __name__ == "__main__":
    main()
