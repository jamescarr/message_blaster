#.PHONY declarations
.PHONY: help deps queue start start10 rate100 stop consumer \
	stack-up stack-down stack-logs stack-ps stack-restart stack-clean stack-recreate \
	stack-logs-localstack stack-exec-localstack docker-ps docker-images docker-prune

help:
	@echo "make deps                 - mix deps.get"
	@echo "make queue                - create SQS queue"
	@echo "make start                - start producer (default rate)"
	@echo "make start10              - start producer at 10 msg/s"
	@echo "make rate100              - set rate to 100 msg/s"
	@echo "make stop                 - stop producer"
	@echo "make consumer             - run python consumer (uses poetry if available)"
	@echo "make stack-up             - docker compose up -d"
	@echo "make stack-down           - docker compose down"
	@echo "make stack-clean          - docker compose down -v (remove volumes)"
	@echo "make stack-restart        - docker compose restart"
	@echo "make stack-recreate       - down -v && up -d"
	@echo "make stack-logs           - tail compose logs"
	@echo "make stack-ps             - docker compose ps"
	@echo "make stack-logs-localstack- tail logs for localstack"
	@echo "make stack-exec-localstack- exec sh into localstack"
	@echo "make docker-ps            - docker ps"
	@echo "make docker-images        - docker images"
	@echo "make docker-prune         - docker system prune -f"

# Elixir tasks
deps:
	mix deps.get

queue:
	mix mb.sqs.create

start:
	mix mb.start

start10:
	mix mb.start --rate 10

rate100:
	mix mb.rate --set 100

stop:
	mix mb.stop

consumer:
	@if command -v poetry >/dev/null 2>&1; then \
		echo "Using poetry virtualenv..."; \
		poetry run python scripts/sqs_consumer.py; \
	else \
		echo "Poetry not found. Installing boto3 to user site-packages and running with python3..."; \
		python3 -m pip install --user --quiet boto3 && python3 scripts/sqs_consumer.py; \
	fi

# Docker Compose lifecycle
stack-up:
	docker compose up -d

stack-down:
	docker compose down

stack-clean:
	docker compose down -v

stack-restart:
	docker compose restart

stack-recreate:
	docker compose down -v && docker compose up -d

stack-logs:
	docker compose logs -f --tail=200

stack-ps:
	docker compose ps

stack-logs-localstack:
	docker compose logs -f --tail=200 localstack

stack-exec-localstack:
	docker compose exec localstack sh

# Raw Docker helpers
docker-ps:
	docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

docker-images:
	docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}' | sed 1q; docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}'

docker-prune:
	docker system prune -f

# Poetry (Python consumer)
.PHONY: py-setup py-run py-shell py-lock
py-setup:
	poetry install --no-interaction --no-ansi

py-run:
	poetry run python scripts/sqs_consumer.py

py-shell:
	poetry shell

py-lock:
	poetry lock --no-update

.PHONY: connector-apply connector-status connector-delete
connector-apply:
	curl -s -X PUT -H 'Content-Type: application/json' \
	  --data @connectors/sqs-sink.json \
	  http://localhost:8083/connectors/sqs-sink/config | jq .

connector-status:
	curl -s http://localhost:8083/connectors/sqs-sink/status | jq .

connector-delete:
	curl -s -X DELETE http://localhost:8083/connectors/sqs-sink | jq .
