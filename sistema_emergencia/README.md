# Sistema Distribuido de Gestión de Emergencias (Elixir + OTP + Phoenix LiveView)

Proyecto Final de **Programación III** implementado en **Elixir** con arquitectura concurrente supervisada (**OTP GenServer + Procesos Nativos**), **recursividad funcional propia**, **persistencia en archivos de texto plano (`data/*.txt`)** e **interfaz web opcional en tiempo real con Phoenix LiveView**.

---

## 🚀 Cómo Ejecutar el Proyecto (Consola + Interfaz Web Phoenix)

Abre una terminal en la carpeta `sistema_emergencia` y ejecuta:

```bash
iex -S mix
```
*(O si solo deseas levantar el servidor web sin consola interactiva: `mix run --no-halt`)*

Al iniciar, el árbol de supervisión (`SistemaEmergencia.Supervisor`) levanta automáticamente:
1. **`SistemaEmergencia.ProcesoAuditoria`**: Proceso nativo independiente (`spawn_link` + `receive`) que registra cada actividad en memoria y en `data/activity_log.txt`.
2. **`SistemaEmergencia.ServidorInventario`**: `GenServer` para Recursos, Necesidades y Albergues.
3. **`SistemaEmergencia.ServidorComunidad`**: `GenServer` para Usuarios, Zonas, Personas, Mensajes Familiares y Mascotas.
4. **`SistemaEmergenciaWeb.Endpoint`**: Servidor web **Phoenix LiveView** en **`http://localhost:4000`**.

---

## 🌐 1. Uso desde la Interfaz Web (Phoenix LiveView)

Una vez ejecutado `iex -S mix` (o `mix run --no-halt`), abre en tu navegador:

👉 **[http://localhost:4000](http://localhost:4000)**

Desde la interfaz web puedes:
- **Iniciar sesión o registrarte** con cualquiera de los 4 roles (`:ciudadano`, `:voluntario`, `:coordinador`, `:administrador`).
- **▶ Cargar Flujo Ejemplo PDF**: ejecuta automáticamente toda la demostración de la Sección 1.4.10.
- **⚡ Simular Conflicto Concurrente (2 Procesos)**: lanza 2 procesos concurrentes (`Task.async`) pidiendo 30L y 25L de agua cuando solo hay 50L disponibles, mostrando en pantalla cómo el `GenServer` serializa el acceso y evita saldos negativos.
- Navegar por las **6 pestañas en tiempo real** (sincronizadas cada 2 segundos con la consola):
  1. **🗺️ Zonas y Sectores**: registro y visualización del árbol jerárquico `Zona -> Sectores -> Puntos` con **estadísticas recursivas**.
  2. **📦 Recursos y Necesidades**: inventario con **balance recursivo de movimientos**, necesidades ordenadas por prioridad mediante **QuickSort recursivo** y asignación atómica.
  3. **⛺ Albergues**: control de cupos, validación de capacidad máxima y no duplicidad mediante `MapSet`.
  4. **👨‍👩‍👧 Personas y Mensajes Familiares**: búsqueda recursiva y bandeja de mensajes en tiempo real con estado `:pendiente` / `:entregado`.
  5. **🐾 Mascotas y Matches**: algoritmo recursivo `match_pets` con puntaje de similitud (`>= 65/100`) y confirmación de reencuentro.
  6. **💻 Consola CLI & Auditoría**: intérprete web de comandos de la guía y bitácora en vivo del proceso nativo `ProcesoAuditoria`.

---

## 💻 2. Uso desde la Consola Interactiva (`IEx`)

Dentro de `iex -S mix` tienes disponibles los siguientes atajos:

```elixir
# Abrir el menú interactivo por roles (Ciudadano, Voluntario, Coordinador, Administrador)
SistemaEmergencia.menu()

# Ejecutar paso a paso el flujo completo del PDF (Página 7)
SistemaEmergencia.demo()

# Ejecutar la prueba de conflicto concurrente entre 2 procesos
SistemaEmergencia.conflicto()

# Ejecutar cualquier comando de texto de la Sección 1.4.10
SistemaEmergencia.cmd("summary")
```

---

## 🧪 Ejecutar las Pruebas Automatizadas (ExUnit)

```bash
mix test
```
