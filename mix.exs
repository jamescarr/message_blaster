defmodule MessageBlaster.MixProject do
  use Mix.Project

  def project do
    [
      app: :message_blaster,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :hackney],
      mod: {MessageBlaster.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_aws, "~> 2.5"},
      {:ex_aws_sqs, "~> 3.4"},
      {:hackney, "~> 1.20"},
      {:saxy, "~> 1.1"},
      {:jason, "~> 1.4"}
    ]
  end
end
