package cl.duoc.pedidos360.orders.client.dto;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

import java.util.List;

/** Cuerpo de error que devuelve el catalogo, para propagar el motivo real al BFF. */
@JsonIgnoreProperties(ignoreUnknown = true)
public record ErrorCatalogoDto(
        Integer status,
        String error,
        String mensaje,
        List<String> detalles
) {
}
