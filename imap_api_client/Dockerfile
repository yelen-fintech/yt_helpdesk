# Use the latest official Elixir image available
FROM elixir:latest

# Set the working directory
WORKDIR /app

# Install Hex and Rebar (Elixir's build tools)
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy mix files first for better layer caching
COPY mix.exs mix.lock ./
RUN mix deps.get

# Copy the rest of the application files to the container
COPY . .

# Compile the application
RUN mix compile

# Set the command to start the app in interactive Elixir shell
CMD ["elixir", "--sname", "imap_api_client", "-S", "mix", "run", "--no-halt"]