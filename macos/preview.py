#!/usr/bin/env python3
"""Serve the macOS UI preview locally. No build step or third-party packages."""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import webbrowser


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=4178)
    parser.add_argument("--open", action="store_true", help="open the preview in your browser")
    args = parser.parse_args()
    directory = Path(__file__).resolve().parent / "preview"
    handler = partial(SimpleHTTPRequestHandler, directory=str(directory))
    try:
        server = ThreadingHTTPServer(("127.0.0.1", args.port), handler)
    except OSError as error:
        parser.exit(1, f"Couldn’t start the preview: {error}. Try --port with another port.\n")
    url = f"http://127.0.0.1:{server.server_port}"
    print(f"Linker macOS preview → {url}\nPress Ctrl+C to stop.", flush=True)
    if args.open:
        webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
