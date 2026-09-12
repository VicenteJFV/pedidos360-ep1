package cl.duoc.pedidos360.catalog.service;

import cl.duoc.pedidos360.catalog.domain.Producto;
import cl.duoc.pedidos360.catalog.exception.RecursoNoEncontradoException;
import cl.duoc.pedidos360.catalog.exception.ReglaNegocioException;
import cl.duoc.pedidos360.catalog.repository.ProductoRepository;
import cl.duoc.pedidos360.catalog.web.dto.LineaStockRequest;
import cl.duoc.pedidos360.catalog.web.dto.OperacionStockRequest;
import cl.duoc.pedidos360.catalog.web.dto.OperacionStockResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Movimientos de stock solicitados por el microservicio de pedidos.
 *
 * Regla clave: la operacion es atomica (todo o nada). Si una sola linea no tiene
 * stock suficiente, no se descuenta ninguna y se devuelve 409 con el detalle
 * completo, para que el pedido no quede aceptado a medias.
 */
@Service
public class StockService {

    private static final Logger log = LoggerFactory.getLogger(StockService.class);

    private final ProductoRepository repositorio;

    public StockService(ProductoRepository repositorio) {
        this.repositorio = repositorio;
    }

    @Transactional
    public OperacionStockResponse reservar(OperacionStockRequest request) {
        Map<Long, Integer> consolidado = consolidar(request.items());
        List<Producto> bloqueados = bloquearEnOrden(consolidado.keySet());

        List<String> faltantes = new ArrayList<>();
        for (Producto producto : bloqueados) {
            int solicitado = consolidado.get(producto.getId());
            if (!Boolean.TRUE.equals(producto.getActivo())) {
                faltantes.add("El producto " + producto.getSku() + " esta inactivo y no puede venderse");
            } else if (producto.getStock() < solicitado) {
                faltantes.add("Stock insuficiente para " + producto.getSku()
                        + ": solicitado " + solicitado + ", disponible " + producto.getStock());
            }
        }
        if (!faltantes.isEmpty()) {
            throw new ReglaNegocioException("No es posible reservar el stock solicitado", faltantes);
        }

        List<OperacionStockResponse.LineaStockResultado> resultados = new ArrayList<>();
        for (Producto producto : bloqueados) {
            int solicitado = consolidado.get(producto.getId());
            producto.descontarStock(solicitado);
            resultados.add(new OperacionStockResponse.LineaStockResultado(
                    producto.getId(), producto.getSku(), solicitado, producto.getStock()));
        }
        repositorio.saveAll(bloqueados);

        log.info("Stock reservado. referencia={} lineas={}", request.referencia(), resultados.size());
        return new OperacionStockResponse("RESERVA", request.referencia(), resultados);
    }

    @Transactional
    public OperacionStockResponse liberar(OperacionStockRequest request) {
        Map<Long, Integer> consolidado = consolidar(request.items());
        List<Producto> bloqueados = bloquearEnOrden(consolidado.keySet());

        List<OperacionStockResponse.LineaStockResultado> resultados = new ArrayList<>();
        for (Producto producto : bloqueados) {
            int cantidad = consolidado.get(producto.getId());
            producto.reponerStock(cantidad);
            resultados.add(new OperacionStockResponse.LineaStockResultado(
                    producto.getId(), producto.getSku(), cantidad, producto.getStock()));
        }
        repositorio.saveAll(bloqueados);

        log.info("Stock liberado. referencia={} lineas={}", request.referencia(), resultados.size());
        return new OperacionStockResponse("LIBERACION", request.referencia(), resultados);
    }

    /** Suma las cantidades repetidas del mismo producto para bloquear cada fila una sola vez. */
    private Map<Long, Integer> consolidar(List<LineaStockRequest> items) {
        Map<Long, Integer> consolidado = new LinkedHashMap<>();
        for (LineaStockRequest item : items) {
            consolidado.merge(item.productoId(), item.cantidad(), Integer::sum);
        }
        return consolidado;
    }

    /**
     * Bloquea las filas siempre en el mismo orden (por id ascendente). Dos reservas
     * concurrentes que toquen los mismos productos se serializan en vez de generar deadlock.
     */
    private List<Producto> bloquearEnOrden(Iterable<Long> ids) {
        List<Long> ordenados = new ArrayList<>();
        ids.forEach(ordenados::add);
        ordenados.sort(Long::compareTo);

        List<Producto> productos = new ArrayList<>(ordenados.size());
        for (Long id : ordenados) {
            productos.add(repositorio.findByIdParaActualizar(id)
                    .orElseThrow(() -> new RecursoNoEncontradoException("No existe el producto con id " + id)));
        }
        return productos;
    }
}
