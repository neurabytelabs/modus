.PHONY: up down logs test shell llm-pull clean build

up:
	docker compose up -d --build

down:
	docker compose down

logs:
	docker compose logs -f modus-app

test:
	docker compose exec modus-app mix test

shell:
	docker compose exec modus-app bash

llm-pull:
	docker compose exec modus-llm ollama pull llama3.2:3b-instruct-q4_K_M

clean:
	docker compose down -v
	rm -rf data/

build:
	docker compose build --no-cache

status:
	@echo "=== Containers ==="
	@docker compose ps
	@echo ""
	@echo "=== LLM Models ==="
	@docker compose exec modus-llm ollama list 2>/dev/null || echo "LLM not running"
