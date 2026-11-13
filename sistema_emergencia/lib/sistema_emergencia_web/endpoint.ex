defmodule SistemaEmergenciaWeb.Endpoint do
  @moduledoc """
  Endpoint HTTP y WebSocket de Phoenix para el Sistema Distribuido de Gestión de Emergencias.
  Expone la interfaz web interactiva en http://localhost:4000
  """
  use Phoenix.Endpoint, otp_app: :sistema_emergencia

  @session_options [
    store: :cookie,
    key: "_sistema_emergencia_key",
    signing_salt: "emergencia_sign_salt",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]]

  plug Plug.Static,
    at: "/assets/phoenix",
    from: :phoenix,
    only: ~w(phoenix.min.js phoenix.js)

  plug Plug.Static,
    at: "/assets/phoenix_live_view",
    from: :phoenix_live_view,
    only: ~w(phoenix_live_view.min.js phoenix_live_view.js)

  plug Plug.RequestId
  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug SistemaEmergenciaWeb.Router
end
