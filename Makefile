.PHONY: check demo-data test lint

check: lint test
	cd backend/ts && bun audit --production

demo-data:
	python backend/scripts/create_demo_data.py

test:
	cd backend/ts && bun test
	cd backend/python && pytest tests/ -v
	cd backend-files && uv run python -m unittest discover -s tests -v

lint:
	cd backend/ts && bun run typecheck && bun run lint
	cd backend/python && ruff check .
	cd backend-files && uv run ruff check .
