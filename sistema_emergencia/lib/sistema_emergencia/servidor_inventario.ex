defmodule SistemaEmergencia.ServidorInventario do
  @moduledoc """
  GenServer encargado de Recursos, Necesidades y Albergues.
  Los callbacks `handle_call` son cortos y delegan la lógica a funciones puras privadas.
  """
  use GenServer

  alias SistemaEmergencia.Modelos
  alias SistemaEmergencia.Modelos.{Recurso, Necesidad, Albergue}
  alias SistemaEmergencia.{Persistencia, Recursividad, ProcesoAuditoria}

  @archivo_recursos "resources.txt"
  @archivo_necesidades "needs.txt"
  @archivo_albergues "shelters.txt"

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def registrar_recurso(codigo, nombre, categoria, cantidad, unidad, ubicacion, usuario \\ "sistema"),
    do: GenServer.call(__MODULE__, {:registrar_recurso, codigo, nombre, categoria, cantidad, unidad, ubicacion, usuario})

  def listar_recursos(filtros \\ %{}),
    do: GenServer.call(__MODULE__, {:listar_recursos, filtros})

  def transferir_recurso(codigo, origen, destino, cantidad, usuario \\ "sistema"),
    do: GenServer.call(__MODULE__, {:transferir_recurso, codigo, origen, destino, cantidad, usuario})

  def registrar_necesidad(id, tipo, cantidad, prioridad, zona, descripcion, responsable \\ "sistema"),
    do: GenServer.call(__MODULE__, {:registrar_necesidad, id, tipo, cantidad, prioridad, zona, descripcion, responsable})

  def listar_necesidades(filtros \\ %{}),
    do: GenServer.call(__MODULE__, {:listar_necesidades, filtros})

  def asignar_recurso(necesidad_id, criterio_recurso, cantidad, usuario \\ "sistema"),
    do: GenServer.call(__MODULE__, {:asignar_recurso, necesidad_id, criterio_recurso, cantidad, usuario})

  def registrar_albergue(codigo, nombre, zona, capacidad_maxima, usuario \\ "sistema"),
    do: GenServer.call(__MODULE__, {:registrar_albergue, codigo, nombre, zona, capacidad_maxima, usuario})

  def consultar_albergue(codigo),
    do: GenServer.call(__MODULE__, {:consultar_albergue, codigo})

  def registrar_ingreso_albergue(codigo, documento, usuario \\ "sistema"),
    do: GenServer.call(__MODULE__, {:ingreso_albergue, codigo, documento, usuario})

  def registrar_salida_albergue(codigo, documento, usuario \\ "sistema"),
    do: GenServer.call(__MODULE__, {:salida_albergue, codigo, documento, usuario})

  def reporte_albergues_mayor_ocupacion,
    do: GenServer.call(__MODULE__, :reporte_albergues)

  def recursos_criticos(umbral \\ 25),
    do: GenServer.call(__MODULE__, {:recursos_criticos, umbral})

  def reiniciar_estado,
    do: GenServer.call(__MODULE__, :reiniciar_estado)

  @impl true
  def init(_opts) do
    recursos = Persistencia.cargar_coleccion(@archivo_recursos, & &1.codigo)
    necesidades = Persistencia.cargar_coleccion(@archivo_necesidades, & &1.id)
    albergues = Persistencia.cargar_coleccion(@archivo_albergues, & &1.codigo)

    {:ok, %{recursos: recursos, necesidades: necesidades, albergues: albergues, contador_nec: map_size(necesidades) + 1}}
  end

  @impl true
  def handle_call(:reiniciar_estado, _from, _state) do
    Enum.each([@archivo_recursos, @archivo_necesidades, @archivo_albergues], &Persistencia.guardar_coleccion(&1, %{}))
    {:reply, :ok, %{recursos: %{}, necesidades: %{}, albergues: %{}, contador_nec: 1}}
  end

  @impl true
  def handle_call({:registrar_recurso, cod, nom, cat, cant, uni, ubi, user}, _from, state) do
    state = recargar_desde_disco(state)
    case construir_o_sumar_recurso(state.recursos, cod, nom, cat, cant, uni, ubi) do
      {:ok, recurso, nuevos_recursos} ->
        persistir_y_auditar(@archivo_recursos, nuevos_recursos, user, "register_resource", "#{cod} +#{cant}")
        {:reply, {:ok, recurso}, %{state | recursos: nuevos_recursos}}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:listar_recursos, filtros}, _from, state) do
    state = recargar_desde_disco(state)
    {:reply, filtrar_recursos(Map.values(state.recursos), filtros), state}
  end

  @impl true
  def handle_call({:transferir_recurso, cod, origen, destino, cant, user}, _from, state) do
    state = recargar_desde_disco(state)
    case ejecutar_transferencia(state.recursos, cod, origen, destino, cant) do
      {:ok, resultado, nuevos_recursos} ->
        persistir_y_auditar(@archivo_recursos, nuevos_recursos, user, "transfer_resource", "#{cod}: #{cant} -> #{destino}")
        {:reply, {:ok, resultado}, %{state | recursos: nuevos_recursos}}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:registrar_necesidad, id_opt, tipo, cant, prio, zona, desc, resp}, _from, state) do
    state = recargar_desde_disco(state)
    id = generar_id_necesidad(id_opt, state.contador_nec)

    case construir_necesidad(state.necesidades, id, tipo, cant, prio, zona, desc, resp) do
      {:ok, necesidad, nuevas_nec} ->
        persistir_y_auditar(@archivo_necesidades, nuevas_nec, resp, "register_need", "#{id} (#{tipo})")
        {:reply, {:ok, necesidad}, %{state | necesidades: nuevas_nec, contador_nec: state.contador_nec + 1}}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:listar_necesidades, filtros}, _from, state) do
    state = recargar_desde_disco(state)
    ordenadas =
      state.necesidades
      |> Map.values()
      |> filtrar_necesidades(filtros)
      |> Recursividad.ordenar_necesidades_por_prioridad()

    {:reply, ordenadas, state}
  end

  @impl true
  def handle_call({:asignar_recurso, nec_id, criterio_rec, cant, user}, _from, state) do
    state = recargar_desde_disco(state)
    case ejecutar_asignacion_atomica(state, nec_id, criterio_rec, cant) do
      {:ok, res, nuevo_state} ->
        Persistencia.guardar_coleccion(@archivo_recursos, nuevo_state.recursos)
        persistir_y_auditar(@archivo_necesidades, nuevo_state.necesidades, user, "assign_resource", "#{cant} -> #{nec_id}")
        {:reply, {:ok, res}, nuevo_state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:registrar_albergue, cod, nom, zona, cap, user}, _from, state) do
    state = recargar_desde_disco(state)
    case construir_albergue(state.albergues, cod, nom, zona, cap) do
      {:ok, albergue, nuevos_alb} ->
        persistir_y_auditar(@archivo_albergues, nuevos_alb, user, "register_shelter", "#{cod} cap=#{cap}")
        {:reply, {:ok, albergue}, %{state | albergues: nuevos_alb}}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:consultar_albergue, codigo}, _from, state) do
    state = recargar_desde_disco(state)
    case Map.get(state.albergues, codigo) do
      nil -> {:reply, {:error, :albergue_no_encontrado}, state}
      %Albergue{} = a -> {:reply, {:ok, %{albergue: a, cupos_disponibles: a.capacidad_maxima - a.ocupacion_actual}}, state}
    end
  end

  @impl true
  def handle_call({:ingreso_albergue, codigo, doc, user}, _from, state) do
    state = recargar_desde_disco(state)
    case cambiar_ocupacion_albergue(state.albergues, codigo, doc, :ingreso) do
      {:ok, alb, nuevos_alb} ->
        persistir_y_auditar(@archivo_albergues, nuevos_alb, user, "register_entry", "#{doc} -> #{codigo}")
        {:reply, {:ok, alb}, %{state | albergues: nuevos_alb}}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:salida_albergue, codigo, doc, user}, _from, state) do
    state = recargar_desde_disco(state)
    case cambiar_ocupacion_albergue(state.albergues, codigo, doc, :salida) do
      {:ok, alb, nuevos_alb} ->
        persistir_y_auditar(@archivo_albergues, nuevos_alb, user, "register_exit", "#{doc} <- #{codigo}")
        {:reply, {:ok, alb}, %{state | albergues: nuevos_alb}}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:reporte_albergues, _from, state) do
    state = recargar_desde_disco(state)
    ordenados = Enum.sort_by(Map.values(state.albergues), &porcentaje_ocupacion/1, :desc)
    {:reply, ordenados, state}
  end

  @impl true
  def handle_call({:recursos_criticos, umbral}, _from, state) do
    state = recargar_desde_disco(state)
    criticos = Recursividad.filtrar_recursivo(Map.values(state.recursos), &(&1.cantidad <= umbral))
    {:reply, criticos, state}
  end

  defp construir_o_sumar_recurso(recursos, codigo, nombre, categoria, cantidad, unidad, ubicacion) do
    with {:ok, cod} <- Modelos.validar_id(codigo),
         {:ok, cant} <- Modelos.validar_no_negativo(cantidad) do
      movimiento = {fecha_actual(), :entrada, cant, "Ingreso en #{ubicacion}"}

      recurso =
        case Map.get(recursos, cod) do
          nil -> %Recurso{codigo: cod, nombre: norm(nombre), categoria: categoria, cantidad: cant, unidad: unidad, ubicacion: ubicacion, historial: [movimiento]}
          %Recurso{} = r -> %Recurso{r | cantidad: r.cantidad + cant, historial: [movimiento | r.historial]}
        end

      {:ok, recurso, Map.put(recursos, cod, recurso)}
    end
  end

  defp ejecutar_transferencia(recursos, codigo, origen, destino, cantidad) do
    with {:ok, cant} <- Modelos.validar_cantidad_positiva(cantidad),
         %Recurso{} = rec <- Map.get(recursos, codigo) || {:error, :recurso_no_encontrado},
         true <- rec.ubicacion == origen || {:error, :ubicacion_origen_no_coincide},
         true <- rec.cantidad >= cant || {:error, :inventario_insuficiente} do
      cod_dest = "#{codigo}_#{destino}"
      rec_origen = %Recurso{rec | cantidad: rec.cantidad - cant, historial: [{fecha_actual(), :transferencia_salida, cant, "A #{destino}"} | rec.historial]}
      {:ok, rec_destino, mapa_intermedio} = construir_o_sumar_recurso(recursos, cod_dest, rec.nombre, rec.categoria, cant, rec.unidad, destino)

      {:ok, %{origen: rec_origen, destino: rec_destino}, Map.put(mapa_intermedio, codigo, rec_origen)}
    end
  end

  defp construir_necesidad(necesidades, id, tipo, cantidad, prioridad, zona, desc, resp) do
    with true <- not Map.has_key?(necesidades, id) || {:error, :id_necesidad_duplicado},
         {:ok, cant} <- Modelos.validar_cantidad_positiva(cantidad),
         {:ok, prio} <- Modelos.validar_prioridad(prioridad) do
      nueva = %Necesidad{id: id, tipo: norm(tipo), descripcion: desc, cantidad: cant, cantidad_asignada: 0, zona: zona, prioridad: prio, responsable: resp}
      {:ok, nueva, Map.put(necesidades, id, nueva)}
    end
  end

  defp ejecutar_asignacion_atomica(state, nec_id, criterio_rec, cantidad) do
    with {:ok, cant} <- Modelos.validar_cantidad_positiva(cantidad),
         %Necesidad{} = nec <- Map.get(state.necesidades, nec_id) || {:error, :necesidad_no_encontrada},
         :ok <- Modelos.transicion_necesidad_valida?(nec.estado, :asignada),
         {:ok, %Recurso{} = rec} <- buscar_recurso_con_stock(state.recursos, criterio_rec, cant) do
      rec_act = %Recurso{rec | cantidad: rec.cantidad - cant, historial: [{fecha_actual(), :asignacion, cant, "A #{nec.id}"} | rec.historial]}
      asignada = nec.cantidad_asignada + cant
      estado_nec = if asignada >= nec.cantidad, do: :atendida, else: :asignada
      nec_act = %Necesidad{nec | cantidad_asignada: asignada, estado: estado_nec}

      nuevo_state = %{state | recursos: Map.put(state.recursos, rec.codigo, rec_act), necesidades: Map.put(state.necesidades, nec.id, nec_act)}
      {:ok, %{necesidad: nec_act, recurso: rec_act}, nuevo_state}
    end
  end

  defp construir_albergue(albergues, codigo, nombre, zona, capacidad) do
    with {:ok, cod} <- Modelos.validar_id(codigo),
         true <- not Map.has_key?(albergues, cod) || {:error, :albergue_ya_existe},
         {:ok, cap} <- Modelos.validar_cantidad_positiva(capacidad) do
      alb = %Albergue{codigo: cod, nombre: nombre, zona: zona, capacidad_maxima: cap}
      {:ok, alb, Map.put(albergues, cod, alb)}
    end
  end

  defp cambiar_ocupacion_albergue(albergues, codigo, doc, :ingreso) do
    with %Albergue{} = a <- Map.get(albergues, codigo) || {:error, :albergue_no_encontrado},
         true <- not MapSet.member?(a.personas_alojadas, doc) || {:error, :persona_ya_en_albergue},
         true <- a.ocupacion_actual < a.capacidad_maxima || {:error, :capacidad_maxima_superada} do
      act = %Albergue{a | ocupacion_actual: a.ocupacion_actual + 1, personas_alojadas: MapSet.put(a.personas_alojadas, doc)}
      {:ok, act, Map.put(albergues, codigo, act)}
    end
  end

  defp cambiar_ocupacion_albergue(albergues, codigo, doc, :salida) do
    with %Albergue{} = a <- Map.get(albergues, codigo) || {:error, :albergue_no_encontrado},
         true <- MapSet.member?(a.personas_alojadas, doc) || {:error, :persona_no_estaba_en_albergue} do
      act = %Albergue{a | ocupacion_actual: max(0, a.ocupacion_actual - 1), personas_alojadas: MapSet.delete(a.personas_alojadas, doc)}
      {:ok, act, Map.put(albergues, codigo, act)}
    end
  end

  defp buscar_recurso_con_stock(mapa_recursos, criterio, cantidad_req) do
    c = norm(criterio)
    candidatos = Recursividad.filtrar_recursivo(Map.values(mapa_recursos), &(norm(&1.codigo) == c or norm(&1.nombre) == c))

    case candidatos do
      [] -> {:error, :recurso_no_encontrado}
      lista -> Enum.find(lista, &(&1.cantidad >= cantidad_req)) |> case do nil -> {:error, :inventario_insuficiente}; r -> {:ok, r} end
    end
  end

  defp filtrar_recursos(lista, f) do
    Recursividad.filtrar_recursivo(lista, fn r ->
      (is_nil(f[:tipo]) or norm(r.nombre) == norm(f[:tipo])) and
        (is_nil(f[:ubicacion]) or norm(r.ubicacion) == norm(f[:ubicacion]))
    end)
  end

  defp filtrar_necesidades(lista, f) do
    Recursividad.filtrar_recursivo(lista, fn n ->
      (is_nil(f[:zona]) or norm(n.zona) == norm(f[:zona])) and
        (is_nil(f[:tipo]) or norm(n.tipo) == norm(f[:tipo])) and
        (is_nil(f[:prioridad]) or n.prioridad == f[:prioridad]) and
        (is_nil(f[:estado]) or n.estado == f[:estado])
    end)
  end

  defp persistir_y_auditar(archivo, datos, usuario, accion, detalle) do
    Persistencia.guardar_coleccion(archivo, datos)
    ProcesoAuditoria.registrar_evento(usuario, accion, detalle)
  end

  defp recargar_desde_disco(state) do
    recursos = Persistencia.cargar_coleccion(@archivo_recursos, & &1.codigo)
    necesidades = Persistencia.cargar_coleccion(@archivo_necesidades, & &1.id)
    albergues = Persistencia.cargar_coleccion(@archivo_albergues, & &1.codigo)
    %{state | recursos: recursos, necesidades: necesidades, albergues: albergues, contador_nec: map_size(necesidades) + 1}
  end

  defp generar_id_necesidad(id, _) when is_binary(id) and byte_size(id) > 0, do: id
  defp generar_id_necesidad(_, cont), do: "N" <> String.pad_leading(Integer.to_string(cont), 3, "0")

  defp porcentaje_ocupacion(%Albergue{capacidad_maxima: c, ocupacion_actual: o}) when c > 0, do: o / c
  defp porcentaje_ocupacion(_), do: 0.0

  defp norm(v), do: v |> to_string() |> String.trim() |> String.downcase()
  defp fecha_actual, do: DateTime.utc_now() |> Calendar.strftime("%Y-%m-%d %H:%M:%S")
end
