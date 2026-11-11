defmodule SistemaEmergencia.ProcesoAuditoria do
  @moduledoc """
  Proceso Independiente Nativo (spawn_link + receive loop).
  Cumple con los Objetivos de Aprendizaje (1.3 y 1.4.1):
    - Aplicar concurrencia mediante procesos de Elixir y paso de mensajes (`send` / `receive`).
    - Registrar la actividad realizada por cada usuario en segundo plano.
  """
  alias SistemaEmergencia.Persistencia
  @nombre_proceso :proceso_auditoria_emergencia

  @doc """
  Especificación `child_spec/1` para que el Supervisor principal de la aplicación
  pueda supervisar y reiniciar automáticamente este proceso nativo si falla.
  """
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  @doc "Inicia el proceso con `spawn_link` y lo registra bajo un nombre global local."
  def start_link(_opts \\ []) do
    pid = spawn_link(fn -> loop([]) end)
    Process.register(pid, @nombre_proceso)
    {:ok, pid}
  end

  @doc "Envía un mensaje asíncrono (`send`) al proceso de auditoría para registrar un evento."
  def registrar_evento(usuario, accion, detalle) do
    case Process.whereis(@nombre_proceso) do
      nil -> :error
      pid -> send(pid, {:registrar, usuario, accion, detalle})
    end
  end

  @doc "Solicita mediante paso de mensajes síncrono el historial en memoria del proceso."
  def consultar_historial do
    case Process.whereis(@nombre_proceso) do
      nil ->
        []
      pid ->
        send(pid, {:consultar, self()})
        receive do
          {:respuesta_historial, eventos} -> eventos
        after
          2_000 -> []
        end
    end
  end

  defp loop(eventos_memoria) do
    receive do
      {:registrar, usuario, accion, detalle} ->
        Persistencia.registrar_log_texto(usuario, accion, detalle)
        nuevo_evento = {DateTime.utc_now(), usuario, accion, detalle}
        loop([nuevo_evento | eventos_memoria])
      {:consultar, remitente_pid} ->
        send(remitente_pid, {:respuesta_historial, Enum.reverse(eventos_memoria)})
        loop(eventos_memoria)
      _otro ->
        loop(eventos_memoria)
    end
  end
end
