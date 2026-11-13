defmodule SistemaEmergenciaTest do
  use ExUnit.Case, async: false

  alias SistemaEmergencia.{ServidorInventario, ServidorComunidad, Recursividad, CLI}
  alias SistemaEmergencia.Modelos.{Zona, Sector, PuntoAtencion, Necesidad}

  setup do
    ServidorInventario.reiniciar_estado()
    ServidorComunidad.reiniciar_estado()
    :ok
  end

  test "1. Funciones recursivas: estadisticas jerarquicas de Zona -> Sectores -> Puntos" do
    zona = %Zona{
      codigo: "Z1",
      nombre: "Centro",
      nivel: :critico,
      afectados_estimados: 100,
      sectores: [
        %Sector{
          id: "S1",
          nombre: "Sector Norte",
          afectados_estimados: 50,
          puntos: [
            %PuntoAtencion{id: "P1", nombre: "Carpa 1", capacidad: 40},
            %PuntoAtencion{id: "P2", nombre: "Carpa 2", capacidad: 60}
          ]
        },
        %Sector{
          id: "S2",
          nombre: "Sector Sur",
          afectados_estimados: 30,
          puntos: [%PuntoAtencion{id: "P3", nombre: "Escuela", capacidad: 100}]
        }
      ]
    }

    stats = Recursividad.estadisticas_zona(zona)
    assert stats.total_sectores == 2
    assert stats.total_puntos_atencion == 3
    assert stats.capacidad_puntos_atencion == 200
    assert stats.afectados_acumulados == 180
  end

  test "2. Funciones recursivas: QuickSort ordena necesidades por prioridad" do
    n1 = %Necesidad{id: "N1", prioridad: :baja}
    n2 = %Necesidad{id: "N2", prioridad: :critica}
    n3 = %Necesidad{id: "N3", prioridad: :alta}
    n4 = %Necesidad{id: "N4", prioridad: :media}

    ordenadas = Recursividad.ordenar_necesidades_por_prioridad([n1, n2, n3, n4])
    assert Enum.map(ordenadas, & &1.id) == ["N2", "N3", "N4", "N1"]
  end

  test "3. Regla obligatoria de concurrencia: 2 procesos piden 30L y 25L con solo 50L en stock" do
    resultado = CLI.simular_conflicto_concurrente()

    # Exactamente una solicitud debe tener éxito {:ok, _} y la otra debe fallar {:error, :inventario_insuficiente}
    exitos = Enum.count(resultado.respuestas_concurrentes, &match?({:ok, _}, &1))
    rechazos = Enum.count(resultado.respuestas_concurrentes, &match?({:error, :inventario_insuficiente}, &1))

    assert exitos == 1
    assert rechazos == 1
    assert resultado.stock_restante_agua in [20, 25]
    assert resultado.stock_restante_agua >= 0
  end

  test "4. Albergues: impide superar la capacidad maxima y evita duplicados con MapSet" do
    {:ok, _} = ServidorInventario.registrar_albergue("A01", "Albergue Central", "centro", 1)
    assert {:ok, _} = ServidorInventario.registrar_ingreso_albergue("A01", "DOC_1")

    # No permite registrar a la misma persona dos veces
    assert {:error, :persona_ya_en_albergue} = ServidorInventario.registrar_ingreso_albergue("A01", "DOC_1")

    # No permite superar la capacidad máxima de 1 cupo
    assert {:error, :capacidad_maxima_superada} = ServidorInventario.registrar_ingreso_albergue("A01", "DOC_2")
  end

  test "5. Mascotas: algoritmo recursivo detecta coincidencias y evita doble cierre" do
    {:ok, p} = ServidorComunidad.reportar_mascota("lost", "perro", "Luna", "negra", "mediana", "zona_norte", "300", ["collar"])
    {:ok, e} = ServidorComunidad.reportar_mascota("found", "perro", "desconocido", "negra", "mediana", "zona_norte", "310", ["collar"])

    coincidencias = ServidorComunidad.buscar_coincidencias_mascotas()
    assert length(coincidencias) == 1
    assert hd(coincidencias).puntaje >= 65

    # Confirmar coincidencia cierra ambos reportes
    assert {:ok, _} = ServidorComunidad.confirmar_coincidencia_mascota(p.id, e.id)

    # Intentar cerrarlos una segunda vez debe fallar (Requisito 1.4.9)
    assert {:error, :reporte_ya_resuelto} = ServidorComunidad.confirmar_coincidencia_mascota(p.id, e.id)
  end

  test "6. Flujo de ejemplo completo de la pagina 7 se ejecuta sin errores" do
    resumen = CLI.ejecutar_flujo_ejemplo()
    assert length(resumen.personas_registradas) == 1
    assert length(resumen.coincidencias_mascotas) == 1
  end

  test "7. Interfaz Web Phoenix LiveView responde HTTP 200 con el panel de emergencias" do
    conn =
      Plug.Test.conn(:get, "/")
      |> SistemaEmergenciaWeb.Endpoint.call(SistemaEmergenciaWeb.Endpoint.init([]))

    assert conn.status == 200
    assert conn.resp_body =~ "Sistema Distribuido de Gestión de Emergencias"
    assert conn.resp_body =~ "Simular Conflicto Concurrente"
  end
end
