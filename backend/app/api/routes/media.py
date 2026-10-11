"""Serves locally stored images behind short-lived signed links (dev / single box).
With STORAGE_BACKEND=r2 clients get presigned R2 URLs instead and this route 404s."""
import mimetypes

from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import FileResponse

from app.services.storage import LocalStorage, get_storage, verify_media

router = APIRouter()


@router.get("/{key:path}")
async def media(key: str, exp: int = Query(...), sig: str = Query(..., max_length=128)):
    storage = get_storage()
    if not isinstance(storage, LocalStorage):
        raise HTTPException(404, "Not found")
    if not verify_media(key, exp, sig):
        raise HTTPException(403, "Link expired")
    try:
        path = storage.path_for(key)
    except ValueError:
        raise HTTPException(404, "Not found")
    if not path.is_file():
        raise HTTPException(404, "Not found")
    return FileResponse(
        path,
        media_type=mimetypes.guess_type(path.name)[0] or "application/octet-stream",
        headers={"Cache-Control": "private, max-age=600"},
    )
