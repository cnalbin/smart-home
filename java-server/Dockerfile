FROM eclipse-temurin:17-jre
WORKDIR /app
COPY target/sensor-server-1.0.0.jar app.jar
USER 10001:10001
EXPOSE 8080
ENTRYPOINT ["java", "-Duser.timezone=Asia/Shanghai", "-jar", "/app/app.jar"]
