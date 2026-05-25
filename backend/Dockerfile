# Original working Dockerfile - Just DAB with Microsoft SDK
FROM mcr.microsoft.com/dotnet/sdk:8.0
WORKDIR /App

# Install DAB CLI
RUN dotnet tool install --global Microsoft.DataApiBuilder --version 1.2.10
ENV PATH="${PATH}:/root/.dotnet/tools"

# Copy configuration files
COPY dab-config.json /App/dab-config.json
COPY .env /App/.env

# Bind to port 5000 - same as working v20.7.53 (ASPNETCORE_URLS overrides base image 8080)
ENV ASPNETCORE_URLS=http://+:5000

# Expose default port
EXPOSE 5000

# Start DAB
CMD ["dab", "start", "--config", "dab-config.json", "--no-https-redirect"]
