package cl.duoc.pedidos360.orders.client.dto;

import java.util.List;

public record OperacionStockDto(List<LineaStockDto> items, String referencia) {
}
