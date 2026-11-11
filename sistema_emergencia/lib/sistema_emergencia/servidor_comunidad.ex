defmodule SistemaEmergencia.ServidorComunidad do
  @moduledoc """
  GenServer encargado de Usuarios, Zonas, Personas, Mensajes y Mascotas.
  Mantiene los `handle_call` breves delegando a funciones privadas pequeñas.
  """
  use GenServer

  alias SistemaEmergencia.Modelos
  alias SistemaEmergencia.Modelos.{Usuario, Zona, Sector, PuntoAtencion, Persona, MensajeFamiliar, ReporteMascota}
  alias SistemaEmergencia.{Persistencia, Recursividad, ProcesoAuditoria}

  @archivo_usuarios "users.txt"
  @archivo_zonas "zones.txt"
  @archivo_personas "people.txt"
  @archivo_mensajes "family_messages.txt"
  @archivo_mascotas "pets.txt"

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def conectar_usuario(username, password, rol \\ :ciudadano, zona \\ "general"),
    do: GenServer.call(__MODULE__, {:conectar, username, password, rol, zona})

  def buscar_usuario(username),
    do: GenServer.call(__MODULE__, {:buscar_usuario, username})

  def desconectar_usuario(username \\ nil),
    do: GenServer.call(__MODULE__, {:desconectar, username})

  def usuario_actual, do: GenServer.call(__MODULE__, :usuario_actual)

  def registrar_zona(codigo, nombre, nivel, afectados \\ 0),
    do: GenServer.call(__MODULE__, {:registrar_zona, codigo, nombre, nivel, afectados})

  def agregar_sector_a_zona(codigo_zona, id_sector, nombre_sector, afectados, puntos \\ []),
    do: GenServer.call(__MODULE__, {:agregar_sector, codigo_zona, id_sector, nombre_sector, afectados, puntos})

  def consultar_zona(codigo_zona), do: GenServer.call(__MODULE__, {:consultar_zona, codigo_zona})
  def listar_zonas, do: GenServer.call(__MODULE__, :listar_zonas)

  def reportar_persona(documento, nombre, zona, estado, edad \\ 30),
    do: GenServer.call(__MODULE__, {:reportar_persona, documento, nombre, zona, estado, edad})

  def buscar_persona(criterio), do: GenServer.call(__MODULE__, {:buscar_persona, criterio})
  def listar_personas, do: GenServer.call(__MODULE__, :listar_personas)

  def enviar_mensaje_familiar(doc_dest, contenido, remitente \\ "familiar"),
    do: GenServer.call(__MODULE__, {:enviar_mensaje, doc_dest, contenido, remitente})

  def listar_mensajes_familiares(doc_dest),
    do: GenServer.call(__MODULE__, {:listar_mensajes, doc_dest})

  def marcar_mensaje_entregado(id_mensaje),
    do: GenServer.call(__MODULE__, {:marcar_mensaje_entregado, id_mensaje})

  def reportar_mascota(tipo, especie, nombre, color, tamano, zona, contacto, caract \\ []),
    do: GenServer.call(__MODULE__, {:reportar_mascota, tipo, especie, nombre, color, tamano, zona, contacto, caract})

  def buscar_coincidencias_mascotas, do: GenServer.call(__MODULE__, :match_pets)

  def confirmar_coincidencia_mascota(perdida_id, encontrada_id),
    do: GenServer.call(__MODULE__, {:confirmar_match, perdida_id, encontrada_id})

  def listar_mascotas(filtros \\ %{}), do: GenServer.call(__MODULE__, {:listar_mascotas, filtros})
  def reiniciar_estado, do: GenServer.call(__MODULE__, :reiniciar_estado)

  @impl true
  def init(_opts) do
    {:ok,
     %{
       usuarios: Persistencia.cargar_coleccion(@archivo_usuarios, & &1.username),
       usuario_sesion: nil,
       zonas: Persistencia.cargar_coleccion(@archivo_zonas, & &1.codigo),
       personas: Persistencia.cargar_coleccion(@archivo_personas, & &1.documento),
       mensajes: Persistencia.cargar_coleccion(@archivo_mensajes, & &1.id),
       mascotas: Persistencia.cargar_coleccion(@archivo_mascotas, & &1.id)
     }}
  end

  @impl true
  def handle_call(:reiniciar_estado, _from, _state) do
    [@archivo_usuarios, @archivo_zonas, @archivo_personas, @archivo_mensajes, @archivo_mascotas]
    |> Enum.each(&Persistencia.guardar_coleccion(&1, %{}))

    {:reply, :ok, %{usuarios: %{}, usuario_sesion: nil, zonas: %{}, personas: %{}, mensajes: %{}, mascotas: %{}}}
  end

  @impl true
  def handle_call({:conectar, user, pass, rol, zona}, _from, state) do
    case autenticar_o_registrar(state.usuarios, user, pass, rol, zona) do
      {:ok, modo, usuario, nuevos_usuarios} ->
        persistir_y_auditar(@archivo_usuarios, nuevos_usuarios, usuario.username, "connect", "#{modo}")
        {:reply, {:ok, modo, usuario}, %{state | usuarios: nuevos_usuarios, usuario_sesion: usuario}}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:desconectar, username}, _from, state) do
    target = username || (state.usuario_sesion && state.usuario_sesion.username)

    case cerrar_sesion_usuario(state.usuarios, target) do
      {:ok, desconectado, nuevos_usuarios} ->
        persistir_y_auditar(@archivo_usuarios, nuevos_usuarios, desconectado.username, "disconnect", "Cierre")
        {:reply, {:ok, desconectado}, %{state | usuarios: nuevos_usuarios, usuario_sesion: nil}}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:usuario_actual, _from, state), do: {:reply, state.usuario_sesion, state}

  @impl true
  def handle_call({:buscar_usuario, username}, _from, state) do
    {:reply, Map.get(state.usuarios, String.trim(to_string(username))), state}
  end

  @impl true
  def handle_call({:registrar_zona, cod, nom, niv, afec}, _from, state) do
    case construir_zona(state.zonas, cod, nom, niv, afec) do
      {:ok, zona, nuevas_zonas} ->
        persistir_y_auditar(@archivo_zonas, nuevas_zonas, sesion(state), "register_zone", "#{cod} (#{niv})")
        {:reply, {:ok, zona}, %{state | zonas: nuevas_zonas}}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:agregar_sector, cod_zona, id_sec, nom_sec, afec, puntos}, _from, state) do
    case anexar_sector(state.zonas, cod_zona, id_sec, nom_sec, afec, puntos) do
      {:ok, zona_act, nuevas_zonas} ->
        Persistencia.guardar_coleccion(@archivo_zonas, nuevas_zonas)
        {:reply, {:ok, zona_act}, %{state | zonas: nuevas_zonas}}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:consultar_zona, cod_zona}, _from, state) do
    case Map.get(state.zonas, cod_zona) do
      nil -> {:reply, {:error, :zona_no_encontrada}, state}
      %Zona{} = z -> {:reply, {:ok, %{zona: z, estadisticas: Recursividad.estadisticas_zona(z)}}, state}
    end
  end

  @impl true
  def handle_call(:listar_zonas, _from, state), do: {:reply, Map.values(state.zonas), state}

  @impl true
  def handle_call({:reportar_persona, doc, nom, zona, est, edad}, _from, state) do
    case guardar_o_actualizar_persona(state.personas, doc, nom, zona, est, edad) do
      {:ok, persona, nuevas_personas} ->
        persistir_y_auditar(@archivo_personas, nuevas_personas, sesion(state), "report_person", "#{doc} -> #{est}")
        {:reply, {:ok, persona}, %{state | personas: nuevas_personas}}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:buscar_persona, criterio}, _from, state) do
    {:reply, filtrar_personas(Map.values(state.personas), criterio), state}
  end

  @impl true
  def handle_call(:listar_personas, _from, state), do: {:reply, Map.values(state.personas), state}

  @impl true
  def handle_call({:enviar_mensaje, doc_dest, contenido, remitente}, _from, state) do
    case construir_mensaje(state.mensajes, doc_dest, contenido, remitente) do
      {:ok, msg, nuevos_msgs} ->
        persistir_y_auditar(@archivo_mensajes, nuevos_msgs, sesion(state), "send_family_message", "Para #{doc_dest}")
        {:reply, {:ok, msg}, %{state | mensajes: nuevos_msgs}}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:listar_mensajes, doc_dest}, _from, state) do
    lista = Recursividad.filtrar_recursivo(Map.values(state.mensajes), &(&1.documento_destinatario == doc_dest))
    {:reply, lista, state}
  end

  @impl true
  def handle_call({:marcar_mensaje_entregado, id_msg}, _from, state) do
    case Map.get(state.mensajes, id_msg) do
      nil ->
        {:reply, {:error, :mensaje_no_encontrado}, state}

      %MensajeFamiliar{} = m ->
        act = %MensajeFamiliar{m | estado: :entregado}
        nuevos = Map.put(state.mensajes, id_msg, act)
        Persistencia.guardar_coleccion(@archivo_mensajes, nuevos)
        {:reply, {:ok, act}, %{state | mensajes: nuevos}}
    end
  end

  @impl true
  def handle_call({:reportar_mascota, tipo, esp, nom, col, tam, zona, cont, caract}, _from, state) do
    case construir_reporte_mascota(state.mascotas, tipo, esp, nom, col, tam, zona, cont, caract) do
      {:ok, rep, nuevas_mascotas} ->
        persistir_y_auditar(@archivo_mascotas, nuevas_mascotas, sesion(state), "report_pet", "#{rep.id} (#{rep.tipo})")
        {:reply, {:ok, rep}, %{state | mascotas: nuevas_mascotas}}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:match_pets, _from, state) do
    todas = Map.values(state.mascotas)
    perdidas = Recursividad.filtrar_recursivo(todas, &(&1.tipo == :perdida))
    encontradas = Recursividad.filtrar_recursivo(todas, &(&1.tipo == :encontrada))
    {:reply, Recursividad.buscar_coincidencias_mascotas(perdidas, encontradas), state}
  end

  @impl true
  def handle_call({:confirmar_match, p_id, e_id}, _from, state) do
    case cerrar_pareja_mascotas(state.mascotas, p_id, e_id) do
      {:ok, pareja, nuevas_mascotas} ->
        persistir_y_auditar(@archivo_mascotas, nuevas_mascotas, sesion(state), "confirm_pet_match", "#{p_id}<->#{e_id}")
        {:reply, {:ok, pareja}, %{state | mascotas: nuevas_mascotas}}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:listar_mascotas, filtros}, _from, state) do
    {:reply, filtrar_mascotas(Map.values(state.mascotas), filtros), state}
  end

  defp autenticar_o_registrar(usuarios, username, password, rol, zona) do
    with {:ok, id} <- Modelos.validar_id(username),
         {:ok, r} <- Modelos.validar_rol(rol) do
      case Map.get(usuarios, id) do
        nil ->
          nuevo = %Usuario{username: id, password: password, nombre: id, rol: r, zona: zona, conectado: true}
          {:ok, :registrado_y_conectado, nuevo, Map.put(usuarios, id, nuevo)}

        %Usuario{password: ^password} = u ->
          conectado = %Usuario{u | conectado: true}
          {:ok, :conectado, conectado, Map.put(usuarios, id, conectado)}

        %Usuario{} ->
          {:error, :credenciales_invalidas}
      end
    end
  end

  defp cerrar_sesion_usuario(usuarios, target) do
    case target && Map.get(usuarios, target) do
      nil -> {:error, :usuario_no_conectado}
      %Usuario{} = u -> {:ok, %Usuario{u | conectado: false}, Map.put(usuarios, u.username, %Usuario{u | conectado: false})}
    end
  end

  defp construir_zona(zonas, codigo, nombre, nivel, afectados) do
    with {:ok, cod} <- Modelos.validar_id(codigo),
         {:ok, niv} <- Modelos.validar_nivel_zona(nivel),
         {:ok, afec} <- Modelos.validar_no_negativo(afectados) do
      sector_base = %Sector{id: "#{cod}_S1", nombre: "Sector Base #{nombre}", afectados_estimados: div(afec, 2), puntos: [%PuntoAtencion{id: "#{cod}_P1", nombre: "Punto #{nombre}", capacidad: 100}]}
      zona = %Zona{codigo: cod, nombre: nombre, nivel: niv, afectados_estimados: afec, sectores: [sector_base]}
      {:ok, zona, Map.put(zonas, cod, zona)}
    end
  end

  defp anexar_sector(zonas, cod_zona, id_sec, nom_sec, afec, lista_puntos) do
    case Map.get(zonas, cod_zona) do
      nil ->
        {:error, :zona_no_encontrada}

      %Zona{} = z ->
        pts = Enum.map(lista_puntos, fn {i, n, c} -> %PuntoAtencion{id: i, nombre: n, capacidad: c} end)
        sec = %Sector{id: id_sec, nombre: nom_sec, afectados_estimados: afec, puntos: pts}
        z_act = %Zona{z | sectores: z.sectores ++ [sec]}
        {:ok, z_act, Map.put(zonas, cod_zona, z_act)}
    end
  end

  defp guardar_o_actualizar_persona(personas, documento, nombre, zona, estado, edad) do
    with {:ok, doc} <- Modelos.validar_id(documento),
         {:ok, est} <- Modelos.validar_estado_persona(estado) do
      f = fecha_actual()

      p =
        case Map.get(personas, doc) do
          nil -> %Persona{id: "PER_#{doc}", documento: doc, nombre: nombre, edad: edad, zona: zona, estado: est, historial_estados: [{f, :ninguno, est}]}
          %Persona{} = ex -> %Persona{ex | nombre: nombre, zona: zona, estado: est, historial_estados: [{f, ex.estado, est} | ex.historial_estados]}
        end

      {:ok, p, Map.put(personas, doc, p)}
    end
  end

  defp construir_mensaje(mensajes, doc_dest, contenido, remitente) do
    with {:ok, doc} <- Modelos.validar_id(doc_dest),
         {:ok, txt} <- Modelos.validar_id(contenido) do
      id = "MSG_" <> Integer.to_string(map_size(mensajes) + 1)
      msg = %MensajeFamiliar{id: id, documento_destinatario: doc, remitente: remitente, contenido: txt, fecha: fecha_actual()}
      {:ok, msg, Map.put(mensajes, id, msg)}
    end
  end

  defp construir_reporte_mascota(mascotas, tipo, esp, nom, col, tam, zona, cont, caract) do
    with {:ok, tipo_atom} <- normalizar_tipo_mascota(tipo) do
      id = "PET_" <> String.pad_leading(Integer.to_string(map_size(mascotas) + 1), 3, "0")
      set_c = caract |> List.wrap() |> Enum.map(&norm/1) |> MapSet.new()
      rep = %ReporteMascota{id: id, tipo: tipo_atom, especie: esp, nombre: nom, color: col, tamano: tam, caracteristicas: set_c, zona: zona, contacto: cont}
      {:ok, rep, Map.put(mascotas, id, rep)}
    end
  end

  defp cerrar_pareja_mascotas(mascotas, p_id, e_id) do
    with %ReporteMascota{} = p <- Map.get(mascotas, p_id) || {:error, :reporte_no_encontrado},
         %ReporteMascota{} = e <- Map.get(mascotas, e_id) || {:error, :reporte_no_encontrado},
         true <- (p.estado != :resuelta and e.estado != :resuelta) || {:error, :reporte_ya_resuelto} do
      p_res = %ReporteMascota{p | estado: :resuelta, pareja_id: e.id}
      e_res = %ReporteMascota{e | estado: :resuelta, pareja_id: p.id}
      {:ok, {p_res, e_res}, mascotas |> Map.put(p.id, p_res) |> Map.put(e.id, e_res)}
    end
  end

  defp filtrar_personas(lista, criterio) do
    c = norm(criterio)
    Recursividad.filtrar_recursivo(lista, &(norm(&1.documento) == c or String.contains?(norm(&1.nombre), c) or norm(&1.zona) == c or norm(&1.estado) == c))
  end

  defp filtrar_mascotas(lista, f) do
    Recursividad.filtrar_recursivo(lista, fn m ->
      (is_nil(f[:especie]) or norm(m.especie) == norm(f[:especie])) and
        (is_nil(f[:zona]) or norm(m.zona) == norm(f[:zona])) and
        (is_nil(f[:estado]) or m.estado == f[:estado])
    end)
  end

  defp normalizar_tipo_mascota(t) when t in [:perdida, "perdida", "lost"], do: {:ok, :perdida}
  defp normalizar_tipo_mascota(t) when t in [:encontrada, "encontrada", "found"], do: {:ok, :encontrada}
  defp normalizar_tipo_mascota(_), do: {:error, :tipo_reporte_mascota_invalido}

  defp persistir_y_auditar(archivo, datos, usuario, accion, detalle) do
    Persistencia.guardar_coleccion(archivo, datos)
    ProcesoAuditoria.registrar_evento(usuario, accion, detalle)
  end

  defp sesion(%{usuario_sesion: %Usuario{username: u}}), do: u
  defp sesion(_), do: "sistema"
  defp norm(v), do: v |> to_string() |> String.trim() |> String.downcase()
  defp fecha_actual, do: DateTime.utc_now() |> Calendar.strftime("%Y-%m-%d %H:%M:%S")
end
