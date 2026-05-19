#!/usr/bin/env bash
# Render build hook — idempotent on every deploy.
set -o errexit
set -o pipefail
set -o nounset

echo "==> Installing gems"
bundle install

echo "==> Precompiling assets (includes tailwindcss:build via tailwindcss-rails)"
bundle exec rails assets:precompile

echo "==> Running migrations"
bundle exec rails db:migrate

echo "==> Build complete"
