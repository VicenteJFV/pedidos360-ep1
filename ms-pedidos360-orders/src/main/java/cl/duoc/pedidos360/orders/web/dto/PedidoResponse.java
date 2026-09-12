package cl.duoc.pedidos360.orders.web.dto;

import cl.duoc.pedidos360.orders.domain.EstadoPedido;
import cl.duoc.pedidos360.orders.domain.Pedido;
import cl.duoc.pedidos360.orders.domain.PedidoItem;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Set;

public record PedidoResponse(
        Long id,
        String codigo,
        String clienteEmail,
        String clienteNombre,
        EstadoPedido estado,
        /** Transiciones que el frontend puede ofrecer como botones sin adivinar. */
        Set<EstadoPedido> transicionesPermitidas,
        BigDecimal total,
        String direccionEntrega,
        String observacion,
        LocalDateTime fechaCreacion,
        LocalDateTime fechaActualizacion,
        List<ItemResponse> items
) {

    public record ItemResponse(
            Long id,
            Long productoId,
            String sku,
            String nombreProducto,
            Integer cantidad,
            BigDecimal precioUnitario,
            BigDecimal subtotal
    ) {
        static ItemResponse desde(PedidoItem item) {
            return new ItemResponse(
                    item.getId(),
                    item.getProductoId(),
                    item.getSku(),
                    item.getNombreProducto(),
                    item.getCantidad(),
                    item.getPrecioUnitario(),
                    item.getSubtotal()
            );
        }
    }

    /** Debe invocarse dentro de la transaccion: recorre la coleccion LAZY de items. */
    public static PedidoResponse desde(Pedido pedido) {
        return new PedidoResponse(
                pedido.getId(),
                pedido.getCodigo(),
                pedido.getClienteEmail(),
                pedido.getClienteNombre(),
                pedido.getEstado(),
                pedido.getEstado().transicionesPermitidas(),
                pedido.getTotal(),
                pedido.getDireccionEntrega(),
                pedido.getObservacion(),
                pedido.getFechaCreacion(),
                pedido.getFechaActualizacion(),
                pedido.getItems().stream().map(ItemResponse::desde).toList()
        );
    }
}
