"""Load profile mirroring real traffic from the console and the mobile apps.

    locust -f loadtest/locustfile.py --host https://staging-api.example.com

Environment:
    LOADTEST_ADMIN_EMAIL / LOADTEST_ADMIN_PASSWORD   company admin on staging
    LOADTEST_EMPLOYEE_TOKEN                          optional employee access token
"""
import os
import random
import threading

from locust import HttpUser, between, events, task

ADMIN_EMAIL = os.getenv("LOADTEST_ADMIN_EMAIL", "acme@demo.com")
ADMIN_PASSWORD = os.getenv("LOADTEST_ADMIN_PASSWORD", "DemoAdmin!123")
EMPLOYEE_TOKEN = os.getenv("LOADTEST_EMPLOYEE_TOKEN")
STATUSES = [None, "pending", "approved", "rejected", "returned"]
SEARCH_TERMS = ["a", "inv", "ltd", "traders", "2026"]


class SharedAdminSession:
    """One sign-in per worker process: login is deliberately throttled per email."""

    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.access: str | None = None
        self.refresh: str | None = None

    def headers(self, client) -> dict[str, str]:
        with self.lock:
            if not self.access:
                self._login(client)
        return {"Authorization": f"Bearer {self.access}"}

    def renew(self, client, stale: str | None) -> None:
        with self.lock:
            if self.access != stale:
                return
            if self.refresh:
                response = client.post(
                    "/v1/auth/token/refresh",
                    json={"refreshToken": self.refresh},
                    name="/v1/auth/token/refresh",
                )
                if response.ok:
                    self._store(response.json())
                    return
            self._login(client)

    def _login(self, client) -> None:
        response = client.post(
            "/v1/admin/auth/login",
            json={"email": ADMIN_EMAIL, "password": ADMIN_PASSWORD},
            name="/v1/admin/auth/login",
        )
        response.raise_for_status()
        self._store(response.json())

    def _store(self, body: dict) -> None:
        self.access = body["accessToken"]
        self.refresh = body.get("refreshToken")


admin_session = SharedAdminSession()


@events.test_start.add_listener
def _announce(environment, **_kwargs):
    print(f"Admin load as {ADMIN_EMAIL}; employee load {'on' if EMPLOYEE_TOKEN else 'off'}")


class CompanyAdmin(HttpUser):
    """Console / admin-app usage: dashboards, invoice review, team lookups."""

    weight = 3
    wait_time = between(1, 4)

    def _get(self, path: str, name: str | None = None, **params):
        headers = admin_session.headers(self.client)
        with self.client.get(path, params=params or None, headers=headers, name=name or path, catch_response=True) as response:
            if response.status_code == 401:
                admin_session.renew(self.client, headers["Authorization"].removeprefix("Bearer "))
                response.success()
            elif response.status_code == 429:
                response.failure("rate limited")
            elif not response.ok:
                response.failure(f"HTTP {response.status_code}")
        return response

    @task(5)
    def dashboard(self):
        self._get("/v1/admin/dashboard")

    @task(6)
    def invoices(self):
        status = random.choice(STATUSES)
        params = {"page": random.randint(1, 3), "pageSize": 25}
        if status:
            params["status"] = status
        response = self._get("/v1/admin/invoices", **params)
        if response.ok:
            items = response.json().get("items") or []
            if items:
                self._get(f"/v1/admin/invoices/{random.choice(items)['id']}", name="/v1/admin/invoices/[id]")

    @task(2)
    def search_invoices(self):
        self._get("/v1/admin/invoices", name="/v1/admin/invoices?q", q=random.choice(SEARCH_TERMS), pageSize=25)

    @task(2)
    def employees(self):
        self._get("/v1/admin/employees", page=1, pageSize=50)

    @task(1)
    def notifications(self):
        self._get("/v1/admin/notifications", page=1, pageSize=50)

    @task(1)
    def announcements(self):
        self._get("/v1/admin/notifications/announcements")

    @task(1)
    def itc_status(self):
        self._get("/v1/admin/itc/status")


class Employee(HttpUser):
    """Mobile-app polling: own invoices, notifications and company config."""

    weight = 5
    wait_time = between(2, 8)

    def on_start(self):
        if not EMPLOYEE_TOKEN:
            self.stop()
        self.headers = {"Authorization": f"Bearer {EMPLOYEE_TOKEN}"}

    @task(4)
    def my_invoices(self):
        self.client.get("/v1/invoices/mine", params={"page": 1, "pageSize": 50}, headers=self.headers, name="/v1/invoices/mine")

    @task(3)
    def notifications(self):
        self.client.get("/v1/notifications", params={"page": 1, "pageSize": 50}, headers=self.headers, name="/v1/notifications")

    @task(1)
    def company_config(self):
        self.client.get("/v1/company/config", headers=self.headers, name="/v1/company/config")


class Probe(HttpUser):
    """Load balancer health checks."""

    weight = 1
    wait_time = between(5, 10)

    @task
    def ready(self):
        self.client.get("/ready")
