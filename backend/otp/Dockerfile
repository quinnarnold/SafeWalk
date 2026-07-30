# Stage 1: Download data + build graph (runs on GitHub Actions)
FROM eclipse-temurin:21-jre AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl osmium-tool unzip zip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /otp

ARG OTP_VERSION=2.6.0
ARG OTP_SHA256=33a6a7ad66d34ea48fc8e95ca1a3bc1ac986185e9e81d23c42abd4b49c53a8fe
RUN curl -fSL -o otp.jar \
    "https://repo1.maven.org/maven2/org/opentripplanner/otp/${OTP_VERSION}/otp-${OTP_VERSION}-shaded.jar" \
    && echo "${OTP_SHA256}  otp.jar" | sha256sum -c -

COPY build-config.json router-config.json otp-config.json ./

COPY scripts/download-gtfs.sh ./scripts/
RUN chmod +x scripts/download-gtfs.sh && scripts/download-gtfs.sh /otp/gtfs

COPY scripts/download-osm.sh ./scripts/
RUN chmod +x scripts/download-osm.sh && scripts/download-osm.sh /otp/osm
RUN cp /otp/osm/combined.osm.pbf /otp/combined.osm.pbf

RUN java -Xmx8g -jar otp.jar --buildStreet --save .
RUN java -Xmx8g -jar otp.jar --loadStreet --save .

# Stage 2: Slim runtime image
FROM eclipse-temurin:21-jre-alpine

RUN adduser -D -u 1000 otp

WORKDIR /otp

COPY --from=builder /otp/otp.jar .
COPY --from=builder /otp/graph.obj .
COPY --from=builder /otp/router-config.json .
COPY --from=builder /otp/otp-config.json .
COPY --from=builder /otp/scripts ./scripts/

RUN chown -R otp:otp /otp

ENV JAVA_TOOL_OPTIONS="-Xmx3g -XX:+UseG1GC -XX:+UseContainerSupport"

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=3 \
    CMD wget -q -O /dev/null http://localhost:8080/otp/actuators/health || exit 1

USER otp

CMD ["java", "-jar", "otp.jar", "--load", "--serve", "."]
