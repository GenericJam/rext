import Config

# The bridge listens on a fixed port in dev (so the render backend knows where
# to connect) and an OS-assigned ephemeral port in test (so parallel/leftover
# nodes never collide on a fixed port). The dev launcher always reads the actual
# port back via `Rect.Bridge.port/0`, so an ephemeral port works there too.
config :rect, :port, if(config_env() == :test, do: 0, else: 8137)
