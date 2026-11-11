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
    children = [
      SistemaEmergencia.ProcesoAuditoria,
      SistemaEmergencia.ServidorInventario,
      SistemaEmergencia.ServidorComunidad
    ]

    opts = [strategy: :one_for_one, name: SistemaEmergencia.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

