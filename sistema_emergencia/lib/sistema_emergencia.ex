defmodule SistemaEmergencia do
  @moduledoc """
  Punto de entrada principal de SistemaEmergencia.
  Expone atajos directos para la demostración y consola interactiva.
  """

  alias SistemaEmergencia.CLI

  @doc "Ejecuta un comando de texto igual a la guía del proyecto."
  def cmd(comando), do: CLI.ejecutar_comando(comando)

  @doc "Ejecuta el flujo completo de ejemplo de la página 7 del PDF."
  def demo, do: CLI.ejecutar_flujo_ejemplo()

  @doc "Demuestra el conflicto concurrente entre múltiples procesos sobre un mismo recurso."
  def conflicto, do: CLI.simular_conflicto_concurrente()

  @doc "Abre el menú interactivo con login/registro y vistas según el rol del usuario."
  def menu, do: CLI.iniciar_consola()

  @doc "Abre la consola interactiva."
  def consola, do: CLI.iniciar_consola()
end
