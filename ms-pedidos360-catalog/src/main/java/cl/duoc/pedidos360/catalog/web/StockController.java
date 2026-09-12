package cl.duoc.pedidos360.catalog.web;

import cl.duoc.pedidos360.catalog.service.StockService;
import cl.duoc.pedidos360.catalog.web.dto.OperacionStockRequest;
import cl.duoc.pedidos360.catalog.web.dto.OperacionStockResponse;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Endpoints internos de stock. Los consume el microservicio de pedidos, no el BFF
 * ni el frontend. Quedan fuera de las rutas publicadas en AWS API Gateway.
 */
@RestController
@RequestMapping("/api/catalog/stock")
public class StockController {

    private final StockService servicio;

    public StockController(StockService servicio) {
        this.servicio = servicio;
    }

    /** Descuenta stock de forma atomica. Devuelve 409 si alguna linea no alcanza. */
    @PostMapping("/reservar")
    public OperacionStockResponse reservar(@Valid @RequestBody OperacionStockRequest request) {
        return servicio.reservar(request);
    }

    /** Repone stock (cancelacion de un pedido que ya habia reservado). */
    @PostMapping("/liberar")
    public OperacionStockResponse liberar(@Valid @RequestBody OperacionStockRequest request) {
        return servicio.liberar(request);
    }
}
