package cl.duoc.pedidos360.orders.client;

import cl.duoc.pedidos360.orders.client.dto.ErrorCatalogoDto;
import cl.duoc.pedidos360.orders.client.dto.LineaStockDto;
import cl.duoc.pedidos360.orders.client.dto.OperacionStockDto;
import cl.duoc.pedidos360.orders.client.dto.ProductoCatalogoDto;
import cl.duoc.pedidos360.orders.exception.CatalogoNoDisponibleException;
import cl.duoc.pedidos360.orders.exception.RecursoNoEncontradoException;
import cl.duoc.pedidos360.orders.exception.ReglaNegocioException;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatusCode;
import org.springframework.http.client.ClientHttpResponse;
import org.springframework.stereotype.Component;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestClient;

import java.util.List;

/**
 * Comunicacion sincrona pedidos -> catalogo.
 *
 * Traduce los errores del catalogo a excepciones del dominio de pedidos para que
 * el BFF reciba siempre un contrato de error coherente, y distingue el caso
 * "el catalogo dijo que no" (409, culpa del cliente) del caso "el catalogo no
 * contesta" (503, culpa de la infraestructura).
 */
@Component
public class CatalogClient {

    private static final Logger log = LoggerFactory.getLogger(CatalogClient.class);

    private final RestClient rest;
    private final ObjectMapper mapper;
    private final String baseUrl;

    public CatalogClient(RestClient catalogRestClient,
                         ObjectMapper mapper,
                         @Value("${catalog.base-url:http://localhost:8082}") String baseUrl) {
        this.rest = catalogRestClient;
        this.mapper = mapper;
        this.baseUrl = baseUrl;
    }

    public ProductoCatalogoDto obtenerProducto(Long productoId) {
        try {
            return rest.get()
                    .uri("/api/catalog/{id}", productoId)
                    .retrieve()
                    .onStatus(esEstado(404), (request, response) -> {
                        throw new RecursoNoEncontradoException(
                                "El producto " + productoId + " no existe en el catalogo");
                    })
                    .onStatus(HttpStatusCode::isError, (request, response) -> {
                        throw new CatalogoNoDisponibleException("El catalogo respondio "
                                + response.getStatusCode() + " al consultar el producto " + productoId);
                    })
                    .body(ProductoCatalogoDto.class);
        } catch (ResourceAccessException ex) {
            throw noDisponible(ex);
        }
    }

    /** Descuenta stock. Lanza ReglaNegocioException (-> 409) si el catalogo lo rechaza. */
    public void reservarStock(String referencia, List<LineaStockDto> items) {
        ejecutarMovimiento("/api/catalog/stock/reservar", referencia, items, "reservar");
    }

    /** Repone stock al cancelar un pedido que ya lo habia descontado. */
    public void liberarStock(String referencia, List<LineaStockDto> items) {
        ejecutarMovimiento("/api/catalog/stock/liberar", referencia, items, "liberar");
    }

    private void ejecutarMovimiento(String ruta, String referencia,
                                    List<LineaStockDto> items, String operacion) {
        try {
            rest.post()
                    .uri(ruta)
                    .body(new OperacionStockDto(items, referencia))
                    .retrieve()
                    .onStatus(esEstado(409), (request, response) -> {
                        ErrorCatalogoDto error = leerError(response);
                        throw new ReglaNegocioException(
                                error != null && error.mensaje() != null
                                        ? error.mensaje()
                                        : "El catalogo rechazo la operacion de stock",
                                error != null ? error.detalles() : null);
                    })
                    .onStatus(esEstado(404), (request, response) -> {
                        ErrorCatalogoDto error = leerError(response);
                        throw new RecursoNoEncontradoException(
                                error != null && error.mensaje() != null
                                        ? error.mensaje()
                                        : "El catalogo no encontro alguno de los productos del pedido");
                    })
                    .onStatus(HttpStatusCode::isError, (request, response) -> {
                        throw new CatalogoNoDisponibleException("El catalogo respondio "
                                + response.getStatusCode() + " al " + operacion + " stock");
                    })
                    .toBodilessEntity();

            log.info("Movimiento de stock '{}' aplicado. referencia={} lineas={}",
                    operacion, referencia, items.size());
        } catch (ResourceAccessException ex) {
            throw noDisponible(ex);
        }
    }

    private CatalogoNoDisponibleException noDisponible(ResourceAccessException ex) {
        log.error("Catalogo inalcanzable en {}", baseUrl, ex);
        return new CatalogoNoDisponibleException(
                "No fue posible contactar al microservicio de catalogo en " + baseUrl, ex);
    }

    private static java.util.function.Predicate<HttpStatusCode> esEstado(int codigo) {
        return status -> status.value() == codigo;
    }

    private ErrorCatalogoDto leerError(ClientHttpResponse response) {
        try {
            return mapper.readValue(response.getBody(), ErrorCatalogoDto.class);
        } catch (Exception ex) {
            log.warn("No se pudo interpretar el cuerpo de error del catalogo: {}", ex.getMessage());
            return null;
        }
    }
}
