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

## Schema-based Generation
Message Blaster can read all Avro schemas in a directory and generate random JSON that conforms to each schema.

- Schema directory (default): `schemas/`
- Configure dir env var: `SCHEMA_DIR=...`
- Select which schemas to publish with `SCHEMAS` (comma-separated, supports `*` wildcards). If unset, all schemas are used.
- Optional registration: set `SCHEMA_REGISTRY_URL` to register each loaded schema; if unset, registration is skipped.

Examples:
```bash
# Use all schemas found in ./schemas at 5 msg/s per schema
RATE=5 make start

# Explicit schema directory
RATE=2 SCHEMA_DIR=schemas make start

# Select specific fully-qualified schema names
RATE=10 SCHEMAS=com.example.cards.PokemonCard,com.example.events.CardSale make start

# Use wildcards to select a namespace
RATE=3 SCHEMAS='com.example.*' make start

# Skip schema registration (default behavior): do not set SCHEMA_REGISTRY_URL
# Register with a running Schema Registry (optional)
export SCHEMA_REGISTRY_URL=http://localhost:8081
RATE=5 SCHEMAS='com.example.*' make start
```

Sample schemas included in `schemas/`:
- `com.example.cards.PokemonCard`
- `com.example.events.CardSale`
- `com.example.events.CardListing`
- `com.example.events.CardOffer`

End-to-end quickstart:
```bash
# 1) Start LocalStack
make stack-up

# 2) Create SQS queue
make queue

# 3) Start producer with all schemas at 2 msg/s
RATE=2 SCHEMA_DIR=schemas make start

# 4) In another terminal, run the consumer
# Preferred: Poetry
make py-setup
make py-run
# Or fallback
make consumer
```

## How it works

```mermaid
graph TD
  subgraph App
    SL[Schema Loader<br/>reads *.avsc] --> SRG[(Optional<br/>Schema Registry)]
    GEN[Avro Generator<br/>(random data)] --> PUB[Publisher]
    SET[Config<br/>(RATE, SCHEMA_DIR, SCHEMAS)] --> GEN
  end

  PUB -- direct mode --> SQS[(LocalStack SQS)]

  PUB -- kafka mode --> K[(Kafka)]
  K --> KC[Kafka Connect<br/>SQS Sink]
  KC --> SQS
```

- Direct SQS mode (default): Producer publishes JSON directly to LocalStack SQS.
- Kafka mode (optional): Publish to Kafka topics, then Kafka Connect SQS Sink delivers to SQS.
- Schemas: All `*.avsc` in `SCHEMA_DIR` are loaded; `SCHEMAS` filters by comma-separated list with `*` wildcards.

## Connector configuration (Kafka mode)
- Connector config lives at `connectors/sqs-sink.json` and is posted on startup by `connect-init`.
- Edit that file to change topic selection, queue URL, region, etc.
- Manual management (optional):
```bash
make connector-apply
make connector-status
make connector-delete
```

## Run modes at a glance
- Direct to SQS (no Kafka):
```bash
make stack-up     # starts LocalStack only (plus Kafka stack; OK to ignore if unused)
make queue        # create the SQS queue
RATE=5 SCHEMAS='com.example.*' make start
make consumer     # or poetry targets
```

- Kafka → Connect → SQS:
```bash
make stack-up
make queue
export SCHEMA_REGISTRY_URL=http://localhost:8081
make connector-apply
RATE=5 SCHEMAS='com.example.*' make start
```

### Notes
- If you don't need Kafka/Connect, you can still run `make stack-up` (Kafka stack also starts) and just use direct SQS.
- If Kafka Connect reports plugin errors, ensure the SQS sink connector jar(s) are under `connect-plugins/` or use an image that includes it.
- Schema registration is optional: if `SCHEMA_REGISTRY_URL` is unset, schemas are not registered.

## Live tuning via Erlang distribution
You can connect to the running node and adjust the producer at runtime.

### Option 1: Start the app as a named node
```bash
# in message_blaster/
COOKIE=secret
iex --name blaster@127.0.0.1 --cookie $COOKIE -S mix
# then start the producer as usual (or via mix mb.start)
```

From another terminal, connect as a control node and tune the rate:
```bash
COOKIE=secret
iex --name ctl@127.0.0.1 --cookie $COOKIE

# Increase rate to 50 msg/s per schema
:rpc.call(:'blaster@127.0.0.1', MessageBlaster.Producer, :set_rate, [50])

# Inspect current state (rate, schemas, etc.)
:rpc.call(:'blaster@127.0.0.1', :sys, :get_state, [MessageBlaster.Producer])

# Stop producing
:rpc.call(:'blaster@127.0.0.1', MessageBlaster.Producer, :stop_producing, [])
```

### Option 2: Remote shell into the running node
```bash
COOKIE=secret
# Attach directly to the running node's shell
iex --remsh blaster@127.0.0.1 --name ctl@127.0.0.1 --cookie $COOKIE

# Now you’re on the blaster node; call directly:
MessageBlaster.Producer.set_rate(25)
:sys.get_state(MessageBlaster.Producer)
```

Tips:
- Ensure the cookie and host (127.0.0.1) match between nodes.
- If you started the producer via `make start`, you can still open a named `iex` on the same machine and use `--remsh` to attach as above (start the app with a name for discovery).
