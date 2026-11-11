defmodule SistemaEmergencia.Persistencia do
  @moduledoc """
  Capa de Persistencia en Archivos de Texto Plano (Requisito 1.4.9).
  Guarda y carga las estructuras del sistema en la carpeta `data/` en formato
  de texto plano legible (una entidad por línea en notación Elixir/texto),
  además de escribir el registro histórico de actividades en `activity_log.txt`.
  """
  @data_dir "data"
  @doc "Asegura que la carpeta `data/` exista."
  def inicializar_directorio do
    File.mkdir_p!(@data_dir)
  end
  
  @doc """
  Guarda un mapa o colección de entidades en un archivo `.txt` de texto plano.
  Cada registro se escribe en una línea legible usando `inspect/2`.
  """
  def guardar_coleccion(nombre_archivo, mapa_datos) when is_map(mapa_datos) do
    inicializar_directorio()
    ruta = Path.join(@data_dir, nombre_archivo)
    contenido =
      mapa_datos
      |> Map.values()
      |> Enum.map(&inspect(&1, limit: :infinity, printable_limit: :infinity))
      |> Enum.join("\n")
    contenido_final = if contenido == "", do: "", else: contenido <> "\n"
    File.write(ruta, contenido_final)
  end

  @doc """
  Lee un archivo `.txt` de la carpeta `data/` y reconstruye el mapa de entidades
  usando ` funcion_clave ` para indexar cada elemento por su ID/código.
  Si el archivo no existe aún, retorna un mapa vacío `%{}`.
  """
  def cargar_coleccion(nombre_archivo, funcion_clave) do
    inicializar_directorio()
    ruta = Path.join(@data_dir, nombre_archivo)
    case File.read(ruta) do
      {:ok, contenido} ->
        contenido
        |> String.split("\n", trim: true)
        |> parsear_lineas(funcion_clave, %{})
      {:error, :enoent} ->
        %{}
      {:error, _razon} ->
        %{}
    end
  end

  # Recorrido recursivo para convertir cada línea del archivo .txt en su Struct
  defp parsear_lineas([], _funcion_clave, acc), do: acc
  defp parsear_lineas([linea | resto], funcion_clave, acc) do
    try do
      {termino, _binding} = Code.eval_string(linea)
      clave = funcion_clave.(termino)
      parsear_lineas(resto, funcion_clave, Map.put(acc, clave, termino))
    rescue
      _ -> parsear_lineas(resto, funcion_clave, acc)
    end
  end

  @doc """
  Agrega una línea de texto plano al archivo `data/activity_log.txt`
  con marca de tiempo, usuario y acción realizada.
  """
  def registrar_log_texto(usuario, accion, detalle) do
    inicializar_directorio()
    ruta = Path.join(@data_dir, "activity_log.txt")
    fecha = DateTime.utc_now() |> Calendar.strftime("%Y-%m-%d %H:%M:%S")
    linea = "[#{fecha}] USUARIO=#{usuario} | ACCION=#{accion} | DETalle=#{detalle}\n"
    File.write(ruta, linea, [:append])
  end

  @doc "Lee todas las líneas del historial de actividad en texto plano."
  def leer_logs do
    ruta = Path.join(@data_dir, "activity_log.txt")
    case File.read(ruta) do
      {:ok, contenido} -> String.split(contenido, "\n", trim: true)
      {:error, _} -> []
    end
  end
end
