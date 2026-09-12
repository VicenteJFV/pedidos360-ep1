package cl.duoc.pedidos360.orders.web.dto;

import jakarta.validation.constraints.Size;

public record CancelarPedidoRequest(

        @Size(max = 500, message = "El motivo no puede superar 500 caracteres")
        String motivo
) {
}
