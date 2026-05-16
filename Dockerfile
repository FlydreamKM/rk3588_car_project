FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    unzip \
    xz-utils \
    zip \
    libglu1-mesa \
    openjdk-17-jdk \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Set environment variables
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ENV ANDROID_HOME=/opt/android-sdk
ENV PATH="/opt/flutter/bin:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}"

# Install Flutter
RUN git clone -b stable --depth 1 https://github.com/flutter/flutter.git /opt/flutter

# Install Android SDK command line tools
RUN mkdir -p ${ANDROID_HOME}/cmdline-tools \
    && cd ${ANDROID_HOME}/cmdline-tools \
    && wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip \
    && unzip -q commandlinetools-linux-11076708_latest.zip \
    && mv cmdline-tools latest \
    && rm commandlinetools-linux-11076708_latest.zip

# Accept licenses and install SDK components
RUN yes | sdkmanager --licenses \
    && sdkmanager "platforms;android-34" \
    && sdkmanager "build-tools;34.0.0" \
    && sdkmanager "platform-tools"

# Pre-download Flutter dependencies
RUN flutter config --no-analytics \
    && flutter precache

# Build entrypoint
WORKDIR /project
COPY . /project/

RUN flutter pub get

CMD ["flutter", "build", "apk", "--release"]
