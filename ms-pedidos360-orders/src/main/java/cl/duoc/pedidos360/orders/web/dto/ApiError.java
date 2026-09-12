package cl.duoc.pedidos360.orders.web.dto;

import com.fasterxml.jackson.annotation.JsonInclude;

import java.time.OffsetDateTime;
import java.util.List;

@JsonInclude(JsonInclude.Include.NON_NULL)
public record ApiError(
        OffsetDateTime timestamp,
        int status,
        String error,
        String mensaje,
        String path,
        List<String> detalles
) {

    public static ApiError de(int status, String error, String mensaje, String path) {
        return new ApiError(OffsetDateTime.now(), status, error, mensaje, path, null);
    }

    public static ApiError de(int status, String error, String mensaje, String path, List<String> detalles) {
        return new ApiError(OffsetDateTime.now(), status, error, mensaje, path,
                detalles == null || detalles.isEmpty() ? null : detalles);
    }
}
