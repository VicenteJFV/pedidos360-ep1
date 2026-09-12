package cl.duoc.pedidos360.catalog.web.dto;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.math.BigDecimal;

public record ProductoRequest(

        @NotBlank(message = "El SKU es obligatorio")
        @Size(max = 40, message = "El SKU no puede superar 40 caracteres")
        String sku,

        @NotBlank(message = "El nombre es obligatorio")
        @Size(max = 150, message = "El nombre no puede superar 150 caracteres")
        String nombre,

        @Size(max = 500, message = "La descripcion no puede superar 500 caracteres")
        String descripcion,

        @NotNull(message = "El precio es obligatorio")
        @DecimalMin(value = "0.0", inclusive = false, message = "El precio debe ser mayor a cero")
        BigDecimal precio,

        @NotNull(message = "El stock es obligatorio")
        @Min(value = 0, message = "El stock no puede ser negativo")
        Integer stock,

        @Size(max = 60, message = "La categoria no puede superar 60 caracteres")
        String categoria,

        Boolean activo
) {
}
