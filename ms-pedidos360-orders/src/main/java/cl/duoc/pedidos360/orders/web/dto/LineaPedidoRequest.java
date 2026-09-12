package cl.duoc.pedidos360.orders.web.dto;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;

public record LineaPedidoRequest(

        @NotNull(message = "productoId es obligatorio")
        Long productoId,

        @NotNull(message = "cantidad es obligatoria")
        @Min(value = 1, message = "La cantidad debe ser al menos 1")
        @Max(value = 999, message = "La cantidad maxima por linea es 999")
        Integer cantidad
) {
}
