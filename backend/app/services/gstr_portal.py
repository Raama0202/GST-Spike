"""GSTR portal client abstraction.

Excel uploads are the default free path. When GSP credentials are configured,
HttpGspClient can fetch 2A/2B without changing the matching pipeline.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any

import httpx

from app.core.config import settings


class GstrPortalClient(ABC):
    @abstractmethod
    async def fetch_2a(self, gstin: str, period: str) -> list[dict[str, Any]]:
        raise NotImplementedError

    @abstractmethod
    async def fetch_2b(self, gstin: str, period: str) -> list[dict[str, Any]]:
        raise NotImplementedError

    @property
    def configured(self) -> bool:
        return False


class ExcelGstrClient(GstrPortalClient):
    """Placeholder client — Excel is uploaded via the import endpoint."""

    async def fetch_2a(self, gstin: str, period: str) -> list[dict[str, Any]]:
        raise RuntimeError("ExcelGstrClient does not fetch remotely; upload a file instead.")

    async def fetch_2b(self, gstin: str, period: str) -> list[dict[str, Any]]:
        raise RuntimeError("ExcelGstrClient does not fetch remotely; upload a file instead.")


class HttpGspClient(GstrPortalClient):
    """Thin HTTP adapter for a future paid GSP.

    Expected env:
      GSP_BASE_URL, GSP_CLIENT_ID, GSP_CLIENT_SECRET
    The GSP must expose:
      POST {base}/oauth/token
      GET  {base}/gstr2a?gstin=&period=
      GET  {base}/gstr2b?gstin=&period=
    """

    def __init__(self) -> None:
        self.base_url = settings.gsp_base_url.rstrip("/")
        self.client_id = settings.gsp_client_id
        self.client_secret = settings.gsp_client_secret

    @property
    def configured(self) -> bool:
        return bool(self.base_url and self.client_id and self.client_secret)

    async def _token(self, client: httpx.AsyncClient) -> str:
        response = await client.post(
            f"{self.base_url}/oauth/token",
            data={
                "grant_type": "client_credentials",
                "client_id": self.client_id,
                "client_secret": self.client_secret,
            },
            timeout=30.0,
        )
        response.raise_for_status()
        return response.json()["access_token"]

    async def _fetch(self, path: str, gstin: str, period: str) -> list[dict[str, Any]]:
        if not self.configured:
            raise RuntimeError("GSP credentials are not configured")
        async with httpx.AsyncClient() as client:
            token = await self._token(client)
            response = await client.get(
                f"{self.base_url}{path}",
                params={"gstin": gstin, "period": period},
                headers={"Authorization": f"Bearer {token}"},
                timeout=60.0,
            )
            response.raise_for_status()
            data = response.json()
            if isinstance(data, list):
                return data
            return data.get("items") or data.get("invoices") or []

    async def fetch_2a(self, gstin: str, period: str) -> list[dict[str, Any]]:
        return await self._fetch("/gstr2a", gstin, period)

    async def fetch_2b(self, gstin: str, period: str) -> list[dict[str, Any]]:
        return await self._fetch("/gstr2b", gstin, period)


def get_portal_client() -> GstrPortalClient:
    http_client = HttpGspClient()
    if http_client.configured:
        return http_client
    return ExcelGstrClient()


def portal_api_configured() -> bool:
    return HttpGspClient().configured
