package cl.duoc.pedidos360.catalog.service;

import cl.duoc.pedidos360.catalog.domain.Producto;
import cl.duoc.pedidos360.catalog.exception.ReglaNegocioException;
import cl.duoc.pedidos360.catalog.repository.ProductoRepository;
import cl.duoc.pedidos360.catalog.web.dto.LineaStockRequest;
import cl.duoc.pedidos360.catalog.web.dto.OperacionStockRequest;
import cl.duoc.pedidos360.catalog.web.dto.OperacionStockResponse;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.NONE)
@Transactional
class StockServiceTest {

    @Autowired
    private StockService stockService;

    @Autowired
    private ProductoRepository repositorio;

    private Producto conStock;
    private Producto casiSinStock;
    private Producto inactivo;

    @BeforeEach
    void prepararDatos() {
        conStock = repositorio.save(new Producto(
                "TEST-CON-STOCK", "Producto con stock", null, new BigDecimal("1000.00"), 50, "TEST"));
        casiSinStock = repositorio.save(new Producto(
                "TEST-POCO-STOCK", "Producto casi agotado", null, new BigDecimal("2000.00"), 2, "TEST"));

        inactivo = repositorio.save(new Producto(
                "TEST-INACTIVO", "Producto dado de baja", null, new BigDecimal("3000.00"), 99, "TEST"));
        inactivo.setActivo(false);
        inactivo = repositorio.save(inactivo);
    }

    @Test
    @DisplayName("Reservar descuenta el stock y devuelve el saldo resultante")
    void reservarDescuentaStock() {
        OperacionStockResponse respuesta = stockService.reservar(new OperacionStockRequest(
                List.of(new LineaStockRequest(conStock.getId(), 5)), "PED-TEST-1"));

        assertThat(respuesta.operacion()).isEqualTo("RESERVA");
        assertThat(respuesta.items()).hasSize(1);
        assertThat(respuesta.items().get(0).stockResultante()).isEqualTo(45);
        assertThat(repositorio.findById(conStock.getId()).orElseThrow().getStock()).isEqualTo(45);
    }

    @Test
    @DisplayName("Si una sola linea no alcanza, NO se descuenta ninguna (atomicidad)")
    void reservaParcialNoDescuentaNada() {
        assertThatThrownBy(() -> stockService.reservar(new OperacionStockRequest(
                List.of(
                        new LineaStockRequest(conStock.getId(), 5),
                        new LineaStockRequest(casiSinStock.getId(), 10)
                ), "PED-TEST-2")))
                .isInstanceOf(ReglaNegocioException.class)
                .hasMessageContaining("No es posible reservar");

        assertThat(repositorio.findById(conStock.getId()).orElseThrow().getStock())
                .as("el producto que si tenia stock no debe haber sido tocado")
                .isEqualTo(50);
        assertThat(repositorio.findById(casiSinStock.getId()).orElseThrow().getStock())
                .isEqualTo(2);
    }

    @Test
    @DisplayName("El error detalla que producto falto y cuanto habia disponible")
    void reservaInsuficienteExplicaElMotivo() {
        assertThatThrownBy(() -> stockService.reservar(new OperacionStockRequest(
                List.of(new LineaStockRequest(casiSinStock.getId(), 10)), "PED-TEST-3")))
                .isInstanceOf(ReglaNegocioException.class)
                .satisfies(ex -> {
                    List<String> detalles = ((ReglaNegocioException) ex).getDetalles();
                    assertThat(detalles).hasSize(1);
                    assertThat(detalles.get(0))
                            .contains("TEST-POCO-STOCK")
                            .contains("solicitado 10")
                            .contains("disponible 2");
                });
    }

    @Test
    @DisplayName("Un producto inactivo no se puede vender aunque tenga stock")
    void productoInactivoNoSeVende() {
        assertThatThrownBy(() -> stockService.reservar(new OperacionStockRequest(
                List.of(new LineaStockRequest(inactivo.getId(), 1)), "PED-TEST-4")))
                .isInstanceOf(ReglaNegocioException.class)
                .satisfies(ex -> assertThat(((ReglaNegocioException) ex).getDetalles().get(0))
                        .contains("inactivo"));

        assertThat(repositorio.findById(inactivo.getId()).orElseThrow().getStock()).isEqualTo(99);
    }

    @Test
    @DisplayName("Las lineas repetidas del mismo producto se suman antes de validar")
    void lineasRepetidasSeConsolidan() {
        // 2 + 1 = 3 > 2 disponibles. Sin consolidar, cada linea pasaria por separado.
        assertThatThrownBy(() -> stockService.reservar(new OperacionStockRequest(
                List.of(
                        new LineaStockRequest(casiSinStock.getId(), 2),
                        new LineaStockRequest(casiSinStock.getId(), 1)
                ), "PED-TEST-5")))
                .isInstanceOf(ReglaNegocioException.class)
                .satisfies(ex -> assertThat(((ReglaNegocioException) ex).getDetalles().get(0))
                        .contains("solicitado 3"));
    }

    @Test
    @DisplayName("Liberar repone el stock al inventario")
    void liberarReponeStock() {
        stockService.reservar(new OperacionStockRequest(
                List.of(new LineaStockRequest(conStock.getId(), 20)), "PED-TEST-6"));
        assertThat(repositorio.findById(conStock.getId()).orElseThrow().getStock()).isEqualTo(30);

        OperacionStockResponse respuesta = stockService.liberar(new OperacionStockRequest(
                List.of(new LineaStockRequest(conStock.getId(), 20)), "PED-TEST-6"));

        assertThat(respuesta.operacion()).isEqualTo("LIBERACION");
        assertThat(repositorio.findById(conStock.getId()).orElseThrow().getStock()).isEqualTo(50);
    }
}
