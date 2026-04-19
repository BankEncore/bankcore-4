# Development image for bankcore-4 (Rails 8 + PostgreSQL + libvips for Active Storage).
FROM ruby:3.4.9-bookworm

WORKDIR /app

RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    curl \
    git \
    nano \
    libpq-dev \
    libvips42 \
    && rm -rf /var/lib/apt/lists/*

ENV BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_APP_CONFIG="/usr/local/bundle"

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

EXPOSE 3000

CMD ["bash", "-lc", "rm -f tmp/pids/server.pid && bin/rails server -b 0.0.0.0 -p 3000"]
