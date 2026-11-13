defmodule SistemaEmergenciaWeb.EmergenciaLive do
  @moduledoc """
  Vista interactiva en tiempo real (Phoenix LiveView) para el
  Sistema Distribuido de Gestión de Emergencias.
  Se comunica directamente con `ServidorInventario`, `ServidorComunidad`,
  `ProcesoAuditoria`, `Recursividad` y `CLI`.
  """
  use Phoenix.LiveView

  alias SistemaEmergencia.{
    ServidorInventario,
    ServidorComunidad,
    ProcesoAuditoria,
    Recursividad,
    Modelos,
    CLI
  }

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :timer.send_interval(2_000, self(), :tick_sync)
    end

    socket =
      socket
      |> assign(:tab, "zonas")
      |> assign(:flash_msg, nil)
      |> assign(:flash_type, :info)
      |> assign(:busqueda_persona, "")
      |> assign(:resultado_conflicto, nil)
      |> assign(:salida_comando, "Escriba un comando de la guía (ej. summary) y presione Ejecutar.")
      |> assign(:ultimo_comando, "summary")
      |> recargar_datos()

    {:ok, socket}
  end

  @impl true
  def handle_info(:tick_sync, socket) do
    anteriores = Map.new(socket.assigns[:mensajes] || [], &{&1.id, &1})
    nuevo_socket = recargar_datos(socket)
    actuales = nuevo_socket.assigns.mensajes

    nuevo_socket =
      Enum.reduce(actuales, nuevo_socket, fn m, acc ->
        case Map.get(anteriores, m.id) do
          nil ->
            notificar(
              acc,
              :success,
              "🔔 [TIEMPO REAL] Nuevo mensaje #{m.id} de '#{m.remitente}' para '#{m.documento_destinatario}': \"#{m.contenido}\""
            )

          prev when prev.estado != m.estado ->
            notificar(
              acc,
              :info,
              "✅ [TIEMPO REAL] El mensaje #{m.id} para '#{m.documento_destinatario}' cambió de :#{prev.estado} a :#{m.estado}"
            )

          _ ->
            acc
        end
      end)

    {:noreply, nuevo_socket}
  end

  @impl true
  def handle_event("cambiar_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :tab, tab)}
  end

  @impl true
  def handle_event("cerrar_alerta", _params, socket) do
    {:noreply, assign(socket, :flash_msg, nil)}
  end

  @impl true
  def handle_event("login", %{"username" => u, "password" => p, "rol" => r, "zona" => z}, socket) do
    rol_atom = String.to_existing_atom(r)

    case ServidorComunidad.buscar_usuario(u) do
      nil ->
        case ServidorComunidad.conectar_usuario(u, p, rol_atom, z) do
          {:ok, _, usuario} ->
            {:noreply,
             socket
             |> recargar_datos()
             |> notificar(:success, "Cuenta creada y conectada como #{usuario.username} (#{usuario.rol}).")}

          {:error, err} ->
            {:noreply, notificar(socket, :error, "Error al registrar usuario: #{inspect(err)}")}
        end

      _existente ->
        case ServidorComunidad.conectar_usuario(u, p) do
          {:ok, _, usuario} ->
            {:noreply,
             socket
             |> recargar_datos()
             |> notificar(:success, "¡Bienvenido de nuevo, #{usuario.username} (#{usuario.rol})!")}

          {:error, :credenciales_invalidas} ->
            {:noreply, notificar(socket, :error, "Contraseña incorrecta para '#{u}'.")}

          {:error, err} ->
            {:noreply, notificar(socket, :error, "Error: #{inspect(err)}")}
        end
    end
  end

  @impl true
  def handle_event("logout", _params, socket) do
    ServidorComunidad.desconectar_usuario()

    {:noreply,
     socket
     |> recargar_datos()
     |> notificar(:info, "Sesión cerrada correctamente.")}
  end

  @impl true
  def handle_event("ejecutar_demo_pdf", _params, socket) do
    CLI.ejecutar_flujo_ejemplo()

    {:noreply,
     socket
     |> recargar_datos()
     |> notificar(:success, "✅ Se ejecutó el Flujo Completo del PDF (Sección 1.4.10) en todos los GenServers.")}
  end

  @impl true
  def handle_event("simular_conflicto", _params, socket) do
    resultado = CLI.simular_conflicto_concurrente()

    {:noreply,
     socket
     |> assign(:resultado_conflicto, resultado)
     |> recargar_datos()
     |> notificar(:success, "⚡ Prueba de conflicto concurrente ejecutada (2 procesos pidiendo 30L y 25L sobre 50L).")}
  end

  @impl true
  def handle_event("reiniciar_sistema", _params, socket) do
    ServidorInventario.reiniciar_estado()
    ServidorComunidad.reiniciar_estado()

    {:noreply,
     socket
     |> assign(:resultado_conflicto, nil)
     |> recargar_datos()
     |> notificar(:info, "Estado de inventario y comunidad reiniciado.")}
  end

  @impl true
  def handle_event("registrar_zona", %{"codigo" => c, "nombre" => n, "nivel" => niv, "afectados" => af}, socket) do
    ejecutar_autorizado(socket, :registrar_zona, fn _user ->
      ServidorComunidad.registrar_zona(c, n, String.to_existing_atom(niv), parse_int(af))
    end, "Zona '#{c}' registrada exitosamente.")
  end

  @impl true
  def handle_event("agregar_sector", params, socket) do
    %{
      "cod_zona" => cz,
      "id_sec" => is,
      "nom_sec" => ns,
      "afectados" => af,
      "id_pto" => ip,
      "nom_pto" => np,
      "cap_pto" => cp
    } = params

    ejecutar_autorizado(socket, :registrar_zona, fn _user ->
      ServidorComunidad.agregar_sector_a_zona(cz, is, ns, parse_int(af), [{ip, np, parse_int(cp)}])
    end, "Sector '#{is}' y punto '#{ip}' anexados a la zona #{cz}.")
  end

  @impl true
  def handle_event("registrar_recurso", params, socket) do
    %{
      "codigo" => cod,
      "nombre" => nom,
      "categoria" => cat,
      "cantidad" => cant,
      "unidad" => uni,
      "ubicacion" => ubi
    } = params

    ejecutar_autorizado(socket, :registrar_recurso, fn user ->
      ServidorInventario.registrar_recurso(cod, nom, cat, parse_int(cant), uni, ubi, user)
    end, "Recurso '#{cod}' (#{nom}) ingresado al inventario.")
  end

  @impl true
  def handle_event("transferir_recurso", %{"codigo" => cod, "origen" => ori, "destino" => dest, "cantidad" => cant}, socket) do
    ejecutar_autorizado(socket, :transferir_recurso, fn user ->
      ServidorInventario.transferir_recurso(cod, ori, dest, parse_int(cant), user)
    end, "Transferencia de #{cant} unidades de #{cod} hacia #{dest} completada.")
  end

  @impl true
  def handle_event("registrar_necesidad", %{"tipo" => t, "cantidad" => c, "prioridad" => p, "zona" => z, "descripcion" => d}, socket) do
    ejecutar_autorizado(socket, :registrar_necesidad, fn user ->
      ServidorInventario.registrar_necesidad(nil, t, parse_int(c), String.to_existing_atom(p), z, d, user)
    end, "Necesidad de '#{t}' registrada y ordenada por prioridad.")
  end

  @impl true
  def handle_event("asignar_recurso", %{"nec_id" => nid, "criterio" => crit, "cantidad" => cant}, socket) do
    ejecutar_autorizado(socket, :asignar_recurso, fn user ->
      ServidorInventario.asignar_recurso(nid, crit, parse_int(cant), user)
    end, "Asignación atómica de #{cant} de '#{crit}' a necesidad #{nid} realizada.")
  end

  @impl true
  def handle_event("registrar_albergue", %{"codigo" => cod, "nombre" => nom, "zona" => z, "capacidad" => cap}, socket) do
    ejecutar_autorizado(socket, :registrar_albergue, fn user ->
      ServidorInventario.registrar_albergue(cod, nom, z, parse_int(cap), user)
    end, "Albergue '#{nom}' (#{cod}) registrado.")
  end

  @impl true
  def handle_event("movimiento_albergue", %{"codigo" => cod, "documento" => doc, "tipo" => tipo}, socket) do
    ejecutar_autorizado(socket, :ingreso_albergue, fn user ->
      if tipo == "ingreso" do
        ServidorInventario.registrar_ingreso_albergue(cod, doc, user)
      else
        ServidorInventario.registrar_salida_albergue(cod, doc, user)
      end
    end, "Movimiento (#{tipo}) de documento #{doc} en albergue #{cod} procesado.")
  end

  @impl true
  def handle_event("reportar_persona", %{"documento" => doc, "nombre" => nom, "edad" => ed, "zona" => z, "estado" => est}, socket) do
    ejecutar_autorizado(socket, :reportar_persona, fn _user ->
      ServidorComunidad.reportar_persona(doc, nom, z, String.to_existing_atom(est), parse_int(ed))
    end, "Persona #{nom} (#{doc}) actualizada a estado :#{est}.")
  end

  @impl true
  def handle_event("buscar_persona", %{"criterio" => crit}, socket) do
    {:noreply,
     socket
     |> assign(:busqueda_persona, String.trim(crit))
     |> recargar_datos()}
  end

  @impl true
  def handle_event("enviar_mensaje", %{"destinatario" => dest, "contenido" => cont}, socket) do
    ejecutar_autorizado(socket, :enviar_mensaje, fn user ->
      ServidorComunidad.enviar_mensaje_familiar(dest, cont, user)
    end, "Mensaje familiar enviado en tiempo real a #{dest}.")
  end

  @impl true
  def handle_event("entregar_mensaje", %{"id" => id_msg}, socket) do
    case ServidorComunidad.marcar_mensaje_entregado(id_msg) do
      {:ok, _} ->
        {:noreply,
         socket
         |> recargar_datos()
         |> notificar(:success, "✅ Mensaje #{id_msg} marcado como :entregado.")}

      {:error, err} ->
        {:noreply, notificar(socket, :error, "No se pudo marcar mensaje: #{inspect(err)}")}
    end
  end

  @impl true
  def handle_event("reportar_mascota", params, socket) do
    %{
      "tipo" => tipo,
      "especie" => esp,
      "nombre" => nom,
      "color" => col,
      "tamano" => tam,
      "zona" => zona,
      "contacto" => cont,
      "caract" => caract_str
    } = params

    caract =
      caract_str
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)

    ejecutar_autorizado(socket, :reportar_mascota, fn _user ->
      ServidorComunidad.reportar_mascota(tipo, esp, nom, col, tam, zona, cont, [col, tam | caract])
    end, "Reporte de mascota (#{tipo}) registrado.")
  end

  @impl true
  def handle_event("confirmar_match_mascota", %{"perdida" => p_id, "encontrada" => e_id}, socket) do
    case ServidorComunidad.confirmar_coincidencia_mascota(p_id, e_id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> recargar_datos()
         |> notificar(:success, "🐾 Reencuentro confirmado entre #{p_id} y #{e_id}. Reportes cerrados.")}

      {:error, err} ->
        {:noreply, notificar(socket, :error, "Error al confirmar coincidencia: #{inspect(err)}")}
    end
  end

  @impl true
  def handle_event("ejecutar_comando_cli", %{"comando" => cmd}, socket) do
    res = CLI.ejecutar_comando(cmd)
    formateado = inspect(res, pretty: true, limit: :infinity)

    {:noreply,
     socket
     |> assign(:ultimo_comando, cmd)
     |> assign(:salida_comando, formateado)
     |> recargar_datos()}
  end

  defp ejecutar_autorizado(socket, accion, fun, msg_exito) do
    usuario = socket.assigns.usuario_actual
    nombre_user = if usuario, do: usuario.username, else: "coordinador_web"

    permiso =
      if is_nil(usuario) do
        :ok
      else
        Modelos.autorizar_accion(usuario, accion)
      end

    case permiso do
      :ok ->
        case fun.(nombre_user) do
          {:ok, _} ->
            {:noreply, socket |> recargar_datos() |> notificar(:success, msg_exito)}

          {:error, motivo} ->
            {:noreply, notificar(socket, :error, "Operación rechazada: #{inspect(motivo)}")}
        end

      {:error, :permiso_denegado_para_rol} ->
        {:noreply,
         notificar(
           socket,
           :error,
           "Permiso denegado: Tu rol actual (:#{usuario.rol}) no tiene autorización para #{accion}."
         )}
    end
  end

  defp recargar_datos(socket) do
    criterio_p = socket.assigns[:busqueda_persona] || ""

    personas =
      if criterio_p == "" do
        ServidorComunidad.listar_personas()
      else
        ServidorComunidad.buscar_persona(criterio_p)
      end

    zonas_con_stats =
      ServidorComunidad.listar_zonas()
      |> Enum.map(fn z -> {z, Recursividad.estadisticas_zona(z)} end)

    recursos_con_balance =
      ServidorInventario.listar_recursos()
      |> Enum.map(fn r -> {r, Recursividad.balance_historial_movimientos(r.historial)} end)

    mensajes =
      ServidorComunidad.todos_los_mensajes()
      |> Map.values()
      |> Enum.sort_by(& &1.id, :desc)

    socket
    |> assign(:usuario_actual, ServidorComunidad.usuario_actual())
    |> assign(:zonas_stats, zonas_con_stats)
    |> assign(:recursos_balance, recursos_con_balance)
    |> assign(:recursos_criticos, ServidorInventario.recursos_criticos())
    |> assign(:necesidades, ServidorInventario.listar_necesidades())
    |> assign(:albergues, ServidorInventario.reporte_albergues_mayor_ocupacion())
    |> assign(:personas, personas)
    |> assign(:mensajes, mensajes)
    |> assign(:mascotas, ServidorComunidad.listar_mascotas())
    |> assign(:matches_mascotas, ServidorComunidad.buscar_coincidencias_mascotas())
    |> assign(:auditoria, Enum.reverse(ProcesoAuditoria.consultar_historial()))
  end

  defp notificar(socket, tipo, mensaje) do
    socket
    |> assign(:flash_type, tipo)
    |> assign(:flash_msg, mensaje)
  end

  defp parse_int(val) when is_integer(val), do: val
  defp parse_int(val) when is_binary(val) do
    case Integer.parse(String.trim(val)) do
      {n, _} -> n
      :error -> 0
    end
  end
  defp parse_int(_), do: 0

  defp porcentaje(actual, max) when is_integer(max) and max > 0 do
    min(100, round(actual / max * 100))
  end
  defp porcentaje(_, _), do: 0

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <!-- BARRA SUPERIOR -->
      <header class="topbar">
        <div class="container topbar-inner">
          <div class="brand">
            <div class="brand-icon">🚨</div>
            <div>
              <h1>Sistema Distribuido de Gestión de Emergencias</h1>
              <p>Elixir OTP · GenServer · Procesos Nativos · Recursividad · Phoenix LiveView</p>
            </div>
          </div>

          <div class="top-actions">
            <button phx-click="ejecutar_demo_pdf" class="btn btn-success btn-sm">
              ▶ Cargar Flujo Ejemplo PDF
            </button>
            <button phx-click="simular_conflicto" class="btn btn-warning btn-sm">
              ⚡ Simular Conflicto Concurrente (2 Procesos)
            </button>
            <button phx-click="reiniciar_sistema" class="btn btn-outline btn-sm">
              🗑️ Reiniciar Estado
            </button>
          </div>
        </div>
      </header>

      <main class="container" style="margin-top: 1.25rem;">
        <!-- NOTIFICACIÓN FLASH -->
        <%= if @flash_msg do %>
          <div class={"alert alert-#{@flash_type}"}>
            <span>{@flash_msg}</span>
            <button phx-click="cerrar_alerta" class="btn btn-outline btn-sm">✕</button>
          </div>
        <% end %>

        <!-- RESULTADO DE CONFLICTO CONCURRENTE (CUANDO SE EJECUTA) -->
        <%= if @resultado_conflicto do %>
          <div class="card" style="border-color: #f59e0b; background: rgba(245, 158, 11, 0.08);">
            <div class="card-title">
              <span>⚡ Resultado de Demostración de Concurrencia (2 Procesos pidiendo 30L y 25L con 50L en stock)</span>
              <span class="badge badge-alta">Stock Restante: {@resultado_conflicto.stock_restante_agua} Litros</span>
            </div>
            <p style="font-size: 0.84rem; color: var(--text-secondary); margin-bottom: 0.65rem;">
              El <code>ServidorInventario</code> (GenServer) serializó ambas peticiones concurrentes lanzadas con <code>Task.async/1</code>, garantizando que el inventario nunca quede negativo:
            </p>
            <pre class="code-output"><%= inspect(@resultado_conflicto.respuestas_concurrentes, pretty: true) %></pre>
          </div>
        <% end %>

        <!-- BARRA DE SESIÓN Y LOGIN -->
        <div class="card" style="padding: 0.9rem 1.2rem;">
          <%= if @usuario_actual do %>
            <div style="display: flex; flex-wrap: wrap; justify-content: space-between; align-items: center; gap: 1rem;">
              <div style="display: flex; align-items: center; gap: 0.75rem;">
                <span class="badge badge-ok">● CONECTADO</span>
                <strong>Usuario:</strong> <span>{@usuario_actual.username}</span>
                <span>|</span>
                <strong>Rol:</strong> <span class="badge badge-purple">{@usuario_actual.rol}</span>
                <span>|</span>
                <strong>Zona asignada:</strong> <span class="chip">{@usuario_actual.zona}</span>
              </div>
              <button phx-click="logout" class="btn btn-danger btn-sm">Cerrar Sesión (disconnect)</button>
            </div>
          <% else %>
            <form phx-submit="login" style="display: flex; flex-wrap: wrap; gap: 0.65rem; align-items: flex-end;">
              <div style="flex: 1; min-width: 150px;">
                <label>Usuario / Correo</label>
                <input type="text" name="username" placeholder="ej. laura" required />
              </div>
              <div style="flex: 1; min-width: 130px;">
                <label>Contraseña</label>
                <input type="password" name="password" placeholder="••••" required />
              </div>
              <div style="flex: 1; min-width: 150px;">
                <label>Rol (para registro nuevo)</label>
                <select name="rol">
                  <option value="coordinador">Coordinador (Control Total)</option>
                  <option value="administrador">Administrador (Auditoría + Total)</option>
                  <option value="voluntario">Voluntario (Acopio y Albergues)</option>
                  <option value="ciudadano">Ciudadano (Reportes y Mensajes)</option>
                </select>
              </div>
              <div style="flex: 1; min-width: 130px;">
                <label>Zona</label>
                <input type="text" name="zona" value="centro" required />
              </div>
              <button type="submit" class="btn btn-sm" style="height: 36px;">
                🔐 Conectar / Registrar
              </button>
            </form>
          <% end %>
        </div>

        <!-- TARJETAS KPI EN TIEMPO REAL -->
        <section class="kpi-grid">
          <div class="kpi-card">
            <span class="kpi-label">Zonas Afectadas</span>
            <span class="kpi-value">{length(@zonas_stats)}</span>
            <span class="kpi-sub">Jerarquía Zona → Sector → Punto</span>
          </div>
          <div class="kpi-card">
            <span class="kpi-label">Recursos en Inventario</span>
            <span class="kpi-value">{length(@recursos_balance)}</span>
            <span class="kpi-sub" style="color: #fca5a5;">{length(@recursos_criticos)} en estado crítico (≤25)</span>
          </div>
          <div class="kpi-card">
            <span class="kpi-label">Necesidades</span>
            <span class="kpi-value">{length(@necesidades)}</span>
            <span class="kpi-sub">Ordenadas con QuickSort Recursivo</span>
          </div>
          <div class="kpi-card">
            <span class="kpi-label">Albergues Activos</span>
            <span class="kpi-value">{length(@albergues)}</span>
            <span class="kpi-sub">Control de cupos con MapSet</span>
          </div>
          <div class="kpi-card">
            <span class="kpi-label">Personas y Mensajes</span>
            <span class="kpi-value">{length(@personas)} / {length(@mensajes)}</span>
            <span class="kpi-sub">Personas / Mensajes familiares</span>
          </div>
          <div class="kpi-card">
            <span class="kpi-label">Mascotas / Matches</span>
            <span class="kpi-value">{length(@mascotas)} / {length(@matches_mascotas)}</span>
            <span class="kpi-sub">Coincidencias con puntaje ≥ 65</span>
          </div>
          <div class="kpi-card">
            <span class="kpi-label">Eventos Auditoría</span>
            <span class="kpi-value">{length(@auditoria)}</span>
            <span class="kpi-sub">Proceso Nativo (spawn + receive)</span>
          </div>
        </section>

        <!-- PESTAÑAS DE NAVEGACIÓN -->
        <nav class="tabs">
          <button phx-click="cambiar_tab" phx-value-tab="zonas" class={"tab-btn #{if @tab == "zonas", do: "active"}"}>
            🗺️ 1. Zonas y Sectores ({length(@zonas_stats)})
          </button>
          <button phx-click="cambiar_tab" phx-value-tab="inventario" class={"tab-btn #{if @tab == "inventario", do: "active"}"}>
            📦 2. Recursos y Necesidades ({length(@necesidades)})
          </button>
          <button phx-click="cambiar_tab" phx-value-tab="albergues" class={"tab-btn #{if @tab == "albergues", do: "active"}"}>
            ⛺ 3. Albergues ({length(@albergues)})
          </button>
          <button phx-click="cambiar_tab" phx-value-tab="comunidad" class={"tab-btn #{if @tab == "comunidad", do: "active"}"}>
            👨‍👩‍👧 4. Personas y Mensajes ({length(@mensajes)})
          </button>
          <button phx-click="cambiar_tab" phx-value-tab="mascotas" class={"tab-btn #{if @tab == "mascotas", do: "active"}"}>
            🐾 5. Mascotas y Matches ({length(@matches_mascotas)})
          </button>
          <button phx-click="cambiar_tab" phx-value-tab="consola" class={"tab-btn #{if @tab == "consola", do: "active"}"}>
            💻 6. Consola CLI & Auditoría ({length(@auditoria)})
          </button>
        </nav>

        <!-- ==================== PESTAÑA 1: ZONAS Y SECTORES ==================== -->
        <%= if @tab == "zonas" do %>
          <div class="grid-2">
            <div>
              <div class="card">
                <div class="card-title">➕ Registrar Zona Afectada</div>
                <form phx-submit="registrar_zona">
                  <div class="form-row">
                    <div class="form-group">
                      <label>Código de Zona</label>
                      <input type="text" name="codigo" placeholder="ej. centro" required />
                    </div>
                    <div class="form-group">
                      <label>Nivel de Afectación</label>
                      <select name="nivel">
                        <option value="critico">Crítico</option>
                        <option value="alto">Alto</option>
                        <option value="medio">Medio</option>
                        <option value="bajo">Bajo</option>
                      </select>
                    </div>
                  </div>
                  <div class="form-row">
                    <div class="form-group">
                      <label>Nombre de la Zona</label>
                      <input type="text" name="nombre" placeholder="ej. Zona Centro" required />
                    </div>
                    <div class="form-group">
                      <label>Afectados Estimados</label>
                      <input type="number" name="afectados" value="120" min="0" required />
                    </div>
                  </div>
                  <button type="submit" class="btn">Registrar Zona</button>
                </form>
              </div>

              <div class="card">
                <div class="card-title">🏗️ Anexar Sector y Punto de Atención</div>
                <form phx-submit="agregar_sector">
                  <div class="form-row">
                    <div class="form-group">
                      <label>Código Zona Existente</label>
                      <input type="text" name="cod_zona" placeholder="ej. centro" required />
                    </div>
                    <div class="form-group">
                      <label>ID Sector</label>
                      <input type="text" name="id_sec" placeholder="ej. SEC_NORTE" required />
                    </div>
                  </div>
                  <div class="form-row">
                    <div class="form-group">
                      <label>Nombre del Sector</label>
                      <input type="text" name="nom_sec" placeholder="ej. Barrio San José" required />
                    </div>
                    <div class="form-group">
                      <label>Afectados en el Sector</label>
                      <input type="number" name="afectados" value="45" min="1" required />
                    </div>
                  </div>
                  <div class="form-row">
                    <div class="form-group">
                      <label>ID Punto Atención</label>
                      <input type="text" name="id_pto" placeholder="ej. PTO_2" required />
                    </div>
                    <div class="form-group">
                      <label>Nombre Punto Atención</label>
                      <input type="text" name="nom_pto" placeholder="ej. Escuela Municipal" required />
                    </div>
                  </div>
                  <div class="form-group">
                    <label>Capacidad del Punto de Atención</label>
                    <input type="number" name="cap_pto" value="80" min="1" required />
                  </div>
                  <button type="submit" class="btn btn-purple">Agregar Sector y Punto</button>
                </form>
              </div>
            </div>

            <div class="card">
              <div class="card-title">
                <span>🌳 Árbol Jerárquico y Estadísticas Recursivas (Zona → Sectores → Puntos)</span>
              </div>
              <%= if @zonas_stats == [] do %>
                <p style="color: var(--text-secondary);">No hay zonas registradas. Registre una o presione "Cargar Flujo Ejemplo PDF".</p>
              <% else %>
                <%= for {z, st} <- @zonas_stats do %>
                  <div style="border: 1px solid var(--border); border-radius: 10px; padding: 1rem; margin-bottom: 0.85rem; background: rgba(255,255,255,0.02);">
                    <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 0.5rem;">
                      <div>
                        <strong style="font-size: 1.05rem;">{z.nombre}</strong>
                        <span class="chip">{z.codigo}</span>
                      </div>
                      <span class={"badge badge-#{z.nivel}"}>Nivel {z.nivel}</span>
                    </div>

                    <div style="display: grid; grid-template-columns: repeat(4, 1fr); gap: 0.5rem; margin: 0.65rem 0; font-size: 0.8rem; background: var(--bg-input); padding: 0.6rem; border-radius: 8px;">
                      <div><strong>Sectores:</strong> {st.total_sectores}</div>
                      <div><strong>Puntos:</strong> {st.total_puntos_atencion}</div>
                      <div><strong>Capacidad Pts:</strong> {st.capacidad_puntos_atencion}</div>
                      <div><strong>Afectados Totales:</strong> {st.afectados_acumulados}</div>
                    </div>

                    <div style="font-size: 0.82rem; color: var(--text-secondary);">
                      <%= for s <- z.sectores do %>
                        <div style="margin-top: 0.35rem; padding-left: 0.6rem; border-left: 2px solid var(--accent);">
                          <strong>↳ Sector {s.id}:</strong> {s.nombre} ({s.afectados_estimados} afectados)
                          <div>
                            <%= for p <- s.puntos do %>
                              <span class="chip">📍 {p.id}: {p.nombre} (Cap: {p.capacidad})</span>
                            <% end %>
                          </div>
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              <% end %>
            </div>
          </div>
        <% end %>

        <!-- ==================== PESTAÑA 2: RECURSOS Y NECESIDADES ==================== -->
        <%= if @tab == "inventario" do %>
          <div class="grid-equal">
            <!-- COLUMNA RECURSOS -->
            <div>
              <div class="card">
                <div class="card-title">📥 Registrar Entrada de Recurso</div>
                <form phx-submit="registrar_recurso">
                  <div class="form-row">
                    <div class="form-group">
                      <label>Código (ej. R001)</label>
                      <input type="text" name="codigo" placeholder="R001" required />
                    </div>
                    <div class="form-group">
                      <label>Nombre (ej. agua, arroz)</label>
                      <input type="text" name="nombre" placeholder="agua" required />
                    </div>
                  </div>
                  <div class="form-row">
                    <div class="form-group">
                      <label>Categoría</label>
                      <select name="categoria">
                        <option value="vital">Vital / Agua</option>
                        <option value="alimentos">Alimentos</option>
                        <option value="medico">Médico / Primeros Auxilios</option>
                        <option value="refugio">Logística / Refugio</option>
                      </select>
                    </div>
                    <div class="form-group">
                      <label>Cantidad</label>
                      <input type="number" name="cantidad" value="50" min="1" required />
                    </div>
                  </div>
                  <div class="form-row">
                    <div class="form-group">
                      <label>Unidad</label>
                      <input type="text" name="unidad" value="litros" required />
                    </div>
                    <div class="form-group">
                      <label>Centro de Acopio / Ubicación</label>
                      <input type="text" name="ubicacion" value="centro_acopio_1" required />
                    </div>
                  </div>
                  <button type="submit" class="btn btn-success">Guardar Recurso</button>
                </form>
              </div>

              <div class="card">
                <div class="card-title">🚚 Transferir Recurso entre Centros</div>
                <form phx-submit="transferir_recurso">
                  <div class="form-row">
                    <div class="form-group">
                      <label>Código Recurso</label>
                      <input type="text" name="codigo" placeholder="R001" required />
                    </div>
                    <div class="form-group">
                      <label>Cantidad</label>
                      <input type="number" name="cantidad" value="10" min="1" required />
                    </div>
                  </div>
                  <div class="form-row">
                    <div class="form-group">
                      <label>Ubicación Origen</label>
                      <input type="text" name="origen" placeholder="centro_acopio_1" required />
                    </div>
                    <div class="form-group">
                      <label>Ubicación Destino</label>
                      <input type="text" name="destino" placeholder="albergue_norte" required />
                    </div>
                  </div>
                  <button type="submit" class="btn btn-outline">Transferir Recurso</button>
                </form>
              </div>

              <div class="card">
                <div class="card-title">
                  <span>📦 Inventario Actual y Balance Recursivo de Movimientos</span>
                </div>
                <table>
                  <thead>
                    <tr>
                      <th>Código</th>
                      <th>Recurso</th>
                      <th>Stock</th>
                      <th>Ubicación</th>
                      <th>Balance Recursivo (E/S)</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for {r, bal} <- @recursos_balance do %>
                      <tr>
                        <td><strong>{r.codigo}</strong></td>
                        <td>{r.nombre}</td>
                        <td>
                          <span class={"badge #{if r.cantidad <= 25, do: "badge-critica", else: "badge-ok"}"}>
                            {r.cantidad} {r.unidad}
                          </span>
                        </td>
                        <td>{r.ubicacion}</td>
                        <td style="font-size: 0.76rem;">
                          +{bal.total_entradas} / -{bal.total_salidas} (Neto: {bal.saldo_neto})
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            </div>

            <!-- COLUMNA NECESIDADES Y ASIGNACIÓN ATÓMICA -->
            <div>
              <div class="card">
                <div class="card-title">🆘 Reportar Necesidad de Ayuda</div>
                <form phx-submit="registrar_necesidad">
                  <div class="form-row">
                    <div class="form-group">
                      <label>Tipo de Recurso Requerido</label>
                      <input type="text" name="tipo" placeholder="ej. agua, alimentos, rescate" required />
                    </div>
                    <div class="form-group">
                      <label>Prioridad</label>
                      <select name="prioridad">
                        <option value="critica">Crítica (Peso 4)</option>
                        <option value="alta">Alta (Peso 3)</option>
                        <option value="media">Media (Peso 2)</option>
                        <option value="baja">Baja (Peso 1)</option>
                      </select>
                    </div>
                  </div>
                  <div class="form-row">
                    <div class="form-group">
                      <label>Cantidad Requerida</label>
                      <input type="number" name="cantidad" value="30" min="1" required />
                    </div>
                    <div class="form-group">
                      <label>Zona</label>
                      <input type="text" name="zona" value="centro" required />
                    </div>
                  </div>
                  <div class="form-group">
                    <label>Descripción / Punto Específico</label>
                    <input type="text" name="descripcion" placeholder="ej. Punto de atención sector 3" required />
                  </div>
                  <button type="submit" class="btn">Registrar Necesidad</button>
                </form>
              </div>

              <div class="card">
                <div class="card-title">⚡ Asignar Recurso a Necesidad (Operación Atómica GenServer)</div>
                <form phx-submit="asignar_recurso">
                  <div class="form-row">
                    <div class="form-group">
                      <label>ID Necesidad (ej. N001)</label>
                      <input type="text" name="nec_id" placeholder="N001" required />
                    </div>
                    <div class="form-group">
                      <label>Código o Nombre Recurso</label>
                      <input type="text" name="criterio" placeholder="agua o R001" required />
                    </div>
                  </div>
                  <div class="form-group">
                    <label>Cantidad a Despachar</label>
                    <input type="number" name="cantidad" value="25" min="1" required />
                  </div>
                  <button type="submit" class="btn btn-warning">Asignar Recurso Atómicamente</button>
                </form>
              </div>

              <div class="card">
                <div class="card-title">
                  <span>📋 Necesidades Ordenadas por Prioridad (QuickSort Recursivo)</span>
                </div>
                <table>
                  <thead>
                    <tr>
                      <th>ID</th>
                      <th>Prioridad</th>
                      <th>Tipo / Zona</th>
                      <th>Progreso</th>
                      <th>Estado</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for n <- @necesidades do %>
                      <tr>
                        <td><strong>{n.id}</strong></td>
                        <td><span class={"badge badge-#{n.prioridad}"}>{n.prioridad}</span></td>
                        <td>
                          <strong>{n.tipo}</strong> <span class="chip">{n.zona}</span>
                          <div style="font-size: 0.75rem; color: var(--text-secondary);">{n.descripcion}</div>
                        </td>
                        <td>
                          {n.cantidad_asignada} / {n.cantidad}
                          <div class="progress-bar">
                            <div class="progress-fill" style={"width: #{porcentaje(n.cantidad_asignada, n.cantidad)}%; background: var(--success);"}></div>
                          </div>
                        </td>
                        <td><span class="chip">:{n.estado}</span></td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        <% end %>

        <!-- ==================== PESTAÑA 3: ALBERGUES ==================== -->
        <%= if @tab == "albergues" do %>
          <div class="grid-2">
            <div>
              <div class="card">
                <div class="card-title">⛺ Registrar Nuevo Albergue</div>
                <form phx-submit="registrar_albergue">
                  <div class="form-row">
                    <div class="form-group">
                      <label>Código (ej. A01)</label>
                      <input type="text" name="codigo" placeholder="A01" required />
                    </div>
                    <div class="form-group">
                      <label>Zona</label>
                      <input type="text" name="zona" value="zona_norte" required />
                    </div>
                  </div>
                  <div class="form-row">
                    <div class="form-group">
                      <label>Nombre del Albergue</label>
                      <input type="text" name="nombre" placeholder="Albergue Norte" required />
                    </div>
                    <div class="form-group">
                      <label>Capacidad Máxima</label>
                      <input type="number" name="capacidad" value="150" min="1" required />
                    </div>
                  </div>
                  <button type="submit" class="btn">Crear Albergue</button>
                </form>
              </div>

              <div class="card">
                <div class="card-title">🚶 Ingreso / Salida de Personas en Albergue</div>
                <form phx-submit="movimiento_albergue">
                  <div class="form-row">
                    <div class="form-group">
                      <label>Código Albergue</label>
                      <input type="text" name="codigo" placeholder="A01" required />
                    </div>
                    <div class="form-group">
                      <label>Documento Persona</label>
                      <input type="text" name="documento" placeholder="1094" required />
                    </div>
                  </div>
                  <div class="form-group">
                    <label>Tipo de Movimiento</label>
                    <select name="tipo">
                      <option value="ingreso">Registrar Ingreso (Valida cupo y evita duplicados con MapSet)</option>
                      <option value="salida">Registrar Salida (Libera cupo)</option>
                    </select>
                  </div>
                  <button type="submit" class="btn btn-success">Procesar Movimiento</button>
                </form>
              </div>
            </div>

            <div class="card">
              <div class="card-title">📊 Albergues Ordenados por Mayor Porcentaje de Ocupación</div>
              <%= if @albergues == [] do %>
                <p style="color: var(--text-secondary);">No hay albergues registrados aún.</p>
              <% else %>
                <%= for a <- @albergues do %>
                  <% pct = porcentaje(a.ocupacion_actual, a.capacidad_maxima) %>
                  <div style="border: 1px solid var(--border); border-radius: 10px; padding: 1rem; margin-bottom: 0.8rem;">
                    <div style="display: flex; justify-content: space-between; align-items: center;">
                      <div>
                        <strong>{a.nombre}</strong> <span class="chip">{a.codigo}</span>
                        <span class="chip">Zona: {a.zona}</span>
                      </div>
                      <span class={"badge #{if pct >= 85, do: "badge-critica", else: "badge-ok"}"}>
                        Ocupación: {a.ocupacion_actual} / {a.capacidad_maxima} ({pct}%)
                      </span>
                    </div>
                    <div class="progress-bar" style="height: 10px; margin: 0.6rem 0;">
                      <div class="progress-fill" style={"width: #{pct}%; background: #{if pct >= 85, do: "var(--danger)", else: "var(--accent)"};"}></div>
                    </div>
                    <div style="font-size: 0.8rem; color: var(--text-secondary);">
                      <strong>Cupos disponibles:</strong> {a.capacidad_maxima - a.ocupacion_actual} |
                      <strong>Documentos alojados (MapSet):</strong>
                      <%= for doc <- MapSet.to_list(a.personas_alojadas) do %>
                        <span class="chip">🪪 {doc}</span>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              <% end %>
            </div>
          </div>
        <% end %>

        <!-- ==================== PESTAÑA 4: PERSONAS Y MENSAJES ==================== -->
        <%= if @tab == "comunidad" do %>
          <div class="grid-equal">
            <!-- PERSONAS -->
            <div>
              <div class="card">
                <div class="card-title">🧑 Reportar o Actualizar Estado de Persona</div>
                <form phx-submit="reportar_persona">
                  <div class="form-row">
                    <div class="form-group">
                      <label>Documento</label>
                      <input type="text" name="documento" placeholder="1094" required />
                    </div>
                    <div class="form-group">
                      <label>Nombre Completo</label>
                      <input type="text" name="nombre" placeholder="Andrés Pérez" required />
                    </div>
                  </div>
                  <div class="form-row">
                    <div class="form-group">
                      <label>Edad</label>
                      <input type="number" name="edad" value="28" min="0" required />
                    </div>
                    <div class="form-group">
                      <label>Zona</label>
                      <input type="text" name="zona" value="zona_norte" required />
                    </div>
                  </div>
                  <div class="form-group">
                    <label>Estado de la Persona</label>
                    <select name="estado">
                      <option value="localizada">Localizada</option>
                      <option value="en_albergue">En Albergue</option>
                      <option value="reunificada">Reunificada</option>
                      <option value="reportada">Reportada</option>
                      <option value="trasladada">Trasladada</option>
                      <option value="sin_informacion">Sin Información</option>
                    </select>
                  </div>
                  <button type="submit" class="btn">Guardar Reporte de Persona</button>
                </form>
              </div>

              <div class="card">
                <div class="card-title">
                  <span>🔍 Directorio y Búsqueda Recursiva de Personas</span>
                </div>
                <form phx-change="buscar_persona" phx-submit="buscar_persona" style="margin-bottom: 0.75rem;">
                  <input type="text" name="criterio" value={@busqueda_persona} placeholder="Filtrar en vivo por documento, nombre, zona o estado..." />
                </form>
                <table>
                  <thead>
                    <tr>
                      <th>Documento</th>
                      <th>Nombre</th>
                      <th>Zona</th>
                      <th>Estado Actual</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for p <- @personas do %>
                      <tr>
                        <td><strong>{p.documento}</strong></td>
                        <td>{p.nombre} ({p.edad} años)</td>
                        <td><span class="chip">{p.zona}</span></td>
                        <td><span class="badge badge-ok">:{p.estado}</span></td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            </div>

            <!-- MENSAJES FAMILIARES EN TIEMPO REAL -->
            <div>
              <div class="card">
                <div class="card-title">💬 Enviar Mensaje Familiar en Tiempo Real</div>
                <form phx-submit="enviar_mensaje">
                  <div class="form-group">
                    <label>Documento o Usuario Destinatario</label>
                    <input type="text" name="destinatario" placeholder="ej. 1094" required />
                  </div>
                  <div class="form-group">
                    <label>Mensaje de Tranquilidad / Ubicación</label>
                    <input type="text" name="contenido" placeholder="Estoy bien, estoy en el albergue norte" required />
                  </div>
                  <button type="submit" class="btn btn-purple">📨 Enviar Mensaje</button>
                </form>
              </div>

              <div class="card">
                <div class="card-title">
                  <span>📡 Bandeja de Mensajes en Tiempo Real</span>
                  <span class="chip">Sincronizado con Consola</span>
                </div>
                <%= if @mensajes == [] do %>
                  <p style="color: var(--text-secondary);">No hay mensajes familiares registrados.</p>
                <% else %>
                  <%= for m <- @mensajes do %>
                    <div style="border: 1px solid var(--border); border-radius: 9px; padding: 0.75rem; margin-bottom: 0.6rem; display: flex; justify-content: space-between; align-items: center; gap: 0.75rem;">
                      <div>
                        <div style="font-size: 0.78rem; color: var(--text-secondary);">
                          <strong>{m.id}</strong> · Para: <strong>{m.documento_destinatario}</strong> · De: {m.remitente} · {m.fecha}
                        </div>
                        <div style="margin-top: 0.2rem; font-size: 0.92rem;">"{m.contenido}"</div>
                      </div>
                      <div>
                        <%= if m.estado == :entregado do %>
                          <span class="badge badge-ok">✅ ENTREGADO</span>
                        <% else %>
                          <button phx-click="entregar_mensaje" phx-value-id={m.id} class="btn btn-success btn-sm">
                            Marcar Entregado
                          </button>
                        <% end %>
                      </div>
                    </div>
                  <% end %>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>

        <!-- ==================== PESTAÑA 5: MASCOTAS ==================== -->
        <%= if @tab == "mascotas" do %>
          <div class="grid-2">
            <div class="card">
              <div class="card-title">🐶 Reportar Mascota Perdida o Encontrada</div>
              <form phx-submit="reportar_mascota">
                <div class="form-row">
                  <div class="form-group">
                    <label>Tipo de Reporte</label>
                    <select name="tipo">
                      <option value="perdida">Perdida (:perdida)</option>
                      <option value="encontrada">Encontrada (:encontrada)</option>
                    </select>
                  </div>
                  <div class="form-group">
                    <label>Especie</label>
                    <select name="especie">
                      <option value="perro">Perro</option>
                      <option value="gato">Gato</option>
                      <option value="otra">Otra</option>
                    </select>
                  </div>
                </div>
                <div class="form-row">
                  <div class="form-group">
                    <label>Nombre (o 'desconocido')</label>
                    <input type="text" name="nombre" placeholder="Luna" required />
                  </div>
                  <div class="form-group">
                    <label>Color Principal</label>
                    <input type="text" name="color" placeholder="negra" required />
                  </div>
                </div>
                <div class="form-row">
                  <div class="form-group">
                    <label>Tamaño</label>
                    <select name="tamano">
                      <option value="pequeno">Pequeño</option>
                      <option value="mediano" selected>Mediano</option>
                      <option value="grande">Grande</option>
                    </select>
                  </div>
                  <div class="form-group">
                    <label>Zona</label>
                    <input type="text" name="zona" value="zona_norte" required />
                  </div>
                </div>
                <div class="form-row">
                  <div class="form-group">
                    <label>Teléfono Contacto</label>
                    <input type="text" name="contacto" placeholder="3001112233" required />
                  </div>
                  <div class="form-group">
                    <label>Rasgos (separados por coma)</label>
                    <input type="text" name="caract" placeholder="collar,mancha" />
                  </div>
                </div>
                <button type="submit" class="btn">Registrar Reporte de Mascota</button>
              </form>
            </div>

            <div>
              <div class="card" style="border-color: var(--purple);">
                <div class="card-title">
                  <span>✨ Coincidencias Detectadas por Algoritmo Recursivo (Puntaje ≥ 65/100)</span>
                </div>
                <%= if @matches_mascotas == [] do %>
                  <p style="color: var(--text-secondary);">No hay coincidencias activas en este momento.</p>
                <% else %>
                  <%= for m <- @matches_mascotas do %>
                    <div style="border: 1px solid rgba(139,92,246,0.4); background: rgba(139,92,246,0.08); border-radius: 10px; padding: 0.9rem; margin-bottom: 0.65rem; display: flex; justify-content: space-between; align-items: center;">
                      <div>
                        <strong>{m.perdida_id} ({m.nombre_perdida}) ↔ {m.encontrada_id}</strong>
                        <div style="font-size: 0.8rem; color: var(--text-secondary);">
                          Especie: {m.especie} | Zona: {m.zona} | <strong>Similitud: {m.puntaje} / 100 pts</strong>
                        </div>
                      </div>
                      <button
                        phx-click="confirmar_match_mascota"
                        phx-value-perdida={m.perdida_id}
                        phx-value-encontrada={m.encontrada_id}
                        class="btn btn-success btn-sm"
                      >
                        ✅ Confirmar Reencuentro
                      </button>
                    </div>
                  <% end %>
                <% end %>
              </div>

              <div class="card">
                <div class="card-title">🐾 Todos los Reportes de Mascotas</div>
                <table>
                  <thead>
                    <tr>
                      <th>ID</th>
                      <th>Tipo</th>
                      <th>Mascota</th>
                      <th>Zona</th>
                      <th>Estado</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for pet <- @mascotas do %>
                      <tr>
                        <td><strong>{pet.id}</strong></td>
                        <td><span class="chip">:{pet.tipo}</span></td>
                        <td>{pet.especie} "{pet.nombre}" ({pet.color}, {pet.tamano})</td>
                        <td>{pet.zona}</td>
                        <td>
                          <span class={"badge #{if pet.estado == :resuelta, do: "badge-ok", else: "badge-alta"}"}>
                            :{pet.estado} {if pet.pareja_id, do: "(#{pet.pareja_id})"}
                          </span>
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        <% end %>

        <!-- ==================== PESTAÑA 6: CONSOLA CLI Y AUDITORÍA ==================== -->
        <%= if @tab == "consola" do %>
          <div class="grid-equal">
            <div class="card">
              <div class="card-title">💻 Intérprete Web de Comandos Oficiales (Sección 1.4.10)</div>
              <form phx-submit="ejecutar_comando_cli" style="display: flex; gap: 0.5rem; margin-bottom: 0.75rem;">
                <input
                  type="text"
                  name="comando"
                  value={@ultimo_comando}
                  placeholder="ej. summary, match_pets, critical_resources..."
                  required
                />
                <button type="submit" class="btn">Ejecutar</button>
              </form>
              <div style="margin-bottom: 0.75rem; display: flex; flex-wrap: wrap; gap: 0.35rem;">
                <button phx-click="ejecutar_comando_cli" phx-value-comando="summary" class="btn btn-outline btn-sm">summary</button>
                <button phx-click="ejecutar_comando_cli" phx-value-comando="critical_resources" class="btn btn-outline btn-sm">critical_resources</button>
                <button phx-click="ejecutar_comando_cli" phx-value-comando="pending_needs" class="btn btn-outline btn-sm">pending_needs</button>
                <button phx-click="ejecutar_comando_cli" phx-value-comando="shelter_report" class="btn btn-outline btn-sm">shelter_report</button>
                <button phx-click="ejecutar_comando_cli" phx-value-comando="match_pets" class="btn btn-outline btn-sm">match_pets</button>
              </div>
              <pre class="code-output">{@salida_comando}</pre>
            </div>

            <div class="card">
              <div class="card-title">
                <span>🛡️ Bitácora del Proceso Nativo de Auditoría (spawn_link + receive)</span>
              </div>
              <table>
                <thead>
                  <tr>
                    <th>Fecha UTC</th>
                    <th>Usuario</th>
                    <th>Acción</th>
                    <th>Detalle</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for {fecha, user, acc, det} <- Enum.take(@auditoria, 20) do %>
                    <tr>
                      <td style="font-size: 0.75rem; color: var(--text-secondary);">
                        {Calendar.strftime(fecha, "%H:%M:%S")}
                      </td>
                      <td><span class="chip">{user}</span></td>
                      <td><strong>{acc}</strong></td>
                      <td>{det}</td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>
        <% end %>
      </main>
    </div>
    """
  end
end

