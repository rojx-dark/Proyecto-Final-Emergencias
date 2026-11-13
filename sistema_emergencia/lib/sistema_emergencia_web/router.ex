defmodule SistemaEmergenciaWeb.Router do
  @moduledoc """
  Enrutador principal de Phoenix que dirige las peticiones HTTP y WebSocket
  hacia el panel interactivo en tiempo real (`EmergenciaLive`).
  """
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :put_root_layout, html: {SistemaEmergenciaWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", SistemaEmergenciaWeb do
    pipe_through :browser

    live "/", EmergenciaLive, :index
  end
end
