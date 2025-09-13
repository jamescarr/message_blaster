# Message Blaster

Message Blaster generates realistic JSON events and publishes them to SQS (LocalStack) at a configurable rate. It is the direct SQS mode described in `message-blaster/agent.md`.

## Prerequisites
- Elixir 1.18+
- direnv (optional) or export env vars manually
- LocalStack running (SQS): `docker run -p 4566:4566 -p 4571:4571 localstack/localstack`

## Environment
You can load the repo-level `.envrc` (recommended):
```bash
# from repo root
brew install direnv   # if needed
echo 'use dotenv' >> .envrc  # if you want
# or just allow the existing .envrc
direnv allow
```
Key variables (defaults are set in `.envrc`):
- `AWS_REGION=us-east-1`
- `AWS_ACCESS_KEY_ID=fake`
- `AWS_SECRET_ACCESS_KEY=fake`
- `SQS_ENDPOINT=http://localhost:4566`
- `SQS_QUEUE_URL=http://localhost:4566/000000000000/message-blaster-events`

## Install deps
```bash
mix deps.get
```

## Create queue
```bash
mix mb.sqs.create
```

## Start producer
```bash
# default rate from config (e.g., 50 msg/s)
mix mb.start

# or explicit rate
mix mb.start --rate 10
```

## Adjust rate at runtime
```bash
mix mb.rate --set 100
```

## Stop producer
```bash
mix mb.stop
```

## Consume messages (Python example)
See `message-blaster/agent.md` for a complete Python consumer. Quickstart:
```bash
python scripts/sqs_consumer.py
```

## Makefile
A Makefile with common commands is provided. Use these targets:
```make
# message_blaster/Makefile
# Usage: make <target>

.PHONY: help deps queue start start10 rate100 stop consumer

help:
	@echo "make deps        - mix deps.get"
	@echo "make queue       - create SQS queue"
	@echo "make start       - start producer (default rate)"
	@echo "make start10     - start producer at 10 msg/s"
	@echo "make rate100     - set rate to 100 msg/s"
	@echo "make stop        - stop producer"
	@echo "make consumer    - run python consumer"

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
	python scripts/sqs_consumer.py
```

Create the Makefile:
```bash
cat > Makefile <<'EOF'
.PHONY: help deps queue start start10 rate100 stop consumer

help:
	@echo "make deps        - mix deps.get"
	@echo "make queue       - create SQS queue"
	@echo "make start       - start producer (default rate)"
	@echo "make start10     - start producer at 10 msg/s"
	@echo "make rate100     - set rate to 100 msg/s"
	@echo "make stop        - stop producer"
	@echo "make consumer    - run python consumer"

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
	python scripts/sqs_consumer.py
EOF
```

## Notes
- This is the minimal direct SQS path. Kafka/Connect mode can be added next.
- Logging level can be adjusted in `config/config.exs`.


### Python Consumer via Poetry
```bash
# from message_blaster/
brew install poetry # if not installed
make py-setup       # installs boto3 in a poetry venv
make py-run         # runs the consumer via poetry
```
