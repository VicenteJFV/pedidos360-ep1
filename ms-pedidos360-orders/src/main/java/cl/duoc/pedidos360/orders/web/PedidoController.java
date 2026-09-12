package cl.duoc.pedidos360.orders.web;

import cl.duoc.pedidos360.orders.domain.EstadoPedido;
import cl.duoc.pedidos360.orders.service.PedidoService;
import cl.duoc.pedidos360.orders.web.dto.CancelarPedidoRequest;
import cl.duoc.pedidos360.orders.web.dto.CrearPedidoRequest;
import cl.duoc.pedidos360.orders.web.dto.PedidoResponse;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.util.UriComponentsBuilder;

import java.net.URI;
import java.util.List;

/**
 * Endpoints de pedidos consumidos por el BFF.
 *
 * Las rutas coinciden 1:1 con las publicadas en AWS API Gateway para que el BFF
 * sea un passthrough con autorizacion por rol y no tenga que traducir rutas.
 */
@RestController
@RequestMapping("/api/orders")
public class PedidoController {

    private final PedidoService servicio;

    public PedidoController(PedidoService servicio) {
        this.servicio = servicio;
    }

    /**
     * Para el rol Cliente, el BFF debe pasar clienteEmail con el correo del token,
     * de modo que un cliente nunca vea pedidos de otro.
     */
    @GetMapping
    public List<PedidoResponse> listar(
            @RequestParam(required = false) String clienteEmail,
            @RequestParam(required = false) EstadoPedido estado) {
        return servicio.listar(clienteEmail, estado);
    }

    @GetMapping("/{id}")
    public PedidoResponse obtener(@PathVariable Long id) {
        return servicio.obtener(id);
    }

    @GetMapping("/codigo/{codigo}")
    public PedidoResponse obtenerPorCodigo(@PathVariable String codigo) {
        return servicio.obtenerPorCodigo(codigo);
    }

    @PostMapping
    public ResponseEntity<PedidoResponse> crear(@Valid @RequestBody CrearPedidoRequest request,
                                                UriComponentsBuilder uriBuilder) {
        PedidoResponse creado = servicio.crear(request);
        URI ubicacion = uriBuilder.path("/api/orders/{id}").buildAndExpand(creado.id()).toUri();
        return ResponseEntity.created(ubicacion).body(creado);
    }

    /** Descuenta stock en el catalogo. Rol esperado: Admin (lo valida el BFF). */
    @PutMapping("/{id}/accept")
    public PedidoResponse aceptar(@PathVariable Long id) {
        return servicio.aceptar(id);
    }

    @PutMapping("/{id}/prepare")
    public PedidoResponse preparar(@PathVariable Long id) {
        return servicio.preparar(id);
    }

    @PutMapping("/{id}/dispatch")
    public PedidoResponse despachar(@PathVariable Long id) {
        return servicio.despachar(id);
    }

    @PutMapping("/{id}/deliver")
    public PedidoResponse entregar(@PathVariable Long id) {
        return servicio.entregar(id);
    }

    /** El cuerpo es opcional: permite registrar el motivo de la cancelacion. */
    @PutMapping("/{id}/cancel")
    public PedidoResponse cancelar(@PathVariable Long id,
                                   @Valid @RequestBody(required = false) CancelarPedidoRequest request) {
        return servicio.cancelar(id, request == null ? null : request.motivo());
    }
}
