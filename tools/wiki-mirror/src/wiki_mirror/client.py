"""A small HTTPS client: one connection per thread and host, polite spacing, retries."""

from __future__ import annotations

import http.client
import threading
import time
from dataclasses import dataclass
from urllib.parse import urljoin, urlsplit

USER_AGENT = "OpenSky-wiki-mirror/1.0 (+https://github.com/jjgroenendijk/opensky)"
MAX_REDIRECTS = 5
MAX_ATTEMPTS = 5
# Status codes worth a retry: rate limits and passing server faults.
RETRY_STATUSES = frozenset({429, 500, 502, 503, 504})


class HttpError(Exception):
    """A request failed for good, after any retries."""


@dataclass(frozen=True)
class Response:
    """The final answer to a request, after redirects."""

    url: str
    status: int
    body: bytes

    def text(self) -> str:
        """Return the body as text; a bad byte becomes U+FFFD."""
        return self.body.decode("utf-8", errors="replace")


class Http:
    """Fetches HTTPS URLs and leaves at least `min_interval` seconds between requests."""

    def __init__(self, min_interval: float) -> None:
        """Share one request clock between every thread that uses this client."""
        self._min_interval = min_interval
        self._clock_lock = threading.Lock()
        self._next_start = 0.0
        self._local = threading.local()

    def get(self, url: str) -> Response:
        """GET `url`, follow redirects, and retry passing failures with a growing wait."""
        last_error = "no attempt"
        for attempt in range(MAX_ATTEMPTS):
            try:
                response, retry_after = self._get_following_redirects(url)
            except (OSError, http.client.HTTPException) as error:
                self._drop_connection(urlsplit(url).netloc)
                last_error = f"{type(error).__name__}: {error}"
                retry_after = None
            else:
                if response.status not in RETRY_STATUSES:
                    return response
                last_error = f"HTTP {response.status}"
            time.sleep(retry_after if retry_after is not None else 2.0**attempt)
        message = f"{url}: {last_error} after {MAX_ATTEMPTS} attempts"
        raise HttpError(message)

    def _get_following_redirects(self, url: str) -> tuple[Response, float | None]:
        for _ in range(MAX_REDIRECTS + 1):
            status, location, retry_after, body = self._get_once(url)
            if status in {301, 302, 303, 307, 308} and location:
                url = urljoin(url, location)
                continue
            return Response(url=url, status=status, body=body), retry_after
        message = f"{url}: more than {MAX_REDIRECTS} redirects"
        raise HttpError(message)

    def _get_once(self, url: str) -> tuple[int, str | None, float | None, bytes]:
        parts = urlsplit(url)
        if parts.scheme != "https":
            message = f"{url}: only https URLs are fetched"
            raise HttpError(message)
        path = parts.path or "/"
        if parts.query:
            path = f"{path}?{parts.query}"
        self._wait_turn()
        connection = self._connection(parts.netloc)
        connection.request("GET", path, headers={"User-Agent": USER_AGENT})
        answer = connection.getresponse()
        body = answer.read()
        retry_after = answer.getheader("Retry-After")
        delay = float(retry_after) if retry_after and retry_after.isdigit() else None
        return answer.status, answer.getheader("Location"), delay, body

    def _wait_turn(self) -> None:
        with self._clock_lock:
            now = time.monotonic()
            start = max(now, self._next_start)
            self._next_start = start + self._min_interval
        time.sleep(start - now)

    def _connection(self, host: str) -> http.client.HTTPSConnection:
        connections = self._connections()
        if host not in connections:
            connections[host] = http.client.HTTPSConnection(host, timeout=60)
        return connections[host]

    def _drop_connection(self, host: str) -> None:
        connection = self._connections().pop(host, None)
        if connection is not None:
            connection.close()

    def _connections(self) -> dict[str, http.client.HTTPSConnection]:
        if not hasattr(self._local, "connections"):
            self._local.connections = {}
        return self._local.connections
