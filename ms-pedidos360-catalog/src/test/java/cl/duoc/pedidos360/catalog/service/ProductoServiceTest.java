package cl.duoc.pedidos360.catalog.service;

import cl.duoc.pedidos360.catalog.domain.Producto;
import cl.duoc.pedidos360.catalog.exception.RecursoNoEncontradoException;
import cl.duoc.pedidos360.catalog.exception.ReglaNegocioException;
import cl.duoc.pedidos360.catalog.web.dto.ProductoRequest;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.NONE)
@Transactional
class ProductoServiceTest {

    @Autowired
    private ProductoService servicio;

    private ProductoRequest pedirCreacion(String sku) {
        return new ProductoRequest(sku, "Producto " + sku, "Descripcion",
                new BigDecimal("9990.00"), 10, "TEST", true);
    }

    @Test
    @DisplayName("Crear producto persiste y asigna id")
    void crearProducto() {
        Producto creado = servicio.crear(pedirCreacion("CRUD-001"));

        assertThat(creado.getId()).isNotNull();
        assertThat(creado.getSku()).isEqualTo("CRUD-001");
        assertThat(creado.getActivo()).isTrue();
        assertThat(creado.getFechaCreacion()).isNotNull();
    }

    @Test
    @DisplayName("No se admiten dos productos con el mismo SKU")
    void skuDuplicadoEsRechazado() {
        servicio.crear(pedirCreacion("CRUD-002"));

        assertThatThrownBy(() -> servicio.crear(pedirCreacion("CRUD-002")))
                .isInstanceOf(ReglaNegocioException.class)
                .hasMessageContaining("CRUD-002");
    }

    @Test
    @DisplayName("Actualizar cambia los datos y refresca la fecha")
    void actualizarProducto() {
        Producto creado = servicio.crear(pedirCreacion("CRUD-003"));

        Producto actualizado = servicio.actualizar(creado.getId(), new ProductoRequest(
                "CRUD-003", "Nombre nuevo", "Otra descripcion",
                new BigDecimal("12345.00"), 7, "OTRA", true));

        assertThat(actualizado.getNombre()).isEqualTo("Nombre nuevo");
        assertThat(actualizado.getPrecio()).isEqualByComparingTo("12345.00");
        assertThat(actualizado.getStock()).isEqualTo(7);
        assertThat(actualizado.getFechaActualizacion()).isNotNull();
    }

    @Test
    @DisplayName("Desactivar es baja logica: el producto sigue existiendo")
    void desactivarEsBajaLogica() {
        Producto creado = servicio.crear(pedirCreacion("CRUD-004"));

        Producto desactivado = servicio.desactivar(creado.getId());

        assertThat(desactivado.getActivo()).isFalse();
        assertThat(servicio.obtenerPorId(creado.getId())).isNotNull();
    }

    @Test
    @DisplayName("Desactivar dos veces es un conflicto")
    void desactivarDosVecesFalla() {
        Producto creado = servicio.crear(pedirCreacion("CRUD-005"));
        servicio.desactivar(creado.getId());

        assertThatThrownBy(() -> servicio.desactivar(creado.getId()))
                .isInstanceOf(ReglaNegocioException.class)
                .hasMessageContaining("ya se encuentra inactivo");
    }

    @Test
    @DisplayName("Pedir un producto inexistente devuelve 404 de dominio")
    void productoInexistente() {
        assertThatThrownBy(() -> servicio.obtenerPorId(999999L))
                .isInstanceOf(RecursoNoEncontradoException.class);
    }

    @Test
    @DisplayName("El filtro soloActivos excluye los dados de baja")
    void filtroSoloActivos() {
        Producto activo = servicio.crear(pedirCreacion("CRUD-006"));
        Producto baja = servicio.crear(pedirCreacion("CRUD-007"));
        servicio.desactivar(baja.getId());

        assertThat(servicio.listar("TEST", true))
                .extracting(Producto::getId)
                .contains(activo.getId())
                .doesNotContain(baja.getId());

        assertThat(servicio.listar("TEST", false))
                .extracting(Producto::getId)
                .contains(activo.getId(), baja.getId());
    }
}
