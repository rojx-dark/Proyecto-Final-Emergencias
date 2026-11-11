defmodule SistemaEmergencia.Recursividad do
  @moduledoc """
  Capa de Algoritmos Recursivos Propios (Sin depender de Enum).
  Cumple con el requisito de tener al menos 4 funciones recursivas sobre
  listas y estructuras jerárquicas.
  """
  alias SistemaEmergencia.Modelos
  alias SistemaEmergencia.Modelos.{Zona, Sector, PuntoAtencion, Necesidad, ReporteMascota}

  @doc """
  Calcula las estadísticas acumuladas de una Zona recorriendo recursivamente
  sus Sectores y, dentro de cada sector, sus Puntos de Atención.
  Retorna un mapa con: total de sectores, total de puntos, capacidad total en
  puntos de atención y total estimado de personas afectadas.
  """
  def estadisticas_zona(%Zona{afectados_estimados: base_afectados, sectores: sectores}) do
    {num_sectores, num_puntos, cap_puntos, afectados_sectores} =
      recorrer_sectores(sectores, 0, 0, 0, 0)
    %{
      total_sectores: num_sectores,
      total_puntos_atencion: num_puntos,
      capacidad_puntos_atencion: cap_puntos,
      afectados_acumulados: (base_afectados || 0) + afectados_sectores
    }
  end

  # Caso base de sectores
  defp recorrer_sectores([], acc_sec, acc_pts, acc_cap, acc_afec) do
    {acc_sec, acc_pts, acc_cap, acc_afec}
  end

  # Caso recursivo de sectores: procesa la cabeza y baja al nivel de puntos de atención
  defp recorrer_sectores(
         [%Sector{afectados_estimados: afec, puntos: puntos} | resto_sectores],
         acc_sec,
         acc_pts,
         acc_cap,
         acc_afec
       ) do
    {pts_sector, cap_sector} = recorrer_puntos(puntos, 0, 0)
    recorrer_sectores(
      resto_sectores,
      acc_sec + 1,
      acc_pts + pts_sector,
      acc_cap + cap_sector,
      acc_afec + (afec || 0)
    )
  end

  # Caso base de puntos de atención
  defp recorrer_puntos([], acc_pts, acc_cap), do: {acc_pts, acc_cap}

  # Caso recursivo de puntos de atención
  defp recorrer_puntos([%PuntoAtencion{capacidad: cap} | resto_puntos], acc_pts, acc_cap) do
    recorrer_puntos(resto_puntos, acc_pts + 1, acc_cap + (cap || 0))
  end

  @doc """
  Ordena recursivamente una lista de Necesidades de mayor a menor prioridad
  (:critica > :alta > :media > :baja) utilizando QuickSort funcional puro.
  """
  def ordenar_necesidades_por_prioridad([]), do: []
  def ordenar_necesidades_por_prioridad([pivote | resto]) do
    peso_pivote = Modelos.peso_prioridad(pivote.prioridad)
    {mayores_o_iguales, menores} = particionar_necesidades(resto, peso_pivote, [], [])
    ordenar_necesidades_por_prioridad(mayores_o_iguales) ++
      [pivote] ++
      ordenar_necesidades_por_prioridad(menores)
  end
  defp particionar_necesidades([], _peso_pivote, mayores, menores) do
    {invertir_lista(mayores, []), invertir_lista(menores, [])}
  end
  defp particionar_necesidades([%Necesidad{} = actual | resto], peso_pivote, mayores, menores) do
    if Modelos.peso_prioridad(actual.prioridad) >= peso_pivote do
      particionar_necesidades(resto, peso_pivote, [actual | mayores], menores)
    else
      particionar_necesidades(resto, peso_pivote, mayores, [actual | menores])
    end
  end
  
  # Función auxiliar recursiva de cola para invertir listas
  defp invertir_lista([], acc), do: acc
  defp invertir_lista([h | t], acc), do: invertir_lista(t, [h | acc])

  @doc """
  Busca recursivamente posibles coincidencias entre reportes de mascotas
  perdidas (:perdida) y encontradas (:encontrada) que sigan activas.
  Criterio de puntaje (máximo 100 puntos):
    - Misma especie (obligatorio): +30 pts
    - Misma zona: +25 pts
    - Mismo color: +20 pts
    - Mismo tamaño: +15 pts
    - Características en común (MapSet.intersection): +10 pts
  Se considera posible coincidencia si el puntaje es >= 65.
  """
  def buscar_coincidencias_mascotas(perdidas, encontradas) do
    comparar_perdidas(perdidas, encontradas, [])
  end

  # Caso base: no quedan mascotas perdidas por comparar
  defp comparar_perdidas([], _encontradas, acc), do: invertir_lista(acc, [])

  # Caso recursivo: toma una mascota perdida y la compara contra todas las encontradas
  defp comparar_perdidas([%ReporteMascota{estado: :activa} = perdida | resto_perdidas], encontradas, acc) do
    coincidencias_para_esta = evaluar_contra_encontradas(perdida, encontradas, [])
    comparar_perdidas(resto_perdidas, encontradas, nuevas_coincidencias(coincidencias_para_esta, acc))
  end
  defp comparar_perdidas([_inactiva | resto_perdidas], encontradas, acc) do
    comparar_perdidas(resto_perdidas, encontradas, acc)
  end
  defp evaluar_contra_encontradas(_perdida, [], acc), do: acc
  defp evaluar_contra_encontradas(
         perdida,
         [%ReporteMascota{estado: :activa} = encontrada | resto_enc],
         acc
       ) do
    puntaje = calcular_puntaje_similitud(perdida, encontrada)
    if puntaje >= 65 do
      coincidencia = %{
        perdida_id: perdida.id,
        encontrada_id: encontrada.id,
        nombre_perdida: perdida.nombre,
        especie: perdida.especie,
        zona: perdida.zona,
        puntaje: puntaje
      }
      evaluar_contra_encontradas(perdida, resto_enc, [coincidencia | acc])
    else
      evaluar_contra_encontradas(perdida, resto_enc, acc)
    end
  end
  defp evaluar_contra_encontradas(perdida, [_inactiva | resto_enc], acc) do
    evaluar_contra_encontradas(perdida, resto_enc, acc)
  end
  defp calcular_puntaje_similitud(%ReporteMascota{} = p, %ReporteMascota{} = e) do
    if normalizar(p.especie) != normalizar(e.especie) do
      0
    else
      pts_especie = 30
      pts_zona = if normalizar(p.zona) == normalizar(e.zona), do: 25, else: 0
      pts_color = if normalizar(p.color) == normalizar(e.color), do: 20, else: 0
      pts_tamano = if normalizar(p.tamano) == normalizar(e.tamano), do: 15, else: 0
      comunes = MapSet.intersection(p.caracteristicas || MapSet.new(), e.caracteristicas || MapSet.new())
      pts_caract = if MapSet.size(comunes) > 0, do: 10, else: 0
      pts_especie + pts_zona + pts_color + pts_tamano + pts_caract
    end
  end
  defp normalizar(nil), do: ""
  defp normalizar(texto) when is_binary(texto), do: texto |> String.trim() |> String.downcase()
  defp normalizar(otro), do: to_string(otro) |> normalizar()
  defp nuevas_coincidencias([], acc), do: acc
  defp nuevas_coincidencias([h | t], acc), do: nuevas_coincidencias(t, [h | acc])

  @doc """
  Recorre recursivamente el historial de movimientos de un recurso
  (lista de tuplas `{fecha, tipo, cantidad, detalle}`) y calcula el total
  acumulado de entradas y salidas.
  """
  def balance_historial_movimientos(historial) do
    calcular_balance(historial, 0, 0)
  end
  defp calcular_balance([], entradas, salidas) do
    %{total_entradas: entradas, total_salidas: salidas, saldo_neto: entradas - salidas}
  end
  defp calcular_balance([{_fecha, :entrada, cant, _det} | resto], entradas, salidas) do
    calcular_balance(resto, entradas + cant, salidas)
  end
  defp calcular_balance([{_fecha, tipo, cant, _det} | resto], entradas, salidas)
       when tipo in [:salida, :asignacion, :transferencia_salida] do
    calcular_balance(resto, entradas, salidas + cant)
  end
  defp calcular_balance([_otro | resto], entradas, salidas) do
    calcular_balance(resto, entradas, salidas)
  end

  @doc """
  Función recursiva genérica para filtrar cualquier lista de elementos según
  un predicado sin usar Enum.filter/2.
  """
  def filtrar_recursivo(lista, funcion_predicado) do
    do_filtrar(lista, funcion_predicado, [])
  end
  defp do_filtrar([], _pred, acc), do: invertir_lista(acc, [])
  defp do_filtrar([h | t], pred, acc) do
    if pred.(h) do
      do_filtrar(t, pred, [h | acc])
    else
      do_filtrar(t, pred, acc)
    end
  end
end
