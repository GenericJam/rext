defmodule Rext.Socket do
  @moduledoc """
  The socket struct threaded through every `Rext.Window` callback.

  Holds two things:

    * `assigns` — the public data map your `render/1` reads via `assigns.foo`.
    * `__rext__` — internal framework metadata (window id, window module,
      title/size, last-rendered tree). Never mutate `__rext__` directly.

  This mirrors `Mob.Socket` deliberately — the programming model is identical to
  mob's. What differs is the *paradigm*: mob threads a navigation stack through
  the socket (`push_screen`/`pop_screen`), because mobile shows one screen at a
  time. Desktop shows many windows at once, so rext's socket carries window
  identity/geometry instead, and multi-window is expressed as multiple
  supervised `Rext.Window` processes rather than a stack.
  """

  @type t :: %__MODULE__{
          assigns: map(),
          __rext__: %{
            window: module() | nil,
            id: String.t(),
            title: String.t(),
            size: {number(), number()},
            tree: map() | nil
          }
        }

  defstruct assigns: %{},
            __rext__: %{
              window: nil,
              id: "main",
              title: "Rext",
              size: {480, 360},
              tree: nil
            }

  @doc """
  Create a new socket for a window module.

  Options: `:id`, `:title`, `:size` (a `{width, height}` tuple).
  """
  @spec new(module(), keyword()) :: t()
  def new(window_module, opts \\ []) do
    %__MODULE__{
      assigns: %{},
      __rext__: %{
        window: window_module,
        id: Keyword.get(opts, :id, "main"),
        title: Keyword.get(opts, :title, "Rext"),
        size: Keyword.get(opts, :size, {480, 360}),
        tree: nil
      }
    }
  end

  @doc "Assign a single key/value into the socket's assigns."
  @spec assign(t(), atom(), term()) :: t()
  def assign(%__MODULE__{assigns: assigns} = socket, key, value) when is_atom(key) do
    %{socket | assigns: Map.put(assigns, key, value)}
  end

  @doc "Assign multiple key/value pairs from a keyword list or map."
  @spec assign(t(), keyword() | map()) :: t()
  def assign(%__MODULE__{assigns: assigns} = socket, kw) when is_list(kw) or is_map(kw) do
    %{socket | assigns: Map.merge(assigns, Map.new(kw))}
  end

  @doc """
  Update an existing assign by applying `fun` to its current value.
  Raises `KeyError` if the key is not already assigned (mirrors LiveView).
  """
  @spec update(t(), atom(), (term() -> term())) :: t()
  def update(%__MODULE__{assigns: assigns} = socket, key, fun)
      when is_atom(key) and is_function(fun, 1) do
    %{socket | assigns: Map.put(assigns, key, fun.(Map.fetch!(assigns, key)))}
  end

  @doc "Assign `key` only if absent, computing the value lazily."
  @spec assign_new(t(), atom(), (-> term())) :: t()
  def assign_new(%__MODULE__{assigns: assigns} = socket, key, fun)
      when is_atom(key) and is_function(fun, 0) do
    case assigns do
      %{^key => _} -> socket
      _ -> %{socket | assigns: Map.put(assigns, key, fun.())}
    end
  end

  @doc false
  @spec put_rext(t(), atom(), term()) :: t()
  def put_rext(%__MODULE__{__rext__: rext} = socket, key, value) do
    %{socket | __rext__: Map.put(rext, key, value)}
  end

  @doc "The window's stable id string."
  @spec id(t()) :: String.t()
  def id(%__MODULE__{__rext__: %{id: id}}), do: id
end
