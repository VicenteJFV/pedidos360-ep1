package cl.duoc.pedidos360.orders.domain;

import java.util.Collections;
import java.util.EnumMap;
import java.util.EnumSet;
import java.util.Map;
import java.util.Set;

/**
 * Maquina de estados del pedido.
 *
 *   CREADO ─┬─> ACEPTADO ─┬─> EN_PREPARACION ──> DESPACHADO ──> ENTREGADO
 *           │             │
 *           └─> CANCELADO <┘
 *
 * Las transiciones validas viven aqui y no dispersas en los servicios: es la
 * unica fuente de verdad y hace imposible, por ejemplo, despachar sin aceptar.
 */
public enum EstadoPedido {

    CREADO,
    ACEPTADO,
    EN_PREPARACION,
    DESPACHADO,
    ENTREGADO,
    CANCELADO;

    private static final Map<EstadoPedido, Set<EstadoPedido>> TRANSICIONES =
            new EnumMap<>(EstadoPedido.class);

    static {
        TRANSICIONES.put(CREADO, EnumSet.of(ACEPTADO, CANCELADO));
        TRANSICIONES.put(ACEPTADO, EnumSet.of(EN_PREPARACION, CANCELADO));
        TRANSICIONES.put(EN_PREPARACION, EnumSet.of(DESPACHADO));
        TRANSICIONES.put(DESPACHADO, EnumSet.of(ENTREGADO));
        TRANSICIONES.put(ENTREGADO, EnumSet.noneOf(EstadoPedido.class));
        TRANSICIONES.put(CANCELADO, EnumSet.noneOf(EstadoPedido.class));
    }

    public boolean puedeTransicionarA(EstadoPedido destino) {
        return transicionesPermitidas().contains(destino);
    }

    public Set<EstadoPedido> transicionesPermitidas() {
        return Collections.unmodifiableSet(
                TRANSICIONES.getOrDefault(this, EnumSet.noneOf(EstadoPedido.class)));
    }

    /** Estado terminal: ya no admite cambios. */
    public boolean esFinal() {
        return transicionesPermitidas().isEmpty();
    }

    /** Indica si en este estado el stock ya fue descontado del catalogo. */
    public boolean tieneStockReservado() {
        return this == ACEPTADO || this == EN_PREPARACION || this == DESPACHADO || this == ENTREGADO;
    }
}
