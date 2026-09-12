package cl.duoc.pedidos360.orders.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.client.RestClient;

import java.time.Duration;

/**
 * Cliente HTTP hacia el microservicio de catalogo.
 *
 * Los timeouts son explicitos a proposito: sin ellos, si el catalogo se cuelga,
 * el hilo de pedidos queda bloqueado indefinidamente y termina cayendo todo el
 * microservicio principal por agotamiento del pool de Tomcat.
 */
@Configuration
@ConfigurationProperties(prefix = "catalog")
public class RestClientConfig {

    private String baseUrl = "http://localhost:8082";
    private Duration connectTimeout = Duration.ofSeconds(5);
    private Duration readTimeout = Duration.ofSeconds(10);

    @Bean
    public RestClient catalogRestClient() {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(connectTimeout);
        factory.setReadTimeout(readTimeout);

        return RestClient.builder()
                .baseUrl(baseUrl)
                .requestFactory(factory)
                .build();
    }

    public String getBaseUrl() {
        return baseUrl;
    }

    public void setBaseUrl(String baseUrl) {
        this.baseUrl = baseUrl;
    }

    public Duration getConnectTimeout() {
        return connectTimeout;
    }

    public void setConnectTimeout(Duration connectTimeout) {
        this.connectTimeout = connectTimeout;
    }

    public Duration getReadTimeout() {
        return readTimeout;
    }

    public void setReadTimeout(Duration readTimeout) {
        this.readTimeout = readTimeout;
    }
}
