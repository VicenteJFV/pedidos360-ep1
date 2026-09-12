package cl.duoc.pedidos360.catalog.web;

import cl.duoc.pedidos360.catalog.service.ProductoService;
import cl.duoc.pedidos360.catalog.web.dto.ProductoRequest;
import cl.duoc.pedidos360.catalog.web.dto.ProductoResponse;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
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
 * Endpoints del catalogo. Sin logica de seguridad OAuth2: la autenticacion se resuelve
 * en AWS API Gateway (JWT Authorizer) y la autorizacion por rol en el BFF.
 */
@RestController
@RequestMapping("/api/catalog")
public class ProductoController {

    private final ProductoService servicio;

    public ProductoController(ProductoService servicio) {
        this.servicio = servicio;
    }

    @GetMapping
    public List<ProductoResponse> listar(
            @RequestParam(required = false) String categoria,
            @RequestParam(defaultValue = "false") boolean soloActivos) {
        return servicio.listar(categoria, soloActivos).stream()
                .map(ProductoResponse::desde)
                .toList();
    }

    @GetMapping("/{id}")
    public ProductoResponse obtener(@PathVariable Long id) {
        return ProductoResponse.desde(servicio.obtenerPorId(id));
    }

    @GetMapping("/sku/{sku}")
    public ProductoResponse obtenerPorSku(@PathVariable String sku) {
        return ProductoResponse.desde(servicio.obtenerPorSku(sku));
    }

    @PostMapping
    public ResponseEntity<ProductoResponse> crear(@Valid @RequestBody ProductoRequest request,
                                                  UriComponentsBuilder uriBuilder) {
        ProductoResponse creado = ProductoResponse.desde(servicio.crear(request));
        URI ubicacion = uriBuilder.path("/api/catalog/{id}").buildAndExpand(creado.id()).toUri();
        return ResponseEntity.created(ubicacion).body(creado);
    }

    @PutMapping("/{id}")
    public ProductoResponse actualizar(@PathVariable Long id, @Valid @RequestBody ProductoRequest request) {
        return ProductoResponse.desde(servicio.actualizar(id, request));
    }

    /**
     * Baja logica: marca el producto como inactivo en vez de borrarlo, porque los
     * pedidos historicos lo referencian y perderiamos trazabilidad.
     * Devuelve 200 con el producto actualizado (no 204) para que el BFF confirme el estado.
     */
    @DeleteMapping("/{id}")
    public ProductoResponse desactivar(@PathVariable Long id) {
        return ProductoResponse.desde(servicio.desactivar(id));
    }
}
