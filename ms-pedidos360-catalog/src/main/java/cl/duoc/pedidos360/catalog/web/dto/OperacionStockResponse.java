package cl.duoc.pedidos360.catalog.web.dto;

import java.util.List;

public record OperacionStockResponse(
        String operacion,
        String referencia,
        List<LineaStockResultado> items
) {

    public record LineaStockResultado(
            Long productoId,
            String sku,
            Integer cantidadAplicada,
            Integer stockResultante
    ) {
    }
}
