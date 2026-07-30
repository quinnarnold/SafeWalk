# SafeWalk contributor guidance

SafeWalk is an iOS application with a Bun/Fastify API, Python/FastAPI compute
service, public-data generation scripts, and optional deployment examples.

Keep secrets, raw incident data, generated city artifacts, caches, and local
tool state out of version control. Only add data sources that are public and
documented. Do not distribute inputs or derived artifacts unless their
redistribution rights and required notices have been established.

Run the narrowest relevant checks:

```bash
cd backend/ts && bun run typecheck && bun run lint && bun test
cd backend/python && ruff check . && pytest tests/ -v
cd backend-files && uv run ruff check .
```

Treat authentication, live-location sharing, route correctness, privacy, and
safety claims as sensitive. Update `DATA_SOURCES.md` for source changes and
`SAFETY_AND_LIMITATIONS.md` for methodological changes.
