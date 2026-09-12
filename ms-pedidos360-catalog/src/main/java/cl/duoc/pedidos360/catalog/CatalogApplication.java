package cl.duoc.pedidos360.catalog;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * Microservicio de Catalogo - Pedidos360 (EP1 DSY1107).
 *
 * Escucha por defecto en 127.0.0.1:8082. No expone seguridad OAuth2: la validacion
 * del JWT ocurre aguas arriba (AWS API Gateway + BFF). El aislamiento de red
 * (bind a loopback + Security Group cerrado) es lo que impide el acceso directo.
 */
@SpringBootApplication
public class CatalogApplication {

    public static void main(String[] args) {
        SpringApplication.run(CatalogApplication.class, args);
    }
}
