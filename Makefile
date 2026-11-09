.PHONY: up down reset logs test

up:
	docker compose up -d --build

down:
	docker compose down

reset:
	docker compose down -v

logs:
	docker compose logs -f

test:
	./tests/smoke-test.sh
