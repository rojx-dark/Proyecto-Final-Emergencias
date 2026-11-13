defmodule SistemaEmergencia.Application do
  @moduledoc """
  Árbol de Supervisión Principal (OTP Tree - Requisito 1.8).
  Supervisa bajo estrategia `:one_for_one`:
    1. `ProcesoAuditoria` (Proceso independiente nativo con receive loop)
    2. `ServidorInventario` (GenServer de Recursos, Necesidades y Albergues)
    3. `ServidorComunidad` (GenServer de Usuarios, Zonas, Personas y Mascotas)
  """

  use Application

  @impl true
  def start(_type, _args) do
    base_children = [
      {Phoenix.PubSub, name: SistemaEmergencia.PubSub},
      SistemaEmergencia.ProcesoAuditoria,
      SistemaEmergencia.ServidorInventario,
      SistemaEmergencia.ServidorComunidad
    ]

    children =
      if iniciar_endpoint_web?() do
        base_children ++ [SistemaEmergenciaWeb.Endpoint]
      else
        IO.puts("[*] Phoenix ya está activo en http://localhost:4000 en otra terminal. Iniciando consola...")
        base_children
      end

    opts = [strategy: :one_for_one, name: SistemaEmergencia.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp iniciar_endpoint_web? do
    if Mix.env() == :test do
      true
    else
      case :gen_tcp.listen(4000, [:binary, active: false, ip: {127, 0, 0, 1}]) do
        {:ok, socket} ->
          :gen_tcp.close(socket)
          true

        {:error, :eaddrinuse} ->
          false

        _ ->
          true
      end
    end
  end
end

