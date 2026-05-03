defmodule SpeechwaveWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use SpeechwaveWeb, :html

  embed_templates "page_html/*"

  attr :current_scope, :map, default: nil

  def public_nav(assigns) do
    ~H"""
    <header class="fixed top-0 left-0 right-0 z-50 bg-white/80 backdrop-blur-md border-b border-hairline">
      <div class="max-w-6xl mx-auto px-6 h-16 flex items-center justify-between gap-4">
        <a
          href="/"
          class="flex items-center gap-2 text-ink font-semibold text-[15px] tracking-tight shrink-0"
        >
          <span class="text-xl leading-none">🎤</span> Speechwave
        </a>
        <nav class="flex items-center gap-1">
          <a href={~p"/pricing"} class="px-3 py-2 text-sm text-steel hover:text-ink transition-colors">
            Pricing
          </a>
          <%= if @current_scope do %>
            <a
              href={~p"/dashboard"}
              class="px-3 py-2 text-sm text-steel hover:text-ink transition-colors"
            >
              Dashboard
            </a>
            <a
              href={~p"/users/settings"}
              class="hidden sm:block px-3 py-2 text-sm text-steel hover:text-ink transition-colors"
            >
              Settings
            </a>
            <span class="hidden md:inline text-xs text-muted px-2 truncate max-w-40">
              {@current_scope.user.email}
            </span>
            <.link
              href={~p"/users/log-out"}
              method="delete"
              class="ml-2 px-4 py-2 text-sm font-medium text-ink border border-hairline rounded-full hover:bg-surface transition-colors whitespace-nowrap"
            >
              Log out
            </.link>
          <% else %>
            <a
              href={~p"/users/log-in"}
              class="hidden sm:block px-3 py-2 text-sm text-steel hover:text-ink transition-colors"
            >
              Log in
            </a>
            <a
              href={~p"/users/register"}
              class="ml-2 px-4 py-2 text-sm font-medium text-canvas bg-ink rounded-full hover:bg-charcoal transition-colors whitespace-nowrap"
            >
              <span class="hidden sm:inline">Get started free</span>
              <span class="sm:hidden">Sign up</span>
            </a>
          <% end %>
        </nav>
      </div>
    </header>
    """
  end

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
