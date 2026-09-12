package cl.duoc.pedidos360.orders.exception;

import cl.duoc.pedidos360.orders.domain.EstadoPedido;

import java.util.List;

/**
 * Transicion de estado no permitida por la maquina de estados. Se traduce a HTTP 409
 * e incluye en el detalle cuales serian las transiciones validas desde el estado actual.
 */
public class TransicionInvalidaException extends ReglaNegocioException {

    public TransicionInvalidaException(String codigoPedido, EstadoPedido origen, EstadoPedido destino) {
        super(
                "El pedido " + codigoPedido + " no puede pasar de " + origen + " a " + destino,
                List.of(origen.esFinal()
                        ? origen + " es un estado final: el pedido ya no admite cambios"
                        : "Transiciones validas desde " + origen + ": " + origen.transicionesPermitidas())
        );
    }
}
