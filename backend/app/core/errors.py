from fastapi import HTTPException


class ApiError(HTTPException):
    """HTTP error with a stable machine-readable `code` for clients to branch on."""

    def __init__(self, status_code: int, message: str, code: str, headers: dict[str, str] | None = None) -> None:
        super().__init__(status_code, message, headers=headers)
        self.code = code


SUBSCRIPTION_EXPIRED = "SUBSCRIPTION_EXPIRED"
COMPANY_SUSPENDED = "COMPANY_SUSPENDED"
COMPANY_INACTIVE = "COMPANY_INACTIVE"
