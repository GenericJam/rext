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
      props: %{spacing: :space_lg, padding: :space_xl, background: :background},
      children: [
        %{
          type: :box,
          props: %{background: :surface, padding: :space_lg, corner_radius: 12, fill_width: true},
          children: [
            %{
              type: :text,
              props: %{
                text: "Count: #{assigns.count}",
                font_size: 34,
                text_color: :on_background
              },
              children: []
            }
          ]
        },
        %{type: :divider, props: %{color: :border}, children: []},
        %{type: :spacer, props: %{size: 8}, children: []},
        %{
          type: :row,
          props: %{spacing: :space_md},
          children: [
            %{
              type: :button,
              props: %{text: "− Decrement", on_click: :dec, background: :surface},
              children: []
            },
            %{
              type: :button,
              props: %{text: "Increment +", on_click: :inc, background: :primary},
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
