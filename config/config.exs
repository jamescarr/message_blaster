import Config

# Message Blaster app configuration
config :message_blaster,
  mode: :direct_sqs, # or :kafka_via_connect (future)
  schemas: [
    path: System.get_env("MB_SCHEMAS_PATH", "./schemas")
  ],
  producer: [
    default_rate: String.to_integer(System.get_env("MB_DEFAULT_RATE", "50")),
    max_concurrency: String.to_integer(System.get_env("MB_MAX_CONCURRENCY", "2")),
    batch_size: String.to_integer(System.get_env("MB_BATCH_SIZE", "1"))
  ],
  sqs: [
    endpoint: System.get_env("SQS_ENDPOINT") || System.get_env("AWS_ENDPOINT_URL") || "http://localhost:4566",
    queue_url: System.get_env("SQS_QUEUE_URL") || System.get_env("SQS_QUEUE_URL_MESSAGE_BLASTER") || "http://localhost:4566/000000000000/message-blaster-events",
    region: System.get_env("AWS_REGION", "us-east-1")
  ]

# ExAws configuration (point explicitly at LocalStack with fake creds)
localstack_endpoint = System.get_env("SQS_ENDPOINT") || System.get_env("AWS_ENDPOINT_URL") || "http://localhost:4566"
localstack_uri = URI.parse(localstack_endpoint)

config :ex_aws,
  access_key_id: System.get_env("AWS_ACCESS_KEY_ID", "fake"),
  secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY", "fake"),
  region: System.get_env("AWS_REGION", "us-east-1")

config :ex_aws, :sqs,
  scheme: (localstack_uri.scheme || "http") <> "://",
  host: localstack_uri.host || "localhost",
  port: localstack_uri.port || 4566,
  region: System.get_env("AWS_REGION", "us-east-1")

config :logger, level: :info
