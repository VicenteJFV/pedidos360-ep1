package cl.duoc.pedidos360.catalog.config;

import cl.duoc.pedidos360.catalog.domain.Producto;
import cl.duoc.pedidos360.catalog.repository.ProductoRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.CommandLineRunner;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.math.BigDecimal;
import java.util.List;

/**
 * Datos de demostracion del catalogo.
 *
 * Corre en cualquier perfil pero solo si la tabla esta vacia, asi que es
 * idempotente: en H2 siembra en cada arranque porque la base es en memoria, y
 * en Oracle siembra una unica vez y nunca vuelve a tocar los datos.
 *
 * Sin esto, al pasar a Oracle el catalogo arrancaria vacio y no se podria
 * crear ningun pedido, porque no habria productos que referenciar.
 */
@Configuration
public class CargaDatosIniciales {

    private static final Logger log = LoggerFactory.getLogger(CargaDatosIniciales.class);

    @Bean
    CommandLineRunner cargarProductos(ProductoRepository repositorio) {
        return args -> {
            if (repositorio.count() > 0) {
                return;
            }
            List<Producto> semilla = List.of(
                    new Producto("SKU-001", "Notebook Lenovo ThinkPad E14",
                            "Core i5, 16 GB RAM, 512 GB SSD", new BigDecimal("749990.00"), 12, "COMPUTACION"),
                    new Producto("SKU-002", "Monitor Dell 24 pulgadas",
                            "Full HD, IPS, 75 Hz", new BigDecimal("129990.00"), 30, "COMPUTACION"),
                    new Producto("SKU-003", "Teclado mecanico Redragon",
                            "Switch rojo, retroiluminado", new BigDecimal("39990.00"), 45, "PERIFERICOS"),
                    new Producto("SKU-004", "Mouse Logitech MX Master 3S",
                            "Inalambrico, sensor 8000 DPI", new BigDecimal("89990.00"), 25, "PERIFERICOS"),
                    new Producto("SKU-005", "Audifonos Sony WH-1000XM4",
                            "Cancelacion activa de ruido", new BigDecimal("249990.00"), 8, "AUDIO"),
                    new Producto("SKU-006", "Silla ergonomica Actiu",
                            "Soporte lumbar regulable", new BigDecimal("199990.00"), 5, "MOBILIARIO"),
                    new Producto("SKU-007", "Webcam Logitech C920",
                            "1080p, microfono estereo", new BigDecimal("54990.00"), 0, "PERIFERICOS")
            );
            repositorio.saveAll(semilla);
            log.info("Catalogo inicializado con {} productos de demostracion", semilla.size());
        };
    }
}
