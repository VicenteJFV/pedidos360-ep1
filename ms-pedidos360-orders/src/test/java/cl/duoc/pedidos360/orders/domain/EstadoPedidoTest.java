package cl.duoc.pedidos360.orders.domain;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.junit.jupiter.params.provider.EnumSource;

import static org.assertj.core.api.Assertions.assertThat;

@DisplayName("Maquina de estados del pedido")
class EstadoPedidoTest {

    @ParameterizedTest(name = "{0} -> {1} es valido")
    @CsvSource({
            "CREADO,         ACEPTADO",
            "CREADO,         CANCELADO",
            "ACEPTADO,       EN_PREPARACION",
            "ACEPTADO,       CANCELADO",
            "EN_PREPARACION, DESPACHADO",
            "DESPACHADO,     ENTREGADO"
    })
    void transicionesValidas(EstadoPedido origen, EstadoPedido destino) {
        assertThat(origen.puedeTransicionarA(destino)).isTrue();
    }

    @ParameterizedTest(name = "{0} -> {1} debe bloquearse")
    @CsvSource({
            // La regla del enunciado: no se puede despachar sin haber aceptado.
            "CREADO,         DESPACHADO",
            "CREADO,         EN_PREPARACION",
            "CREADO,         ENTREGADO",
            "ACEPTADO,       DESPACHADO",
            "ACEPTADO,       ENTREGADO",
            "EN_PREPARACION, ENTREGADO",
            "EN_PREPARACION, CANCELADO",
            "DESPACHADO,     CANCELADO",
            // No se retrocede
            "ACEPTADO,       CREADO",
            "DESPACHADO,     EN_PREPARACION",
            // Estados finales
            "ENTREGADO,      CANCELADO",
            "CANCELADO,      ACEPTADO"
    })
    void transicionesInvalidas(EstadoPedido origen, EstadoPedido destino) {
        assertThat(origen.puedeTransicionarA(destino)).isFalse();
    }

    @Test
    @DisplayName("ENTREGADO y CANCELADO son estados finales")
    void estadosFinales() {
        assertThat(EstadoPedido.ENTREGADO.esFinal()).isTrue();
        assertThat(EstadoPedido.CANCELADO.esFinal()).isTrue();
        assertThat(EstadoPedido.CREADO.esFinal()).isFalse();
        assertThat(EstadoPedido.DESPACHADO.esFinal()).isFalse();
    }

    @Test
    @DisplayName("Ningun estado permite transicionar a si mismo")
    void sinAutotransiciones() {
        for (EstadoPedido estado : EstadoPedido.values()) {
            assertThat(estado.puedeTransicionarA(estado))
                    .as("%s no deberia permitir transicionar a si mismo", estado)
                    .isFalse();
        }
    }

    @Test
    @DisplayName("El stock esta reservado desde ACEPTADO en adelante, salvo si se cancelo")
    void estadosConStockReservado() {
        assertThat(EstadoPedido.CREADO.tieneStockReservado()).isFalse();
        assertThat(EstadoPedido.CANCELADO.tieneStockReservado()).isFalse();
        assertThat(EstadoPedido.ACEPTADO.tieneStockReservado()).isTrue();
        assertThat(EstadoPedido.EN_PREPARACION.tieneStockReservado()).isTrue();
        assertThat(EstadoPedido.DESPACHADO.tieneStockReservado()).isTrue();
        assertThat(EstadoPedido.ENTREGADO.tieneStockReservado()).isTrue();
    }

    @ParameterizedTest
    @EnumSource(EstadoPedido.class)
    void todoEstadoTieneSuConjuntoDeTransicionesDefinido(EstadoPedido estado) {
        assertThat(estado.transicionesPermitidas()).isNotNull();
    }
}
