package cl.duoc.pedidos360.catalog.web.dto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotEmpty;

import java.util.List;

public record OperacionStockRequest(

        @NotEmpty(message = "Debe enviar al menos una linea de stock")
        List<@Valid LineaStockRequest> items,

        /** Traza opcional: codigo del pedido que origina el movimiento. */
        String referencia
) {
}
