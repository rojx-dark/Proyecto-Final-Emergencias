defmodule SistemaEmergencia.Modelos do
  @moduledoc """
  Capa de Dominio: Define todas las estructuras inmutables (Structs),
  tipos válidos y funciones puras de validación.
  """

  defmodule Usuario do
    defstruct [:username, :password, :nombre, :rol, :zona, conectado: false]
  end
  
  # Jerarquía anidada: Zona -> Sectores -> Puntos de Atención (Requisito 1.4.3)
  defmodule PuntoAtencion do
    defstruct [:id, :nombre, :capacidad]
  end
  defmodule Sector do
    defstruct [:id, :nombre, :afectados_estimados, puntos: []]
  end
  defmodule Zona do
    defstruct [
      :codigo,
      :nombre,
      :nivel, # :critico | :alto | :medio | :bajo
      :afectados_estimados,
      sectores: [],
      albergues_ids: MapSet.new(),
      necesidades_ids: MapSet.new(),
      recursos_ids: MapSet.new(),
      reportes_ids: MapSet.new()
    ]
  end
  defmodule Necesidad do
    defstruct [
      :id,
      :tipo,        # :agua, :alimentos, :medicamentos, :primeros_auxilios, :refugio, :transporte, :rescate, :otra
      :descripcion,
      :cantidad,
      :cantidad_asignada,
      :zona,
      :prioridad,   # :critica | :alta | :media | :baja
      :responsable,
      estado: :pendiente # :pendiente | :asignada | :en_atencion | :atendida | :cancelada
    ]
  end
  defmodule Recurso do
    defstruct [
      :codigo,
      :nombre,
      :categoria,
      :cantidad,
      :unidad,
      :ubicacion,
      historial: [] # Lista de tuplas: [{fecha, :entrada | :salida | :transferencia, cantidad, detalle}]
    ]
  end
  defmodule Persona do
    defstruct [
      :id,
      :documento,
      :nombre,
      :edad,
      :zona,
      estado: :reportada, # :sin_informacion | :reportada | :localizada | :trasladada | :en_albergue | :reunificada
      historial_estados: [] # Lista de tuplas: [{fecha, estado_anterior, estado_nuevo}]
    ]
  end
  defmodule MensajeFamiliar do
    defstruct [
      :id,
      :documento_destinatario,
      :remitente,
      :contenido,
      :fecha,
      estado: :pendiente # :pendiente | :entregado
    ]
  end
  defmodule ReporteMascota do
    defstruct [
      :id,
      :tipo,            # :perdida | :encontrada
      :especie,         # "perro", "gato", etc.
      :nombre,
      :color,
      :tamano,          # "pequeno", "mediano", "grande"
      :caracteristicas, # MapSet de palabras clave para comparar similitud
      :zona,
      :contacto,
      estado: :activa,  # :activa | :posible_coincidencia | :resuelta
      pareja_id: nil
    ]
  end
  defmodule Albergue do
    defstruct [
      :codigo,
      :nombre,
      :zona,
      :capacidad_maxima,
      ocupacion_actual: 0,
      personas_alojadas: MapSet.new(), # Documentos únicos sin repetirse
      recursos_ids: MapSet.new(),
      necesidades_ids: MapSet.new()
    ]
  end

  @roles_validos [:ciudadano, :voluntario, :coordinador, :administrador]
  @niveles_zona [:critico, :alto, :medio, :bajo]
  @prioridades [:critica, :alta, :media, :baja]
  @estados_persona [:sin_informacion, :reportada, :localizada, :trasladada, :en_albergue, :reunificada]

  @doc "Valida que un texto o identificador no esté vacío."
  def validar_id(id) when is_binary(id) and byte_size(id) > 0, do: {:ok, String.trim(id)}
  def validar_id(_), do: {:error, :identificador_invalido}

  @doc "Valida usando guards que una cantidad o capacidad sea un entero positivo."
  def validar_cantidad_positiva(n) when is_integer(n) and n > 0, do: {:ok, n}
  def validar_cantidad_positiva(_), do: {:error, :cantidad_debe_ser_positiva}

  @doc "Valida usando guards que un valor no sea negativo (>= 0)."
  def validar_no_negativo(n) when is_integer(n) and n >= 0, do: {:ok, n}
  def validar_no_negativo(_), do: {:error, :cantidad_negativa_no_permitida}

  @doc "Valida roles de usuario."
  def validar_rol(rol) when rol in @roles_validos, do: {:ok, rol}
  def validar_rol(_), do: {:error, :rol_invalido}

  @doc "Valida permisos según el tipo de usuario (Requisito 1.4.1)."
  def autorizar_accion(%Usuario{rol: :administrador}, _accion), do: :ok
  def autorizar_accion(%Usuario{rol: :coordinador}, _accion), do: :ok
  def autorizar_accion(%Usuario{rol: :voluntario}, accion)
      when accion in [:registrar_necesidad, :registrar_recurso, :reportar_persona, :reportar_mascota, :ingreso_albergue],
      do: :ok
  def autorizar_accion(%Usuario{rol: :ciudadano}, accion)
      when accion in [:registrar_necesidad, :reportar_persona, :enviar_mensaje, :reportar_mascota],
      do: :ok
  def autorizar_accion(_usuario, _accion), do: {:error, :permiso_denegado_para_rol}

  @doc "Valida niveles de afectación de una zona."
  def validar_nivel_zona(nivel) when nivel in @niveles_zona, do: {:ok, nivel}
  def validar_nivel_zona(_), do: {:error, :nivel_zona_invalido}

  @doc "Valida prioridad de una necesidad."
  def validar_prioridad(p) when p in @prioridades, do: {:ok, p}
  def validar_prioridad(_), do: {:error, :prioridad_invalida}

  @doc "Valida estado de persona afectada."
  def validar_estado_persona(e) when e in @estados_persona, do: {:ok, e}
  def validar_estado_persona(_), do: {:error, :estado_persona_invalido}

  @doc """
  Valida transiciones de estado para una Necesidad (Requisito 1.4.9).
  Impide que una necesidad ya :atendida o :cancelada vuelva a modificarse o consumir recursos.
  """
  def transicion_necesidad_valida?(:atendida, _nuevo), do: {:error, :necesidad_ya_atendida}
  def transicion_necesidad_valida?(:cancelada, _nuevo), do: {:error, :necesidad_ya_cancelada}
  def transicion_necesidad_valida?(:pendiente, nuevo) when nuevo in [:asignada, :en_atencion, :atendida, :cancelada], do: :ok
  def transicion_necesidad_valida?(:asignada, nuevo) when nuevo in [:en_atencion, :atendida, :cancelada], do: :ok
  def transicion_necesidad_valida?(:en_atencion, nuevo) when nuevo in [:atendida, :cancelada], do: :ok
  def transicion_necesidad_valida?(_, _), do: {:error, :transicion_estado_invalida}

  @doc """
  Convierte una prioridad en un peso numérico para poder ordenarla recursivamente.
  """
  def peso_prioridad(:critica), do: 4
  def peso_prioridad(:alta), do: 3
  def peso_prioridad(:media), do: 2
  def peso_prioridad(:baja), do: 1
  def peso_prioridad(_), do: 0
end
