package cl.duoc.pedidos360.catalog.web;

import cl.duoc.pedidos360.catalog.exception.RecursoNoEncontradoException;
import cl.duoc.pedidos360.catalog.exception.ReglaNegocioException;
import cl.duoc.pedidos360.catalog.web.dto.ApiError;
import jakarta.servlet.http.HttpServletRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.OptimisticLockingFailureException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.util.List;

@RestControllerAdvice
public class ManejadorGlobalErrores {

    private static final Logger log = LoggerFactory.getLogger(ManejadorGlobalErrores.class);

    @ExceptionHandler(RecursoNoEncontradoException.class)
    public ResponseEntity<ApiError> noEncontrado(RecursoNoEncontradoException ex, HttpServletRequest req) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND)
                .body(ApiError.de(404, "Not Found", ex.getMessage(), req.getRequestURI()));
    }

    @ExceptionHandler(ReglaNegocioException.class)
    public ResponseEntity<ApiError> reglaNegocio(ReglaNegocioException ex, HttpServletRequest req) {
        return ResponseEntity.status(HttpStatus.CONFLICT)
                .body(ApiError.de(409, "Conflict", ex.getMessage(), req.getRequestURI(),
                        ex.getDetalles().isEmpty() ? null : ex.getDetalles()));
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ApiError> validacion(MethodArgumentNotValidException ex, HttpServletRequest req) {
        List<String> detalles = ex.getBindingResult().getFieldErrors().stream()
                .map(e -> e.getField() + ": " + e.getDefaultMessage())
                .toList();
        return ResponseEntity.badRequest()
                .body(ApiError.de(400, "Bad Request", "Datos de entrada invalidos",
                        req.getRequestURI(), detalles));
    }

    /** Dos reservas simultaneas sobre el mismo producto: el cliente puede reintentar. */
    @ExceptionHandler(OptimisticLockingFailureException.class)
    public ResponseEntity<ApiError> conflictoConcurrencia(OptimisticLockingFailureException ex,
                                                          HttpServletRequest req) {
        log.warn("Conflicto de concurrencia en {}: {}", req.getRequestURI(), ex.getMessage());
        return ResponseEntity.status(HttpStatus.CONFLICT)
                .body(ApiError.de(409, "Conflict",
                        "El producto fue modificado por otra operacion. Reintente.", req.getRequestURI()));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ApiError> errorInterno(Exception ex, HttpServletRequest req) {
        log.error("Error no controlado en {}", req.getRequestURI(), ex);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(ApiError.de(500, "Internal Server Error",
                        "Error interno del microservicio de catalogo", req.getRequestURI()));
    }
}
