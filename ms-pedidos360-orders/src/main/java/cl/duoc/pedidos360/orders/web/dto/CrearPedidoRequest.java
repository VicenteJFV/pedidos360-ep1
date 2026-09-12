package cl.duoc.pedidos360.orders.web.dto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.Size;

import java.util.List;

public record CrearPedidoRequest(

        /**
         * Identidad del cliente. El BFF la toma del claim 'preferred_username' del JWT
         * y la inyecta aqui: el microservicio no confia en lo que mande el navegador.
         */
        @NotBlank(message = "clienteEmail es obligatorio")
        @Email(message = "clienteEmail debe ser un correo valido")
        @Size(max = 180)
        String clienteEmail,

        @Size(max = 150)
        String clienteNombre,

        @Size(max = 300)
        String direccionEntrega,

        @Size(max = 500)
        String observacion,

        @NotEmpty(message = "El pedido debe tener al menos un item")
        List<@Valid LineaPedidoRequest> items
) {
}
