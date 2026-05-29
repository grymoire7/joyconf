defmodule SpeechwaveWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use SpeechwaveWeb, :html

  embed_templates "page_html/*"

  def public_footer(assigns) do
    ~H"""
    <footer class="py-12 px-6 bg-canvas-dark">
      <div class="max-w-6xl mx-auto flex flex-col sm:flex-row items-center justify-between gap-6 text-sm">
        <a href="/" class="flex items-center gap-2 text-on-dark font-medium">
          <span>🎤</span> Speechwave
        </a>
        <div class="flex gap-6 text-on-dark-muted">
          <a href={~p"/pricing"} class="hover:text-on-dark transition-colors">Pricing</a>
          <a href={~p"/terms"} class="hover:text-on-dark transition-colors">Terms</a>
          <a href={~p"/privacy"} class="hover:text-on-dark transition-colors">Privacy</a>
        </div>
        <span class="text-on-dark-muted">© {Date.utc_today().year} Speechwave</span>
      </div>
    </footer>
    """
  end
end
