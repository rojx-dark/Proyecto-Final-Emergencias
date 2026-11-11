defmodule SistemaEmergencia.CLI do
  @moduledoc """
  Interfaz de Menú Interactivo por Rol (Login/Registro automático y menús
  personalizados para Ciudadano, Voluntario, Coordinador y Administrador)
  + Intérprete de Comandos de Referencia (Sección 1.4.10).
  """

  alias SistemaEmergencia.{Modelos, ServidorInventario, ServidorComunidad, ProcesoAuditoria}
  alias SistemaEmergencia.Modelos.Usuario

  # ===========================================================================
  # 1. MENÚ PRINCIPAL DE ACCESO (LOGIN / REGISTRO AUTOMÁTICO)
  # ===========================================================================

  @doc "Inicia el sistema interactivo por menús numerados."
  def iniciar_consola do
    loop_acceso()
  end

  defp loop_acceso do
    IO.puts("\n==============================================================")
    IO.puts("   SISTEMA DISTRIBUIDO DE GESTIÓN DE EMERGENCIAS (ELIXIR)     ")
    IO.puts("==============================================================")
    IO.puts("  1. Ingresar / Registrarse (Correo o Usuario y Contraseña)")
    IO.puts("  2. Ejecutar Flujo de Ejemplo del PDF (Demostración)")
    IO.puts("  3. Simular Conflicto Concurrente (2 procesos pidiendo agua)")
    IO.puts("  4. Modo comando directo (Sección 1.4.10)")
    IO.puts("  0. Salir del sistema")
    IO.puts("--------------------------------------------------------------")

    case pedir("Seleccione una opción") do
      "1" ->
        flujo_login_o_registro()
        loop_acceso()

      "2" ->
        ejecutar_flujo_ejemplo()
        loop_acceso()

      "3" ->
        res = simular_conflicto_concurrente()
        IO.inspect(res, label: "\n[Resultado Conflicto Concurrente]")
        loop_acceso()

      "4" ->
        cmd = pedir("Escriba el comando exacto (ej. summary)")
        IO.inspect(ejecutar_comando(cmd), label: "Resultado")
        loop_acceso()

      "0" ->
        IO.puts("\n¡Hasta pronto! Cerrando sesión interactiva.")
        :ok

      _ ->
        IO.puts("\n[!] Opción no válida, intente de nuevo.")
        loop_acceso()
    end
  end

  defp flujo_login_o_registro do
    IO.puts("\n--- ACCESO AL SISTEMA ---")
    identificador = pedir("Ingrese su correo o nombre de usuario")
    password = pedir("Ingrese su contraseña")

    case ServidorComunidad.buscar_usuario(identificador) do
      nil ->
        IO.puts("\n[*] El usuario '#{identificador}' no existe. Iniciando registro automático...")
        rol = seleccionar_rol_interactivo()
        zona = pedir("Ingrese su zona principal (ej. centro, zona_norte, zona_sur)")

        case ServidorComunidad.conectar_usuario(identificador, password, rol, zona) do
          {:ok, :registrado_y_conectado, %Usuario{} = u} ->
            IO.puts("\n[OK] ¡Cuenta creada y conectada exitosamente como #{u.rol}!")
            loop_menu_usuario(u)

          {:error, motivo} ->
            IO.puts("\n[ERROR] No se pudo registrar: #{inspect(motivo)}")
        end

      %Usuario{} ->
        case ServidorComunidad.conectar_usuario(identificador, password) do
          {:ok, :conectado, %Usuario{} = u} ->
            IO.puts("\n[OK] ¡Bienvenido de nuevo, #{u.username} (Rol: #{u.rol} | Zona: #{u.zona})!")
            loop_menu_usuario(u)

          {:error, :credenciales_invalidas} ->
            IO.puts("\n[ERROR] Contraseña incorrecta para el usuario '#{identificador}'.")

          {:error, motivo} ->
            IO.puts("\n[ERROR] #{inspect(motivo)}")
        end
    end
  end

  defp seleccionar_rol_interactivo do
    IO.puts("\nSeleccione su tipo de usuario (Rol):")
    IO.puts("  1. Ciudadano     (Reportar necesidades, familiares, mensajes y mascotas)")
    IO.puts("  2. Voluntario    (Funciones de ciudadano + recursos e ingresos a albergues)")
    IO.puts("  3. Coordinador   (Gestión total: zonas, asignaciones, transferencias y reportes)")
    IO.puts("  4. Administrador (Control global y auditoría completa del sistema)")

    case pedir("Opción de rol (1-4)") do
      "1" -> :ciudadano
      "2" -> :voluntario
      "3" -> :coordinador
      "4" -> :administrador
      _ -> :ciudadano
    end
  end

  # ===========================================================================
  # 2. MENÚS PERSONALIZADOS SEGÚN EL ROL DEL USUARIO
  # ===========================================================================

  defp loop_menu_usuario(%Usuario{rol: :ciudadano} = u) do
    IO.puts("\n==============================================================")
    IO.puts("   MENÚ CIUDADANO | Usuario: #{u.username} | Zona: #{u.zona}")
    IO.puts("==============================================================")
    IO.puts("  1. Registrar una necesidad de ayuda (agua, alimentos, rescate...)")
    IO.puts("  2. Consultar necesidades registradas")
    IO.puts("  3. Reportar persona afectada / familiar")
    IO.puts("  4. Buscar persona por documento, nombre, zona o estado")
    IO.puts("  5. Enviar mensaje a un familiar")
    IO.puts("  6. Consultar mensajes de un familiar")
    IO.puts("  7. Reportar mascota perdida o encontrada")
    IO.puts("  8. Buscar coincidencias de mascotas (match_pets)")
    IO.puts("  9. Consultar cupos de un albergue")
    IO.puts("  0. Cerrar sesión (disconnect)")

    case pedir("Seleccione una acción") do
      "1" -> ui_registrar_necesidad(u); loop_menu_usuario(u)
      "2" -> ui_listar_necesidades(); loop_menu_usuario(u)
      "3" -> ui_reportar_persona(); loop_menu_usuario(u)
      "4" -> ui_buscar_persona(); loop_menu_usuario(u)
      "5" -> ui_enviar_mensaje(u); loop_menu_usuario(u)
      "6" -> ui_listar_mensajes(); loop_menu_usuario(u)
      "7" -> ui_reportar_mascota(); loop_menu_usuario(u)
      "8" -> ui_match_mascotas(); loop_menu_usuario(u)
      "9" -> ui_consultar_albergue(); loop_menu_usuario(u)
      "0" -> cerrar_sesion(u)
      _ -> IO.puts("[!] Opción inválida."); loop_menu_usuario(u)
    end
  end

  defp loop_menu_usuario(%Usuario{rol: :voluntario} = u) do
    IO.puts("\n==============================================================")
    IO.puts("   MENÚ VOLUNTARIO | Usuario: #{u.username} | Zona: #{u.zona}")
    IO.puts("==============================================================")
    IO.puts("  1. Registrar necesidad puntual")
    IO.puts("  2. Registrar entrada de recurso en centro de acopio")
    IO.puts("  3. Consultar inventario de recursos disponibles")
    IO.puts("  4. Reportar persona localizada o afectada")
    IO.puts("  5. Buscar persona afectada")
    IO.puts("  6. Registrar ingreso de persona a un albergue")
    IO.puts("  7. Registrar salida de persona de un albergue")
    IO.puts("  8. Consultar cupos de un albergue")
    IO.puts("  9. Reportar mascota perdida o encontrada")
    IO.puts("  10. Buscar coincidencias de mascotas (match_pets)")
    IO.puts("  0. Cerrar sesión (disconnect)")

    case pedir("Seleccione una acción") do
      "1" -> ui_registrar_necesidad(u); loop_menu_usuario(u)
      "2" -> ui_registrar_recurso(u); loop_menu_usuario(u)
      "3" -> ui_listar_recursos(); loop_menu_usuario(u)
      "4" -> ui_reportar_persona(); loop_menu_usuario(u)
      "5" -> ui_buscar_persona(); loop_menu_usuario(u)
      "6" -> ui_ingreso_albergue(u); loop_menu_usuario(u)
      "7" -> ui_salida_albergue(u); loop_menu_usuario(u)
      "8" -> ui_consultar_albergue(); loop_menu_usuario(u)
      "9" -> ui_reportar_mascota(); loop_menu_usuario(u)
      "10" -> ui_match_mascotas(); loop_menu_usuario(u)
      "0" -> cerrar_sesion(u)
      _ -> IO.puts("[!] Opción inválida."); loop_menu_usuario(u)
    end
  end

  defp loop_menu_usuario(%Usuario{rol: rol} = u) when rol in [:coordinador, :administrador] do
    titulo_rol = String.upcase(to_string(rol))
    IO.puts("\n==============================================================")
    IO.puts("   MENÚ #{titulo_rol} | Usuario: #{u.username} | Zona: #{u.zona}")
    IO.puts("==============================================================")
    IO.puts("  --- Zonas y Sectores ---")
    IO.puts("  1. Registrar zona afectada")
    IO.puts("  2. Agregar sector y puntos de atención a una zona")
    IO.puts("  3. Consultar estado y estadísticas recursivas de una zona")
    IO.puts("  --- Recursos y Necesidades ---")
    IO.puts("  4. Registrar recurso en inventario")
    IO.puts("  5. Registrar necesidad puntual")
    IO.puts("  6. Asignar recurso disponible a una necesidad (Atómico)")
    IO.puts("  7. Transferir recursos entre centros de apoyo")
    IO.puts("  8. Listar necesidades ordenadas por prioridad (QuickSort)")
    IO.puts("  9. Consultar recursos críticos en bajo stock")
    IO.puts("  --- Albergues, Personas y Mascotas ---")
    IO.puts("  10. Registrar nuevo albergue")
    IO.puts("  11. Registrar ingreso/salida en albergue y ver reporte de ocupación")
    IO.puts("  12. Reportar/Buscar personas y gestionar mensajes familiares")
    IO.puts("  13. Reportar mascotas, buscar y confirmar coincidencias")
    IO.puts("  --- Reportes Globales y Auditoría ---")
    IO.puts("  14. Ver Resumen Global de la Emergencia (summary)")
    IO.puts("  15. Ver Historial de Auditoría de Usuarios (Proceso Nativo)")
    IO.puts("  0. Cerrar sesión (disconnect)")

    case pedir("Seleccione una acción") do
      "1" -> ui_registrar_zona(); loop_menu_usuario(u)
      "2" -> ui_agregar_sector(); loop_menu_usuario(u)
      "3" -> ui_consultar_zona(); loop_menu_usuario(u)
      "4" -> ui_registrar_recurso(u); loop_menu_usuario(u)
      "5" -> ui_registrar_necesidad(u); loop_menu_usuario(u)
      "6" -> ui_asignar_recurso(u); loop_menu_usuario(u)
      "7" -> ui_transferir_recurso(u); loop_menu_usuario(u)
      "8" -> ui_listar_necesidades(); loop_menu_usuario(u)
      "9" -> IO.inspect(ServidorInventario.recursos_criticos(), label: "Recursos Críticos"); loop_menu_usuario(u)
      "10" -> ui_registrar_albergue(u); loop_menu_usuario(u)
      "11" -> ui_submenu_albergue(u); loop_menu_usuario(u)
      "12" -> ui_submenu_familia(u); loop_menu_usuario(u)
      "13" -> ui_submenu_mascotas(); loop_menu_usuario(u)
      "14" -> IO.inspect(resumen_global(), label: "Resumen Global"); loop_menu_usuario(u)
      "15" -> IO.inspect(ProcesoAuditoria.consultar_historial(), label: "Bitácora de Auditoría"); loop_menu_usuario(u)
      "0" -> cerrar_sesion(u)
      _ -> IO.puts("[!] Opción inválida."); loop_menu_usuario(u)
    end
  end

  defp cerrar_sesion(u) do
    ServidorComunidad.desconectar_usuario(u.username)
    IO.puts("\n[OK] Sesión cerrada para #{u.username}.")
  end

  # ===========================================================================
  # 3. FORMULARIOS INTERACTIVOS PASO A PASO (UI)
  # ===========================================================================

  defp ui_registrar_zona do
    codigo = pedir("Código de la zona (ej. Z01, centro)")
    nombre = pedir("Nombre de la zona")
    nivel = pedir("Nivel de afectación (critico / alto / medio / bajo)") |> String.to_atom()
    afectados = pedir_entero("Número estimado de personas afectadas")
    IO.inspect(ServidorComunidad.registrar_zona(codigo, nombre, nivel, afectados), label: "Resultado")
  end

  defp ui_agregar_sector do
    cod_zona = pedir("Código de la zona a la que pertenece")
    id_sec = pedir("ID del nuevo sector (ej. SEC_2)")
    nom_sec = pedir("Nombre del sector")
    afec = pedir_entero("Personas afectadas estimadas en el sector")
    id_pto = pedir("ID del punto de atención del sector (ej. PTO_1)")
    nom_pto = pedir("Nombre del punto de atención")
    cap_pto = pedir_entero("Capacidad del punto de atención")

    res = ServidorComunidad.agregar_sector_a_zona(cod_zona, id_sec, nom_sec, afec, [{id_pto, nom_pto, cap_pto}])
    IO.inspect(res, label: "Zona actualizada")
  end

  defp ui_consultar_zona do
    cod = pedir("Código de la zona a consultar")
    IO.inspect(ServidorComunidad.consultar_zona(cod), label: "Estado y Estadísticas Recursivas")
  end

  defp ui_registrar_necesidad(u) do
    tipo = pedir("Tipo (agua / alimentos / medicamentos / primeros_auxilios / refugio / rescate)")
    cantidad = pedir_entero("Cantidad requerida")
    prioridad = pedir("Prioridad (critica / alta / media / baja)") |> String.to_atom()
    zona = pedir("Zona afectada")
    desc = pedir("Descripción detallada")
    IO.inspect(ServidorInventario.registrar_necesidad(nil, tipo, cantidad, prioridad, zona, desc, u.username), label: "Necesidad Registrada")
  end

  defp ui_listar_necesidades do
    zona = pedir("Filtrar por zona (Enter para ver todas)")
    filtros = if zona == "", do: %{}, else: %{zona: zona}
    IO.inspect(ServidorInventario.listar_necesidades(filtros), label: "Necesidades (Ordenadas por Prioridad)")
  end

  defp ui_registrar_recurso(u) do
    codigo = pedir("Código del recurso (ej. R001)")
    nombre = pedir("Nombre del recurso (ej. agua, arroz, carpas)")
    categoria = pedir("Categoría (vital, alimentos, medico)")
    cantidad = pedir_entero("Cantidad a ingresar")
    unidad = pedir("Unidad de medida (litros, kilos, unidades)")
    ubicacion = pedir("Ubicación / Centro de acopio")
    IO.inspect(ServidorInventario.registrar_recurso(codigo, nombre, categoria, cantidad, unidad, ubicacion, u.username), label: "Recurso")
  end

  defp ui_listar_recursos do
    IO.inspect(ServidorInventario.listar_recursos(), label: "Inventario de Recursos")
  end

  defp ui_asignar_recurso(u) do
    nec_id = pedir("ID de la necesidad (ej. N001)")
    recurso = pedir("Código o nombre del recurso (ej. R001 o agua)")
    cant = pedir_entero("Cantidad a asignar")
    IO.inspect(ServidorInventario.asignar_recurso(nec_id, recurso, cant, u.username), label: "Asignación")
  end

  defp ui_transferir_recurso(u) do
    cod = pedir("Código del recurso a transferir (ej. R001)")
    origen = pedir("Ubicación origen (ej. centro_acopio_1)")
    destino = pedir("Ubicación destino (ej. albergue_2)")
    cant = pedir_entero("Cantidad a transferir")
    IO.inspect(ServidorInventario.transferir_recurso(cod, origen, destino, cant, u.username), label: "Transferencia")
  end

  defp ui_reportar_persona do
    doc = pedir("Documento de la persona")
    nom = pedir("Nombre completo")
    edad = pedir_entero("Edad")
    zona = pedir("Zona donde se reporta")
    est = pedir("Estado (sin_informacion / reportada / localizada / trasladada / en_albergue / reunificada)") |> String.to_atom()
    IO.inspect(ServidorComunidad.reportar_persona(doc, nom, zona, est, edad), label: "Persona")
  end

  defp ui_buscar_persona do
    crit = pedir("Ingrese documento, nombre, zona o estado a buscar")
    IO.inspect(ServidorComunidad.buscar_persona(crit), label: "Resultados de Búsqueda")
  end

  defp ui_enviar_mensaje(u) do
    doc = pedir("Documento del familiar destinatario")
    msg = pedir("Contenido del mensaje")
    IO.inspect(ServidorComunidad.enviar_mensaje_familiar(doc, msg, u.username), label: "Mensaje Enviado")
  end

  defp ui_listar_mensajes do
    doc = pedir("Documento de la persona para ver sus mensajes")
    IO.inspect(ServidorComunidad.listar_mensajes_familiares(doc), label: "Mensajes")
  end

  defp ui_reportar_mascota do
    tipo = pedir("Tipo de reporte (perdida / encontrada)")
    especie = pedir("Especie (perro / gato / otra)")
    nombre = pedir("Nombre (o 'desconocido')")
    color = pedir("Color principal")
    tamano = pedir("Tamaño (pequeno / mediano / grande)")
    zona = pedir("Zona del reporte")
    contacto = pedir("Teléfono o dato de contacto")
    caract = pedir("Características adicionales separadas por coma (ej. collar,mancha)") |> String.split(",", trim: true)
    IO.inspect(ServidorComunidad.reportar_mascota(tipo, especie, nombre, color, tamano, zona, contacto, [color, tamano | caract]), label: "Reporte Mascota")
  end

  defp ui_match_mascotas do
    IO.inspect(ServidorComunidad.buscar_coincidencias_mascotas(), label: "Posibles Coincidencias (Puntaje >= 65)")
  end

  defp ui_registrar_albergue(u) do
    cod = pedir("Código del albergue (ej. A01)")
    nom = pedir("Nombre del albergue")
    zona = pedir("Zona")
    cap = pedir_entero("Capacidad máxima de personas")
    IO.inspect(ServidorInventario.registrar_albergue(cod, nom, zona, cap, u.username), label: "Albergue")
  end

  defp ui_consultar_albergue do
    cod = pedir("Código del albergue (ej. A01)")
    IO.inspect(ServidorInventario.consultar_albergue(cod), label: "Estado del Albergue")
  end

  defp ui_ingreso_albergue(u) do
    cod = pedir("Código del albergue")
    doc = pedir("Documento de la persona que ingresa")
    IO.inspect(ServidorInventario.registrar_ingreso_albergue(cod, doc, u.username), label: "Ingreso")
  end

  defp ui_salida_albergue(u) do
    cod = pedir("Código del albergue")
    doc = pedir("Documento de la persona que sale")
    IO.inspect(ServidorInventario.registrar_salida_albergue(cod, doc, u.username), label: "Salida")
  end

  defp ui_submenu_albergue(u) do
    IO.puts("  a) Ingreso de persona  |  b) Salida de persona  |  c) Reporte de mayor ocupación")
    case pedir("Opción") do
      "a" -> ui_ingreso_albergue(u)
      "b" -> ui_salida_albergue(u)
      _ -> IO.inspect(ServidorInventario.reporte_albergues_mayor_ocupacion(), label: "Albergues por Ocupación")
    end
  end

  defp ui_submenu_familia(u) do
    IO.puts("  a) Reportar persona  |  b) Buscar persona  |  c) Enviar mensaje  |  d) Marcar mensaje entregado")
    case pedir("Opción") do
      "a" -> ui_reportar_persona()
      "b" -> ui_buscar_persona()
      "c" -> ui_enviar_mensaje(u)
      "d" ->
        id_m = pedir("ID del mensaje (ej. MSG_1)")
        IO.inspect(ServidorComunidad.marcar_mensaje_entregado(id_m), label: "Mensaje")
      _ -> :ok
    end
  end

  defp ui_submenu_mascotas do
    IO.puts("  a) Reportar mascota  |  b) Buscar coincidencias  |  c) Confirmar coincidencia y cerrar reportes")
    case pedir("Opción") do
      "a" -> ui_reportar_mascota()
      "b" -> ui_match_mascotas()
      "c" ->
        p_id = pedir("ID reporte mascota perdida (ej. PET_001)")
        e_id = pedir("ID reporte mascota encontrada (ej. PET_002)")
        IO.inspect(ServidorComunidad.confirmar_coincidencia_mascota(p_id, e_id), label: "Cierre de Reportes")
      _ -> :ok
    end
  end

  defp pedir(etiqueta) do
    IO.gets("  > #{etiqueta}: ") |> to_string() |> String.trim()
  end

  defp pedir_entero(etiqueta) do
    case Integer.parse(pedir(etiqueta)) do
      {num, _} -> num
      :error -> 0
    end
  end

  # ===========================================================================
  # 4. INTÉRPRETE DE COMANDOS DE REFERENCIA (Sección 1.4.10 del PDF)
  # ===========================================================================

  @doc """
  Recibe una cadena de texto con cualquiera de los comandos de la página 6 del PDF,
  separa los argumentos respetando comillas y despacha la acción.
  """
  def ejecutar_comando(linea) when is_binary(linea) do
    linea
    |> tokenizar()
    |> despachar()
  end

  defp despachar(["connect", user, pass, rol, zona]) do
    ServidorComunidad.conectar_usuario(user, pass, String.to_atom(rol), zona)
  end

  defp despachar(["connect", user, pass]) do
    ServidorComunidad.conectar_usuario(user, pass)
  end

  defp despachar(["disconnect"]) do
    ServidorComunidad.desconectar_usuario()
  end

  defp despachar(["register_zone", codigo, nombre, nivel]) do
    con_permiso(:registrar_zona, fn ->
      ServidorComunidad.registrar_zona(codigo, nombre, String.to_atom(nivel), 100)
    end)
  end

  defp despachar(["check_zone", codigo]) do
    ServidorComunidad.consultar_zona(codigo)
  end

  defp despachar(["register_need", tipo, cant_str, prio, zona, desc]) do
    con_permiso(:registrar_necesidad, fn ->
      {cant, _} = Integer.parse(cant_str)
      ServidorInventario.registrar_necesidad(nil, tipo, cant, String.to_atom(prio), zona, desc, usuario_activo())
    end)
  end

  defp despachar(["list_needs" | filtros_raw]) do
    filtros = parsear_filtros(filtros_raw)
    ServidorInventario.listar_necesidades(filtros)
  end

  defp despachar(["assign_resource", need_id, recurso, cant_str]) do
    con_permiso(:asignar_recurso, fn ->
      {cant, _} = Integer.parse(cant_str)
      ServidorInventario.asignar_recurso(need_id, recurso, cant, usuario_activo())
    end)
  end

  defp despachar(["register_resource", codigo, nombre, cant_str, unidad, ubicacion]) do
    con_permiso(:registrar_recurso, fn ->
      {cant, _} = Integer.parse(cant_str)
      ServidorInventario.registrar_recurso(codigo, nombre, "vital", cant, unidad, ubicacion, usuario_activo())
    end)
  end

  defp despachar(["list_resources" | filtros_raw]) do
    filtros = parsear_filtros(filtros_raw)
    ServidorInventario.listar_recursos(filtros)
  end

  defp despachar(["transfer_resource", codigo, origen, destino, cant_str]) do
    con_permiso(:transferir_recurso, fn ->
      {cant, _} = Integer.parse(cant_str)
      ServidorInventario.transferir_recurso(codigo, origen, destino, cant, usuario_activo())
    end)
  end

  defp despachar(["report_person", doc, nombre, zona, estado]) do
    con_permiso(:reportar_persona, fn ->
      ServidorComunidad.reportar_persona(doc, nombre, zona, String.to_atom(estado))
    end)
  end

  defp despachar(["find_person", criterio]) do
    ServidorComunidad.buscar_persona(criterio)
  end

  defp despachar(["send_family_message", doc, mensaje]) do
    con_permiso(:enviar_mensaje, fn ->
      ServidorComunidad.enviar_mensaje_familiar(doc, mensaje, usuario_activo())
    end)
  end

  defp despachar(["list_family_messages", doc]) do
    ServidorComunidad.listar_mensajes_familiares(doc)
  end

  defp despachar(["deliver_message", id_mensaje]) do
    ServidorComunidad.marcar_mensaje_entregado(id_mensaje)
  end

  defp despachar(["report_pet", tipo, especie, nombre, color, tamano, zona, contacto]) do
    con_permiso(:reportar_mascota, fn ->
      ServidorComunidad.reportar_mascota(tipo, especie, nombre, color, tamano, zona, contacto, [color, tamano])
    end)
  end

  defp despachar(["list_pets" | filtros_raw]) do
    filtros = parsear_filtros(filtros_raw)
    ServidorComunidad.listar_mascotas(filtros)
  end

  defp despachar(["match_pets"]) do
    ServidorComunidad.buscar_coincidencias_mascotas()
  end

  defp despachar(["confirm_pet_match", perdida_id, encontrada_id]) do
    ServidorComunidad.confirmar_coincidencia_mascota(perdida_id, encontrada_id)
  end

  defp despachar(["register_shelter", codigo, nombre, zona, cap_str]) do
    con_permiso(:registrar_albergue, fn ->
      {cap, _} = Integer.parse(cap_str)
      ServidorInventario.registrar_albergue(codigo, nombre, zona, cap, usuario_activo())
    end)
  end

  defp despachar(["check_shelter", codigo]) do
    ServidorInventario.consultar_albergue(codigo)
  end

  defp despachar(["shelter_report"]) do
    ServidorInventario.reporte_albergues_mayor_ocupacion()
  end

  defp despachar(["register_entry", codigo, doc]) do
    con_permiso(:ingreso_albergue, fn ->
      ServidorInventario.registrar_ingreso_albergue(codigo, doc, usuario_activo())
    end)
  end

  defp despachar(["register_exit", codigo, doc]) do
    con_permiso(:ingreso_albergue, fn ->
      ServidorInventario.registrar_salida_albergue(codigo, doc, usuario_activo())
    end)
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

  # ===========================================================================
  # 5. RESUMEN GLOBAL Y SIMULACIÓN DEL FLUJO DE EJEMPLO (Página 7 del PDF)
  # ===========================================================================

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

  defp con_permiso(accion, fun) do
    case ServidorComunidad.usuario_actual() do
      nil ->
        fun.()

      usuario ->
        case Modelos.autorizar_accion(usuario, accion) do
          :ok -> fun.()
          error -> error
        end
    end
  end
end
