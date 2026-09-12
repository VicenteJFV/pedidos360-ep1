package cl.duoc.pedidos360.orders.exception;

/**
 * El microservicio de catalogo no respondio (caido, timeout, URL mal configurada).
 * Se traduce a HTTP 503: es un problema de infraestructura, no del cliente.
 */
public class CatalogoNoDisponibleException extends RuntimeException {

    public CatalogoNoDisponibleException(String mensaje) {
        super(mensaje);
    }

    public CatalogoNoDisponibleException(String mensaje, Throwable causa) {
        super(mensaje, causa);
    }
}
