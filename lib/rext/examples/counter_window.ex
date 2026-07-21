defmodule Rext.Examples.CounterWindow do
  @moduledoc """
  The canonical hello-world: a counter in a real desktop window, driven by
  Elixir. Proves the full loop — mount → render → native draw → click event →
  handle_event → re-render — plus the agent harness (`Rext.Test.click/2`).
  """
  use Rext.Window

  @impl true
  def mount(_params, socket) do
    {:ok, Rext.Socket.assign(socket, :count, 0)}
  end

  @impl true
  def render(assigns) do
    %{
      type: :column,
      props: %{gap: :space_lg, padding: :space_xl, background: :background},
      children: [
        %{
          type: :text,
          props: %{text: "Count: #{assigns.count}", size: 34, color: :on_background},
          children: []
        },
        %{
          type: :row,
          props: %{gap: :space_md},
          children: [
            %{
              type: :button,
              props: %{label: "− Decrement", on_click: :dec, color: :surface},
              children: []
            },
            %{
              type: :button,
              props: %{label: "Increment +", on_click: :inc, color: :primary},
              children: []
            }
          ]
        }
      ]
    }
  end

  @impl true
  def handle_event("click", %{"tag" => "inc"}, socket) do
    {:noreply, Rext.Socket.update(socket, :count, &(&1 + 1))}
  end

  def handle_event("click", %{"tag" => "dec"}, socket) do
    {:noreply, Rext.Socket.update(socket, :count, &(&1 - 1))}
  end
end
