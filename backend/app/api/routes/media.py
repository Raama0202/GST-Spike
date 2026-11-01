"""Serves stored images (GridFS or local disk) behind short-lived signed links.
With STORAGE_BACKEND=r2 clients get presigned R2 URLs instead and this route 404s."""
from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import Response

from app.services.storage import R2Storage, get_storage, sniff_image_type, verify_media

router = APIRouter()


@router.get("/{key:path}")
async def media(key: str, exp: int = Query(...), sig: str = Query(..., max_length=128)):
    storage = get_storage()
    if isinstance(storage, R2Storage):
        raise HTTPException(404, "Not found")
    if not verify_media(key, exp, sig):
        raise HTTPException(403, "Link expired")
    data = await storage.get(key)
    if data is None:
        raise HTTPException(404, "Not found")
    return Response(
        content=data,
        media_type=sniff_image_type(data[:16]) or "application/octet-stream",
        headers={"Cache-Control": "private, max-age=600"},
    )
