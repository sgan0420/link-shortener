# frozen_string_literal: true

# Renders a near-empty shell — the actual list is hydrated from the
# visitor's localStorage by app/javascript/controllers/history_list_controller.js.
# No server-side index because the app has no auth; a shared list would
# leak across users.
class HistoryController < ApplicationController
  def show
  end
end
