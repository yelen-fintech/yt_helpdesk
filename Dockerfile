FROM elixir:latest

FROM elixir:latest

# Install required libraries and manually add the repository
RUN apt-get update && apt-get install -y \
    gcc g++ \
    libstdc++6 software-properties-common gnupg && \
    echo "deb http://ppa.launchpad.net/ubuntu-toolchain-r/test/ubuntu focal main" > /etc/apt/sources.list.d/ubuntu-toolchain-r.list && \
    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 1E9377A2BA9EF27F && \
    apt-get update && \
    apt-get install -y libstdc++6 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*


WORKDIR /app

# Copy and setup application
COPY mix.exs mix.lock ./
RUN mix local.hex --force && mix local.rebar --force && mix deps.get

COPY . .
RUN mix compile


# Set the command to start the app in interactive Elixir shell
CMD ["elixir", "--sname", "imap_api_client", "-S", "mix", "run", "--no-halt"]