defmodule SistemaEmergencia.CLI do
  @moduledoc """
  Intérprete de Comandos de Referencia (Sección 1.4.10) y Simulación del
  Flujo de Ejemplo y Conflicto Concurrente.
  """

  alias SistemaEmergencia.{ServidorInventario, ServidorComunidad, ProcesoAuditoria}


  @doc "Inicia un bucle interactivo de consola para escribir comandos como en el PDF."
  def iniciar_consola do
    IO.puts("\n=== SISTEMA DISTRIBUIDO DE GESTIÓN DE EMERGENCIAS ===")
    IO.puts("Escribe un comando (ej. 'demo', 'conflicto', 'summary' o 'salir'):\n")
    loop_consola()
  end

  defp loop_consola do
    linea = IO.gets("emergencia> ") |> to_string() |> String.trim()

    case linea do
      "salir" ->
        IO.puts("Cerrando consola...")
        :ok

      "demo" ->
        ejecutar_flujo_ejemplo()
        loop_consola()

      "conflicto" ->
        simular_conflicto_concurrente()
        loop_consola()

      "" ->
        loop_consola()

      comando ->
         resultado = ejecutar_comando(comando)
        IO.inspect(resultado, label: "Resultado")
        loop_consola()
    end
  end

  @doc """
  Recibe una cadena de texto con cualquiera de los comandos de la página 6 del PDF,
  separa los argumentos respetando comillas y despacha la acción.
  """
  def ejecutar_comando(linea) when is_binary(linea) do
    linea
    |> tokenizar()
    |> despachar()
  end

  # connect usuario contraseña tipo zona
  defp despachar(["connect", user, pass, rol, zona]) do
    ServidorComunidad.conectar_usuario(user, pass, String.to_atom(rol), zona)
  end

  defp despachar(["connect", user, pass]) do
    ServidorComunidad.conectar_usuario(user, pass)
  end

  defp despachar(["disconnect"]) do
    ServidorComunidad.desconectar_usuario()
  end

  # register_zone codigo nombre nivel
  defp despachar(["register_zone", codigo, nombre, nivel]) do
    ServidorComunidad.registrar_zona(codigo, nombre, String.to_atom(nivel), 100)
  end

  # register_need tipo cantidad prioridad zona descripcion
  defp despachar(["register_need", tipo, cant_str, prio, zona, desc]) do
    {cant, _} = Integer.parse(cant_str)
    ServidorInventario.registrar_necesidad(nil, tipo, cant, String.to_atom(prio), zona, desc, usuario_activo())
  end

  # list_needs o list_needs zona=centro prioridad=critica
  defp despachar(["list_needs" | filtros_raw]) do
    filtros = parsear_filtros(filtros_raw)
    ServidorInventario.listar_necesidades(filtros)
  end

  # assign_resource need001 agua 20
  defp despachar(["assign_resource", need_id, recurso, cant_str]) do
    {cant, _} = Integer.parse(cant_str)
    ServidorInventario.asignar_recurso(need_id, recurso, cant, usuario_activo())
  end

  # register_resource R001 agua 200 litros centro_acopio_1
  defp despachar(["register_resource", codigo, nombre, cant_str, unidad, ubicacion]) do
    {cant, _} = Integer.parse(cant_str)
    ServidorInventario.registrar_recurso(codigo, nombre, "vital", cant, unidad, ubicacion, usuario_activo())
  end

  defp despachar(["list_resources"]) do
    ServidorInventario.listar_recursos()
  end

  # transfer_resource R001 centro_acopio_1 albergue_2 30
  defp despachar(["transfer_resource", codigo, origen, destino, cant_str]) do
    {cant, _} = Integer.parse(cant_str)
    ServidorInventario.transferir_recurso(codigo, origen, destino, cant, usuario_activo())
  end

  # report_person documento nombre zona estado
  defp despachar(["report_person", doc, nombre, zona, estado]) do
    ServidorComunidad.reportar_persona(doc, nombre, zona, String.to_atom(estado))
  end

  # find_person documento
  defp despachar(["find_person", criterio]) do
    ServidorComunidad.buscar_persona(criterio)
  end

  # send_family_message documento "Estoy bien, estoy en el albergue norte"
  defp despachar(["send_family_message", doc, mensaje]) do
    ServidorComunidad.enviar_mensaje_familiar(doc, mensaje, usuario_activo())
  end

  # list_family_messages documento
  defp despachar(["list_family_messages", doc]) do
    ServidorComunidad.listar_mensajes_familiares(doc)
  end

  # report_pet lost perro "Luna" negra mediana zona_norte contacto
  defp despachar(["report_pet", tipo, especie, nombre, color, tamano, zona, contacto]) do
    ServidorComunidad.reportar_mascota(tipo, especie, nombre, color, tamano, zona, contacto, [color, tamano])
  end

  defp despachar(["match_pets"]) do
    ServidorComunidad.buscar_coincidencias_mascotas()
  end

  # register_shelter A01 "Albergue Norte" zona_norte 150
  defp despachar(["register_shelter", codigo, nombre, zona, cap_str]) do
    {cap, _} = Integer.parse(cap_str)
    ServidorInventario.registrar_albergue(codigo, nombre, zona, cap, usuario_activo())
  end

  defp despachar(["check_shelter", codigo]) do
    ServidorInventario.consultar_albergue(codigo)
  end

  defp despachar(["register_entry", codigo, doc]) do
    ServidorInventario.registrar_ingreso_albergue(codigo, doc, usuario_activo())
  end

  defp despachar(["register_exit", codigo, doc]) do
    ServidorInventario.registrar_salida_albergue(codigo, doc, usuario_activo())
  end

  defp despachar(["critical_resources"]) do
    ServidorInventario.recursos_criticos()
  end

  defp despachar(["pending_needs"]) do
    ServidorInventario.listar_necesidades(%{estado: :pendiente})
  end

  defp despachar(["summary"]) do
    resumen_global()
  end

  defp despachar(otro) do
    {:error, {:comando_no_reconocido, otro}}
  end

  @doc "Genera el resumen global del estado de la emergencia (comando `summary`)."
  def resumen_global do
    %{
      recursos_disponibles: ServidorInventario.listar_recursos(),
      necesidades_pendientes: ServidorInventario.listar_necesidades(%{estado: :pendiente}),
      todas_las_necesidades: ServidorInventario.listar_necesidades(),
      personas_registradas: ServidorComunidad.listar_personas(),
      reportes_mascotas: ServidorComunidad.listar_mascotas(),
      coincidencias_mascotas: ServidorComunidad.buscar_coincidencias_mascotas(),
      albergues_por_ocupacion: ServidorInventario.reporte_albergues_mayor_ocupacion(),
      eventos_auditoria: length(ProcesoAuditoria.consultar_historial())
    }
  end

  @doc """
  Ejecuta paso a paso el Flujo de Ejemplo de la sección 1.4.10 (Página 7 del PDF),
  incluyendo la prueba de conflicto concurrente entre 2 solicitudes de agua.
  """
  def ejecutar_flujo_ejemplo do
    ServidorInventario.reiniciar_estado()
    ServidorComunidad.reiniciar_estado()

    IO.puts("\n--- 1. Laura se conecta como coordinadora de la zona centro ---")
    ejecutar_comando(~s(connect laura 1234 coordinador centro)) |> IO.inspect()
    ejecutar_comando(~s(register_zone centro "Zona Centro" critico))

    IO.puts("\n--- 2. Registra necesidad N001 (30L agua) y N002 (25L agua) ---")
    ejecutar_comando(~s(register_need agua 30 critica centro "Punto de atencion sector 3")) |> IO.inspect()
    ejecutar_comando(~s(register_need agua 25 alta centro "Punto de apoyo sector 1")) |> IO.inspect()

    IO.puts("\n--- 3. El centro de acopio registra solamente 50 litros de agua ---")
    ejecutar_comando(~s(register_resource R001 agua 50 litros centro_acopio_1)) |> IO.inspect()

    IO.puts("\n--- 4. CONCURRENCIA: Dos procesos intentan tomar 30L y 25L simultáneamente (Total 55L > 50L) ---")
    t1 = Task.async(fn -> ejecutar_comando("assign_resource N001 agua 30") end)
    t2 = Task.async(fn -> ejecutar_comando("assign_resource N002 agua 25") end)
    resultados_concurrencia = [Task.await(t1), Task.await(t2)]
    IO.inspect(resultados_concurrencia, label: "Resultados de asignación concurrente")

    IO.puts("\n--- 5. Registro de albergue, persona localizada (Andrés) y mensaje familiar ---")
    ejecutar_comando(~s(register_shelter A01 "Albergue Norte" zona_norte 150))
    ejecutar_comando(~s(report_person 1094 "Andres" zona_norte localizada))
    ejecutar_comando(~s(register_entry A01 1094))
    ejecutar_comando(~s(send_family_message 1094 "Estoy bien, estoy en el albergue norte"))

    IO.puts("\n--- 6. Reporte de mascota perdida y mascota encontrada + cálculo de coincidencias ---")
    ejecutar_comando(~s(report_pet lost perro "Luna" negra mediana zona_norte 3001112233))
    ejecutar_comando(~s(report_pet found perro "desconocido" negra mediana zona_norte 3109998877))
    coincidencias = ejecutar_comando("match_pets")
    IO.inspect(coincidencias, label: "Coincidencias de mascotas (match_pets)")

    IO.puts("\n--- 7. Resumen Global (summary) ---")
    resumen = ejecutar_comando("summary")
    IO.inspect(resumen, label: "Resumen Global")
    resumen
  end

  @doc """
  Demostración dedicada exclusivamente al conflicto concurrente para pruebas y sustentación.
  """
  def simular_conflicto_concurrente do
    ServidorInventario.reiniciar_estado()
    ServidorInventario.registrar_recurso("R001", "agua", "vital", 50, "litros", "acopio_central")
    ServidorInventario.registrar_necesidad("N001", "agua", 30, :critica, "centro", "Solicitud 1")
    ServidorInventario.registrar_necesidad("N002", "agua", 25, :alta, "centro", "Solicitud 2")

    tareas = [
      Task.async(fn -> ServidorInventario.asignar_recurso("N001", "agua", 30, "usuario_1") end),
      Task.async(fn -> ServidorInventario.asignar_recurso("N002", "agua", 25, "usuario_2") end)
    ]

    respuestas = Task.await_many(tareas)
    [recurso_final] = ServidorInventario.listar_recursos()

    %{
      respuestas_concurrentes: respuestas,
      stock_restante_agua: recurso_final.cantidad,
      historial_recurso: recurso_final.historial
    }
  end

  defp tokenizar(linea) do
    Regex.scan(~r/"([^"]*)"|(\S+)/, linea)
    |> Enum.map(fn
      [_, comillas] -> comillas
      [_, "", palabra] -> palabra
      [palabra | _] -> String.trim(palabra, ~s("))
    end)
  end

  defp parsear_filtros(lista_ares) do
    Enum.reduce(lista_ares, %{}, fn par, acc ->
      case String.split(par, "=", parts: 2) do
        ["prioridad", val] -> Map.put(acc, :prioridad, String.to_atom(val))
        ["estado", val] -> Map.put(acc, :estado, String.to_atom(val))
        [k, val] -> Map.put(acc, String.to_atom(k), val)
        _ -> acc
      end
    end)
  end

  defp usuario_activo do
    case ServidorComunidad.usuario_actual() do
      %{username: u} -> u
      _ -> "anonimo"
    end
  end
end
