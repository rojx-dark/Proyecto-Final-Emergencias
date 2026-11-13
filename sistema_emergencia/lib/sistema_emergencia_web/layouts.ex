defmodule SistemaEmergenciaWeb.ErrorHTML do
  @moduledoc """
  Renderizador de páginas de error HTTP para Phoenix.
  """
  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end

defmodule SistemaEmergenciaWeb.Layouts do
  @moduledoc """
  Layout raíz HTML5 para la interfaz web en Phoenix LiveView del
  Sistema Distribuido de Gestión de Emergencias.
  """
  use Phoenix.Component

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="es">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
        <title>Sistema de Gestión de Emergencias · Elixir & Phoenix</title>
        <style>
          :root {
            --bg-main: #0f172a;
            --bg-card: #1e293b;
            --bg-card-hover: #263449;
            --bg-input: #0b1120;
            --border: #334155;
            --text-primary: #f8fafc;
            --text-secondary: #94a3b8;
            --accent: #3b82f6;
            --accent-hover: #2563eb;
            --success: #10b981;
            --warning: #f59e0b;
            --danger: #ef4444;
            --purple: #8b5cf6;
          }
          * { box-sizing: border-box; margin: 0; padding: 0; }
          body {
            font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
            background-color: var(--bg-main);
            color: var(--text-primary);
            line-height: 1.5;
            padding-bottom: 3rem;
          }
          .container { max-width: 1380px; margin: 0 auto; padding: 0 1.25rem; }
          .topbar {
            background: linear-gradient(90deg, #0f172a 0%, #1e1b4b 50%, #0f172a 100%);
            border-bottom: 1px solid var(--border);
            padding: 1rem 0;
            position: sticky;
            top: 0;
            z-index: 40;
            backdrop-filter: blur(8px);
          }
          .topbar-inner {
            display: flex;
            flex-wrap: wrap;
            justify-content: space-between;
            align-items: center;
            gap: 1rem;
          }
          .brand {
            display: flex;
            align-items: center;
            gap: 0.75rem;
          }
          .brand-icon {
            width: 42px;
            height: 42px;
            border-radius: 10px;
            background: linear-gradient(135deg, #ef4444, #f97316);
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 1.35rem;
            box-shadow: 0 4px 12px rgba(239, 68, 68, 0.35);
          }
          .brand h1 { font-size: 1.2rem; font-weight: 700; letter-spacing: -0.02em; }
          .brand p { font-size: 0.78rem; color: var(--text-secondary); }
          .top-actions { display: flex; flex-wrap: wrap; gap: 0.5rem; align-items: center; }

          .btn {
            display: inline-flex;
            align-items: center;
            gap: 0.4rem;
            padding: 0.5rem 0.95rem;
            border-radius: 8px;
            font-size: 0.85rem;
            font-weight: 600;
            border: 1px solid transparent;
            cursor: pointer;
            transition: all 0.15s ease;
            color: #fff;
            background: var(--accent);
          }
          .btn:hover { background: var(--accent-hover); transform: translateY(-1px); }
          .btn-success { background: var(--success); }
          .btn-success:hover { background: #059669; }
          .btn-warning { background: var(--warning); color: #0f172a; }
          .btn-warning:hover { background: #d97706; color: #fff; }
          .btn-danger { background: var(--danger); }
          .btn-danger:hover { background: #dc2626; }
          .btn-purple { background: var(--purple); }
          .btn-purple:hover { background: #7c3aed; }
          .btn-outline {
            background: rgba(255,255,255,0.04);
            border-color: var(--border);
            color: var(--text-primary);
          }
          .btn-outline:hover { background: var(--bg-card-hover); }
          .btn-sm { padding: 0.3rem 0.65rem; font-size: 0.78rem; border-radius: 6px; }

          .kpi-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(175px, 1fr));
            gap: 0.85rem;
            margin: 1.25rem 0;
          }
          .kpi-card {
            background: var(--bg-card);
            border: 1px solid var(--border);
            border-radius: 12px;
            padding: 0.95rem 1.1rem;
            display: flex;
            flex-direction: column;
            gap: 0.25rem;
          }
          .kpi-label { font-size: 0.76rem; text-transform: uppercase; letter-spacing: 0.04em; color: var(--text-secondary); }
          .kpi-value { font-size: 1.65rem; font-weight: 800; }
          .kpi-sub { font-size: 0.76rem; color: var(--text-secondary); }

          .tabs {
            display: flex;
            flex-wrap: wrap;
            gap: 0.45rem;
            border-bottom: 1px solid var(--border);
            padding-bottom: 0.75rem;
            margin-bottom: 1.25rem;
          }
          .tab-btn {
            padding: 0.55rem 1rem;
            border-radius: 8px;
            font-size: 0.86rem;
            font-weight: 600;
            background: var(--bg-card);
            color: var(--text-secondary);
            border: 1px solid var(--border);
            cursor: pointer;
            transition: all 0.15s;
          }
          .tab-btn:hover { color: var(--text-primary); background: var(--bg-card-hover); }
          .tab-btn.active {
            background: var(--accent);
            color: #fff;
            border-color: var(--accent);
            box-shadow: 0 3px 10px rgba(59, 130, 246, 0.35);
          }

          .grid-2 { display: grid; grid-template-columns: 1fr 1.6fr; gap: 1.25rem; }
          .grid-equal { display: grid; grid-template-columns: 1fr 1fr; gap: 1.25rem; }
          @media (max-width: 960px) {
            .grid-2, .grid-equal { grid-template-columns: 1fr; }
          }

          .card {
            background: var(--bg-card);
            border: 1px solid var(--border);
            border-radius: 12px;
            padding: 1.2rem;
            margin-bottom: 1.1rem;
          }
          .card-title {
            font-size: 1rem;
            font-weight: 700;
            margin-bottom: 0.9rem;
            display: flex;
            align-items: center;
            justify-content: space-between;
            gap: 0.5rem;
            border-bottom: 1px solid rgba(255,255,255,0.06);
            padding-bottom: 0.55rem;
          }

          .form-group { margin-bottom: 0.75rem; }
          .form-row { display: grid; grid-template-columns: 1fr 1fr; gap: 0.65rem; }
          label { display: block; font-size: 0.78rem; color: var(--text-secondary); margin-bottom: 0.25rem; font-weight: 600; }
          input, select, textarea {
            width: 100%;
            padding: 0.5rem 0.75rem;
            border-radius: 7px;
            border: 1px solid var(--border);
            background: var(--bg-input);
            color: var(--text-primary);
            font-size: 0.86rem;
          }
          input:focus, select:focus, textarea:focus {
            outline: none;
            border-color: var(--accent);
          }

          table { width: 100%; border-collapse: collapse; font-size: 0.84rem; }
          th, td {
            text-align: left;
            padding: 0.6rem 0.7rem;
            border-bottom: 1px solid rgba(255,255,255,0.06);
          }
          th { color: var(--text-secondary); font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.04em; }
          tr:hover td { background: rgba(255,255,255,0.02); }

          .badge {
            display: inline-block;
            padding: 0.18rem 0.55rem;
            border-radius: 999px;
            font-size: 0.72rem;
            font-weight: 700;
            text-transform: uppercase;
          }
          .badge-critica, .badge-critico { background: rgba(239, 68, 68, 0.2); color: #fca5a5; border: 1px solid rgba(239,68,68,0.4); }
          .badge-alta, .badge-alto { background: rgba(245, 158, 11, 0.2); color: #fcd34d; border: 1px solid rgba(245,158,11,0.4); }
          .badge-media, .badge-medio { background: rgba(59, 130, 246, 0.2); color: #93c5fd; border: 1px solid rgba(59,130,246,0.4); }
          .badge-baja, .badge-bajo, .badge-ok { background: rgba(16, 185, 129, 0.2); color: #6ee7b7; border: 1px solid rgba(16,185,129,0.4); }
          .badge-purple { background: rgba(139, 92, 246, 0.2); color: #c4b5fd; border: 1px solid rgba(139,92,246,0.4); }

          .progress-bar {
            width: 100%;
            height: 8px;
            background: var(--bg-input);
            border-radius: 999px;
            overflow: hidden;
            margin-top: 0.3rem;
          }
          .progress-fill { height: 100%; border-radius: 999px; transition: width 0.3s ease; }

          .alert {
            padding: 0.75rem 1rem;
            border-radius: 9px;
            margin-bottom: 1rem;
            font-size: 0.86rem;
            display: flex;
            align-items: center;
            justify-content: space-between;
          }
          .alert-info { background: rgba(59, 130, 246, 0.15); border: 1px solid rgba(59, 130, 246, 0.4); color: #bfdbfe; }
          .alert-error { background: rgba(239, 68, 68, 0.15); border: 1px solid rgba(239, 68, 68, 0.4); color: #fecaca; }
          .alert-success { background: rgba(16, 185, 129, 0.15); border: 1px solid rgba(16, 185, 129, 0.4); color: #a7f3d0; }

          pre.code-output {
            background: #070b14;
            border: 1px solid var(--border);
            border-radius: 8px;
            padding: 0.85rem;
            font-family: 'Consolas', 'Courier New', monospace;
            font-size: 0.8rem;
            color: #a7f3d0;
            overflow-x: auto;
            max-height: 300px;
          }
          .chip {
            display: inline-block;
            background: rgba(255,255,255,0.06);
            border: 1px solid var(--border);
            padding: 0.15rem 0.5rem;
            border-radius: 6px;
            font-size: 0.75rem;
            margin: 0.1rem;
          }
        </style>
      </head>
      <body>
        {@inner_content}
        <script src="/assets/phoenix/phoenix.min.js"></script>
        <script src="/assets/phoenix_live_view/phoenix_live_view.min.js"></script>
        <script>
          let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content");
          let liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, {
            params: {_csrf_token: csrfToken}
          });
          liveSocket.connect();
        </script>
      </body>
    </html>
    """
  end
end
