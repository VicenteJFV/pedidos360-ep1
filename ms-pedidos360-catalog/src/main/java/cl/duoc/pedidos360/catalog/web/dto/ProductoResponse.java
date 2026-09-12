package cl.duoc.pedidos360.catalog.web.dto;

import cl.duoc.pedidos360.catalog.domain.Producto;

import java.math.BigDecimal;
import java.time.LocalDateTime;

public record ProductoResponse(
        Long id,
        String sku,
        String nombre,
        String descripcion,
        BigDecimal precio,
        Integer stock,
        String categoria,
        Boolean activo,
        LocalDateTime fechaCreacion,
        LocalDateTime fechaActualizacion
) {

    public static ProductoResponse desde(Producto p) {
        return new ProductoResponse(
                p.getId(),
                p.getSku(),
                p.getNombre(),
                p.getDescripcion(),
                p.getPrecio(),
                p.getStock(),
                p.getCategoria(),
                p.getActivo(),
                p.getFechaCreacion(),
                p.getFechaActualizacion()
        );
    }
}
