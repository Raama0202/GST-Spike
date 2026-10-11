# Load testing

Run against **staging**, never production; the script reads real company data.

```bash
pip install -r requirements-dev.txt
export LOADTEST_ADMIN_EMAIL=admin@yourstagingco.com
export LOADTEST_ADMIN_PASSWORD='...'
export LOADTEST_EMPLOYEE_TOKEN='eyJ...'   # optional: accessToken from an employee OTP sign-in
locust -f loadtest/locustfile.py --host https://your-staging-api.onrender.com
```

Open http://localhost:8089, then ramp up, for example 500 users with a spawn rate of 25 per second.

## Things to know

- All simulated admins share one account, because sign-in is limited to 5 attempts per minute per email.
  - The per-user API limit (`API_RATE_PER_MINUTE`, default 240) therefore applies to the whole admin swarm.
  - Raise it on staging, for example to 100000, to measure raw throughput. Leave it at the default to see the limiter return 429s.
- Access tokens last 60 minutes. Admin sessions refresh automatically. For longer employee runs, regenerate the employee token.
- Rate-limited responses are counted as failures named `rate limited`, so they stand out in the report.

## Targets on the default Render setup

The default setup is 2–4 Standard instances, 3 workers each, and Postgres basic-1gb.

| Metric | Target |
|---|---|
| p95 latency, list endpoints | < 300 ms |
| p99 latency | < 1 s |
| Error rate, excluding intentional 429s | < 0.1 % |
| Sustained throughput | ≥ 300 req/s before autoscaling adds instances |

## If targets are missed

- Check the slowest endpoints in Locust's "Statistics" tab.
- Look at Render metrics for CPU, memory, and Postgres connections.
- If CPU is high, raise the instance count.
- If Postgres connections are saturated, raise the database plan and `DB_POOL_SIZE` together.
  - Keep instances × `WEB_CONCURRENCY` × (pool + overflow) under the database connection limit.
