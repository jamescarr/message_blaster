# Message Blaster — Architecture and Operational Spec

Message Blaster is an Elixir application that generates synthetic Avro messages from local schemas and delivers them to a target queue through a realistic streaming pipeline. It is designed to be observable, configurable at runtime, and resilient under load for local experimentation and demos.

This document specifies the architecture, components, runtime controls, tooling, and operational flows. It does not implement the system.

## Goals
- Provide a local, production-like data path for events:
  Elixir generators → Kafka (per-topic) → Kafka Connect SQS Sink → LocalStack SQS.
- Register Avro schemas from a local directory with Schema Registry.
- Generate realistic random data conforming to schemas at configurable rates.
- Support runtime control of send rate, concurrency, active schemas, and pause/resume.
- Offer clear observability: logs, metrics, and live stats.

## Non-Goals
- No cloud dependencies (everything local via Docker Compose).
- No long-term persistence or exactly-once delivery guarantees (demo-grade).
- No complex orchestration beyond a single-node environment.

---

## High-Level Architecture

```mermaid
flowchart LR
  subgraph App[Message Blaster (Elixir)]
    SL[Schema Loader] -->|avsc| SRC[Schema Registry Client]
    DG[Data Generator] --> PUB[Kafka Publisher]
    RL[Rate Limiter]
    CTRL[Control Plane (Mix/RPC)] --> RL
    CTRL --> PUB
    TM[Topic Manager] --> PUB
  end

  SRC <---> SR[(Schema Registry)]
  PUB --> K[(Kafka)]
  K --> KC[Kafka Connect SQS Sink]
  KC --> SQS[(LocalStack SQS)]

  subgraph Observability
    M[Telemetry/Metrics]
    L[Structured Logs]
  end

  DG --> M
  PUB --> M
  KC --> M
  App --> L
```

### Primary Data Path
1. Avro schemas are discovered locally and registered in Schema Registry.
2. For each active schema, a generator produces valid Avro records.
3. Records are serialized and published to a Kafka topic derived from the schema name.
4. Kafka Connect SQS Sink pushes the records to a configured SQS queue in LocalStack.

### Alternative (direct) Path (optional mode)
- Elixir can publish directly to SQS (bypassing Kafka/Connect) for fast-path demos. This is a runtime mode switch to validate both approaches.

---

## Components (Elixir)

- Application/Supervision Tree
  - `MessageBlaster.Application` — Supervises all components.
  - `MessageBlaster.SchemaLoader` — Watches `schemas/` for `.avsc`, validates, emits events.
  - `MessageBlaster.SchemaRegistryClient` — Registers subjects/versions, caches IDs.
  - `MessageBlaster.TopicManager` — Ensures Kafka topics exist per schema (via REST Proxy or shell).
  - `MessageBlaster.GeneratorSupervisor` — Dynamic supervisors for per-schema producers.
  - `MessageBlaster.Producer` — GenServer per schema controlling workers, rate, and batching.
  - `MessageBlaster.ProducerWorker` — Sends messages; cooperates with `RateLimiter`.
  - `MessageBlaster.RateLimiter` — Token-bucket or leaky-bucket enforcing messages/sec per schema.
  - `MessageBlaster.Publisher` — Kafka publisher; alternative SQS publisher for direct mode.
  - `MessageBlaster.Control` — Runtime control module (called by Mix tasks or RPC).
  - Telemetry — Emits metrics: rates, lag, errors, queue sizes, backoff status.

### Key Design Choices
- Isolation per schema: each schema has an independent producer and limiter.
- Backpressure: workers request tokens from limiter; if unavailable, they sleep with jitter.
- Resilience: exponential backoff on publish errors; circuit-breaker state per destination.
- Idempotence: messages include deterministic keys (if provided by schema) to support partitioning.
- Observability: consistent event names for Telemetry; logs are structured (JSON) when `LOG_JSON=true`.

---

## External Services (via Docker Compose)

- Zookeeper (if required by Kafka image)
- Kafka broker
- Schema Registry (Confluent-compatible)
- Kafka Connect with SQS Sink Connector
- LocalStack (SQS)

> The Compose file wires networking, health checks, and exposes ports for local development.

---

## Configuration

All configuration may be set via `config/*.exs` and overridden by environment variables.

- Schema
  - `schemas.path` — default `./schemas` (directory containing `.avsc` files)
  - `schemas.subject_strategy` — e.g., `topic_record` or `record`
- Registry
  - `registry.url` — e.g., `http://localhost:8081`
- Kafka
  - `kafka.bootstrap` — e.g., `localhost:9092`
  - `kafka.rest_proxy` — optional, for topic creation
  - `kafka.acks` — default `all`
  - `kafka.compression` — e.g., `gzip`
- Connect (SQS Sink)
  - `connect.url` — e.g., `http://localhost:8083`
  - `connect.sink.class` — SQS sink class name
  - `connect.sink.config` — map of connector properties
- SQS (LocalStack)
  - `sqs.endpoint` — `http://localhost:4566`
  - `sqs.queue_name` — default demo queue name
  - `aws.access_key_id`/`aws.secret_access_key` — dummy values
- Producer defaults
  - `producer.default_rate` — msgs/sec per schema (e.g., 50)
  - `producer.max_concurrency` — workers per schema (e.g., 4)
  - `producer.batch_size` — for Kafka produce (e.g., 1–100)
  - `producer.mode` — `:kafka_via_connect` (default) or `:direct_sqs`

---

## Runtime Control Plane

Support two control surfaces:

1. Mix Tasks (CLI)
   - `mix mb.init` — Validate environment; check dependencies.
   - `mix mb.register_schemas [--path ./schemas]` — Register all schemas; print subjects/IDs.
   - `mix mb.topics.ensure` — Ensure topics exist for registered schemas.
   - `mix mb.start [--schema my_event --rate 100 --workers 4]` — Start producers.
   - `mix mb.stop [--schema my_event]` — Stop producers.
   - `mix mb.rate --schema my_event --set 500` — Adjust messages/sec at runtime.
   - `mix mb.stats [--schema my_event]` — Print live stats.
   - `mix mb.mode --set direct_sqs|kafka_via_connect` — Switch publish mode.
   - `mix mb.connector.apply` — Apply/Update Kafka Connect SQS Sink config.
   - `mix mb.sqs.create [--queue name]` — Create SQS queue in LocalStack.
   - `mix mb.sqs.stats` — Approximate message counts via SQS attributes.

2. Erlang Distribution (Remote RPC)
   - Start VM as a named node with a cookie (e.g., via `rel` or `iex --sname blaster --cookie secret`).
   - Invoke at runtime:
     - `:rpc.call(:blaster@host, MessageBlaster.Control, :set_rate, ["my_event", 200])`
     - `:rpc.call(:blaster@host, MessageBlaster.Control, :pause, ["my_event"])`
     - `:rpc.call(:blaster@host, MessageBlaster.Control, :resume, ["my_event"])`
     - `:rpc.call(:blaster@host, MessageBlaster.Control, :set_workers, ["my_event", 8])`

> Optional: lightweight HTTP admin endpoint for non-Erlang users (not required initially).

---

## Data Generation

- Read `.avsc` → build value generators:
  - Primitive types: string, int, long, float, double, boolean, bytes.
  - Complex types: record, array, map, enum, union (prefer first non-null unless configured).
  - Logical types: timestamp-millis, decimal (configurable ranges), uuid.
- Deterministic mode: seed RNG for reproducible runs.
- Field overrides: per-field generators via config (e.g., faker categories).
- Envelope: include metadata (e.g., `event_id`, `sent_at`, `schema_subject`, `schema_id`).

---

## Kafka Topics and Keys

- Topic naming: `events.<record_name>` by default; configurable.
- Partitioning key: choose from field (e.g., `user_id`) or random when absent.
- Headers: include schema id and content-type (`application/avro-binary`).

---

## Kafka Connect SQS Sink

- Connector configuration template (example):
  - `name`: `sqs-sink`
  - `connector.class`: `io.lenses.streamreactor.connect.aws.sqs.sink.SqsSinkConnector` (or alternative)
  - `tasks.max`: `2`
  - `topics`: comma-separated list of event topics
  - `aws.endpoint`: `http://localstack:4566`
  - `aws.region`: `us-east-1`
  - `aws.access.key`: `fake`
  - `aws.secret.key`: `fake`
  - `sqs.queue.url`: `http://localstack:4566/000000000000/<queue>`
  - `value.converter`: `io.confluent.connect.avro.AvroConverter`
  - `value.converter.schema.registry.url`: `http://schema-registry:8081`

> The exact connector may vary; the Compose image should bundle the chosen connector or auto-install it.

---

## Observability

- Telemetry events:
  - `message_blaster.producer.started|stopped`
  - `message_blaster.producer.sent|failed`
  - `message_blaster.publisher.backoff`
  - `message_blaster.rate_limiter.tokens`
- Metrics (exporters):
  - stdout logger, Prometheus (optional via `telemetry_metrics_prometheus`), statsd (optional)
- Logs:
  - JSON logs when `LOG_JSON=true`; otherwise human-readable.
  - Correlate with `schema`, `topic`, `worker_id`, `batch_id`.

---

## Dev Tooling & Project Layout

- `.tool-versions` for Erlang/Elixir pins (latest stable).
- `docker-compose.yaml` for: Kafka, Schema Registry, Kafka Connect, LocalStack.
- `Makefile` convenience commands wrapping Docker and Mix tasks.
- `schemas/` directory with sample Avro (e.g., pokemon card events).
- `scripts/` with sample consumers (e.g., Python SQS poller using boto3).

```
message-blaster/
├─ schemas/
│  └─ pokemon_card.avsc
├─ config/
│  ├─ config.exs
│  ├─ dev.exs
│  └─ prod.exs
├─ lib/message_blaster/
│  ├─ application.ex
│  ├─ schema_loader.ex
│  ├─ schema_registry_client.ex
│  ├─ topic_manager.ex
│  ├─ generator_supervisor.ex
│  ├─ producer.ex
│  ├─ producer_worker.ex
│  ├─ rate_limiter.ex
│  ├─ publisher/
│  │  ├─ kafka_publisher.ex
│  │  └─ sqs_publisher.ex
│  └─ control.ex
├─ mix.exs
├─ docker-compose.yaml
├─ Makefile
└─ scripts/
   └─ sqs_consumer.py
```

### Makefile Targets (examples)
- `make up` — start docker-compose stack
- `make down` — stop stack
- `make logs` — follow container logs
- `make schemas` — `mix mb.register_schemas`
- `make topics` — `mix mb.topics.ensure`
- `make connector` — `mix mb.connector.apply`
- `make start` — start producers with defaults
- `make stop` — stop producers
- `make rate schema=<name> value=<n>` — adjust rate at runtime

---

## Operational Flows

### Happy Path (Kafka via Connect → SQS)
1. `make up`
2. `make schemas` (register `.avsc`)
3. `make topics`
4. `make connector` (SQS sink)
5. `make start` (begin generating)
6. `scripts/sqs_consumer.py` (observe messages)

### Direct SQS Mode
1. `make up`
2. `make schemas`
3. `mix mb.mode --set direct_sqs`
4. `mix mb.start --schema pokemon_card --rate 200`

---

## Risks & Mitigations
- Connector compatibility: pin an image version with SQS sink preinstalled.
- Schema evolution: start with backward-compatible changes; include `null` in unions.
- Local resource limits: expose rate limiters and worker counts; document safe defaults.
- Clock skew: include `sent_at` timestamps from a single source (`System.monotonic_time` for durations, UTC for wall-clock).

---

## Deliverables (when implemented)
- Running Compose stack
- Mix tasks for all control-plane commands
- Sample schemas, producers, and SQS consumer script
- README with quickstart, troubleshooting, and diagrams

---

## Appendix

### Sample Python SQS Consumer (complete)
```python
#!/usr/bin/env python3
"""
Simple SQS consumer for LocalStack.
- Long polls the configured queue
- Prints JSON messages with basic formatting
- Deletes messages after successful processing

Requirements:
  pip install boto3

Environment (defaults shown):
  AWS_REGION=us-east-1
  AWS_ACCESS_KEY_ID=fake
  AWS_SECRET_ACCESS_KEY=fake
  SQS_ENDPOINT=http://localhost:4566
  SQS_QUEUE_URL=http://localhost:4566/000000000000/message-blaster-events
"""
import json
import os
import sys
import time
from typing import Any, Dict

import boto3
from botocore.config import Config

REGION = os.getenv("AWS_REGION", "us-east-1")
ACCESS_KEY = os.getenv("AWS_ACCESS_KEY_ID", "fake")
SECRET_KEY = os.getenv("AWS_SECRET_ACCESS_KEY", "fake")
SQS_ENDPOINT = os.getenv("SQS_ENDPOINT", "http://localhost:4566")
QUEUE_URL = os.getenv("SQS_QUEUE_URL", "http://localhost:4566/000000000000/message-blaster-events")

session = boto3.session.Session()
config = Config(retries={"max_attempts": 5, "mode": "standard"})
sqs = session.client(
    "sqs",
    region_name=REGION,
    aws_access_key_id=ACCESS_KEY,
    aws_secret_access_key=SECRET_KEY,
    endpoint_url=SQS_ENDPOINT,
    config=config,
)

def pretty_print(message_body: str) -> None:
    try:
        data = json.loads(message_body)
        print(json.dumps(data, indent=2, sort_keys=True))
    except json.JSONDecodeError:
        print(message_body)

def process_message(msg: Dict[str, Any]) -> bool:
    body = msg.get("Body", "")
    receipt = msg.get("ReceiptHandle")

    print("\n=== Received Message ===")
    pretty_print(body)

    # TODO: add custom processing here

    # Delete the message when processed
    if receipt:
        sqs.delete_message(QueueUrl=QUEUE_URL, ReceiptHandle=receipt)
        print("Deleted message.")
        return True
    return False

def main() -> int:
    print("Polling SQS:", QUEUE_URL)
    while True:
        try:
            resp = sqs.receive_message(
                QueueUrl=QUEUE_URL,
                MaxNumberOfMessages=10,
                WaitTimeSeconds=10,  # long polling
                VisibilityTimeout=30,
                MessageAttributeNames=["All"],
                AttributeNames=["All"],
            )
            messages = resp.get("Messages", [])
            if not messages:
                # idle tick
                continue

            for msg in messages:
                ok = process_message(msg)
                if not ok:
                    print("Failed to process message:", msg.get("MessageId"))

        except KeyboardInterrupt:
            print("Exiting...")
            break
        except Exception as e:
            print("Error while polling:", repr(e))
            time.sleep(2)
    return 0

if __name__ == "__main__":
    sys.exit(main())
```

#### Quickstart
```bash
# 1) Ensure LocalStack SQS queue exists (example URL used above)
aws --endpoint-url http://localhost:4566 \
  sqs create-queue --queue-name message-blaster-events \
  --region us-east-1

# 2) Install dependencies
python3 -m venv .venv && source .venv/bin/activate
pip install boto3

# 3) Run consumer
export SQS_QUEUE_URL=http://localhost:4566/000000000000/message-blaster-events
python scripts/sqs_consumer.py
```

