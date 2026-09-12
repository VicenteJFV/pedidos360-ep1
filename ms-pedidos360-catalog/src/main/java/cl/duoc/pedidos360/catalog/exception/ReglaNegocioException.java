package cl.duoc.pedidos360.catalog.exception;

import java.util.Collections;
import java.util.List;

/** Se traduce a HTTP 409 (conflicto con el estado actual del recurso). */
public class ReglaNegocioException extends RuntimeException {

    private final List<String> detalles;

    public ReglaNegocioException(String mensaje) {
        this(mensaje, Collections.emptyList());
    }

    public ReglaNegocioException(String mensaje, List<String> detalles) {
        super(mensaje);
        this.detalles = detalles == null ? Collections.emptyList() : List.copyOf(detalles);
    }

    public List<String> getDetalles() {
        return detalles;
    }
}
