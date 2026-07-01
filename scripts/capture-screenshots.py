"""Capture README demo workflow GIF from staging HTML pages."""

from __future__ import annotations

import http.server
import shutil
import socketserver
import threading
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont
from playwright.sync_api import sync_playwright

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
OUTPUT_DIR = REPO_ROOT / "ReadmeFiles"
FRAMES_DIR = OUTPUT_DIR / ".capture-frames"
GIF_PATH = OUTPUT_DIR / "demo-workflow.gif"

GIF_WIDTH = 720
FRAME_DURATION_MS = 2500

CAPTURES = [
    ("01-agent-start.html", "frame-01.png", "Step 1 of 4 — Start session"),
    ("02-agent-verify.html", "frame-02.png", "Step 2 of 4 — Verify yourself"),
    ("03-agent-share-link.html", "frame-03.png", "Step 3 of 4 — Send link to caller"),
    ("04-agent-complete.html", "frame-04.png", "Step 4 of 4 — Verification complete"),
    ("05-caller-confirm-agent.html", "frame-05.png", "Caller — Confirm agent"),
    ("06-caller-verify.html", "frame-06.png", "Caller — Verify identity"),
    ("07-caller-complete.html", "frame-07.png", "Caller — Complete"),
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


def resize_frame(image: Image.Image, target_width: int) -> Image.Image:
    ratio = target_width / image.width
    target_height = int(image.height * ratio)
    return image.resize((target_width, target_height), Image.Resampling.LANCZOS)


def add_step_label(image: Image.Image, label: str) -> Image.Image:
    overlay = image.copy().convert("RGBA")
    draw = ImageDraw.Draw(overlay)
    padding_x, padding_y = 16, 12
    font_size = max(14, image.width // 45)

    try:
        font = ImageFont.truetype("segoeui.ttf", font_size)
    except OSError:
        try:
            font = ImageFont.truetype("arial.ttf", font_size)
        except OSError:
            font = ImageFont.load_default()

    text_bbox = draw.textbbox((0, 0), label, font=font)
    text_width = text_bbox[2] - text_bbox[0]
    text_height = text_bbox[3] - text_bbox[1]
    box_width = text_width + padding_x * 2
    box_height = text_height + padding_y * 2
    footer_height = 56
    bottom_gap = 12
    x0 = 20
    y1 = image.height - footer_height - bottom_gap
    y0 = y1 - box_height
    x1 = x0 + box_width

    draw.rounded_rectangle((x0, y0, x1, y1), radius=8, fill=(59, 46, 88, 220))
    draw.text((x0 + padding_x, y0 + padding_y - text_bbox[1]), label, fill="white", font=font)
    return overlay.convert("RGB")


def build_gif(frame_paths: list[Path], labels: list[str], output_path: Path) -> None:
    frames: list[Image.Image] = []
    for path, label in zip(frame_paths, labels, strict=True):
        image = Image.open(path)
        resized = resize_frame(image, GIF_WIDTH)
        labeled = add_step_label(resized, label)
        frames.append(labeled.convert("P", palette=Image.Palette.ADAPTIVE, colors=256))

    frames[0].save(
        output_path,
        save_all=True,
        append_images=frames[1:],
        duration=FRAME_DURATION_MS,
        loop=0,
        optimize=True,
    )


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    if FRAMES_DIR.exists():
        shutil.rmtree(FRAMES_DIR)
    FRAMES_DIR.mkdir(parents=True)

    server, base_url = start_server()
    frame_paths: list[Path] = []
    labels: list[str] = []

    try:
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch()
            context = browser.new_context(
                viewport={"width": 1280, "height": 900},
                device_scale_factor=2,
            )
            page = context.new_page()

            for staging, frame_name, label in CAPTURES:
                url = f"{base_url}/scripts/screenshot-staging/{staging}"
                page.goto(url, wait_until="networkidle")
                page.wait_for_timeout(300)
                frame_path = FRAMES_DIR / frame_name
                page.screenshot(path=str(frame_path), full_page=True)
                frame_paths.append(frame_path)
                labels.append(label)
                print(f"Captured {frame_path.name}")

            browser.close()

        build_gif(frame_paths, labels, GIF_PATH)
        size_kb = GIF_PATH.stat().st_size / 1024
        print(f"Wrote {GIF_PATH} ({size_kb:.1f} KB)")
    finally:
        server.shutdown()


if __name__ == "__main__":
    main()
