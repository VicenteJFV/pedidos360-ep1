package cl.duoc.pedidos360.catalog.service;

import cl.duoc.pedidos360.catalog.domain.Producto;
import cl.duoc.pedidos360.catalog.exception.RecursoNoEncontradoException;
import cl.duoc.pedidos360.catalog.exception.ReglaNegocioException;
import cl.duoc.pedidos360.catalog.repository.ProductoRepository;
import cl.duoc.pedidos360.catalog.web.dto.ProductoRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

import java.util.List;

@Service
public class ProductoService {

    private final ProductoRepository repositorio;

    public ProductoService(ProductoRepository repositorio) {
        this.repositorio = repositorio;
    }

    @Transactional(readOnly = true)
    public List<Producto> listar(String categoria, boolean soloActivos) {
        if (StringUtils.hasText(categoria)) {
            List<Producto> porCategoria = repositorio.findByCategoriaIgnoreCaseOrderByNombreAsc(categoria);
            if (!soloActivos) {
                return porCategoria;
            }
            return porCategoria.stream()
                    .filter(p -> Boolean.TRUE.equals(p.getActivo()))
                    .toList();
        }
        return soloActivos ? repositorio.findByActivoTrueOrderByNombreAsc() : repositorio.findAll();
    }

    @Transactional(readOnly = true)
    public Producto obtenerPorId(Long id) {
        return repositorio.findById(id)
                .orElseThrow(() -> new RecursoNoEncontradoException("No existe el producto con id " + id));
    }

    @Transactional(readOnly = true)
    public Producto obtenerPorSku(String sku) {
        return repositorio.findBySku(sku)
                .orElseThrow(() -> new RecursoNoEncontradoException("No existe el producto con SKU " + sku));
    }

    @Transactional
    public Producto crear(ProductoRequest request) {
        if (repositorio.existsBySku(request.sku())) {
            throw new ReglaNegocioException("Ya existe un producto con el SKU " + request.sku());
        }
        Producto producto = new Producto(
                request.sku(),
                request.nombre(),
                request.descripcion(),
                request.precio(),
                request.stock(),
                request.categoria()
        );
        if (request.activo() != null) {
            producto.setActivo(request.activo());
        }
        return repositorio.save(producto);
    }

    @Transactional
    public Producto actualizar(Long id, ProductoRequest request) {
        Producto producto = obtenerPorId(id);

        boolean cambioSku = !producto.getSku().equalsIgnoreCase(request.sku());
        if (cambioSku && repositorio.existsBySku(request.sku())) {
            throw new ReglaNegocioException("Ya existe otro producto con el SKU " + request.sku());
        }

        producto.setSku(request.sku());
        producto.setNombre(request.nombre());
        producto.setDescripcion(request.descripcion());
        producto.setPrecio(request.precio());
        producto.setStock(request.stock());
        producto.setCategoria(request.categoria());
        if (request.activo() != null) {
            producto.setActivo(request.activo());
        }
        return repositorio.save(producto);
    }

    /**
     * Baja logica. No se borra fisicamente porque los pedidos historicos referencian
     * el producto y perderiamos la trazabilidad.
     */
    @Transactional
    public Producto desactivar(Long id) {
        Producto producto = obtenerPorId(id);
        if (Boolean.FALSE.equals(producto.getActivo())) {
            throw new ReglaNegocioException("El producto " + producto.getSku() + " ya se encuentra inactivo");
        }
        producto.setActivo(Boolean.FALSE);
        return repositorio.save(producto);
    }
}
