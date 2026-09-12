package cl.duoc.pedidos360.orders.client.dto;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

import java.math.BigDecimal;

/** Vista parcial del producto tal como lo expone el microservicio de catalogo. */
@JsonIgnoreProperties(ignoreUnknown = true)
public record ProductoCatalogoDto(
        Long id,
        String sku,
        String nombre,
        BigDecimal precio,
        Integer stock,
        String categoria,
        Boolean activo
) {
}
