package cl.duoc.pedidos360.orders;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Microservicio Principal de Pedidos - Pedidos360 (EP1 DSY1107).
 *
 * Escucha por defecto en 127.0.0.1:8081 y consume al microservicio de catalogo
 * en 127.0.0.1:8082. La validacion del JWT ocurre aguas arriba (API Gateway + BFF).
 */
@SpringBootApplication
public class OrdersApplication {

    public static void main(String[] args) {
        SpringApplication.run(OrdersApplication.class, args);
    }
}
