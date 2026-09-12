package cl.duoc.pedidos360.orders.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.SequenceGenerator;
import jakarta.persistence.Table;

import java.math.BigDecimal;

/**
 * Linea de un pedido. Guarda una foto del precio y del nombre al momento de la
 * compra: si el catalogo sube el precio manana, el pedido historico no cambia.
 */
@Entity
@Table(name = "PEDIDO_ITEM")
public class PedidoItem {

    @Id
    @GeneratedValue(strategy = GenerationType.SEQUENCE, generator = "pedidoItemSeqGen")
    @SequenceGenerator(name = "pedidoItemSeqGen", sequenceName = "PEDIDO_ITEM_SEQ", allocationSize = 1)
    @Column(name = "ID")
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "PEDIDO_ID", nullable = false, foreignKey = @jakarta.persistence.ForeignKey(name = "FK_ITEM_PEDIDO"))
    private Pedido pedido;

    @Column(name = "PRODUCTO_ID", nullable = false)
    private Long productoId;

    @Column(name = "SKU", nullable = false, length = 40)
    private String sku;

    @Column(name = "NOMBRE_PRODUCTO", nullable = false, length = 150)
    private String nombreProducto;

    @Column(name = "CANTIDAD", nullable = false)
    private Integer cantidad;

    @Column(name = "PRECIO_UNITARIO", nullable = false, precision = 12, scale = 2)
    private BigDecimal precioUnitario;

    @Column(name = "SUBTOTAL", nullable = false, precision = 14, scale = 2)
    private BigDecimal subtotal;

    protected PedidoItem() {
        // requerido por JPA
    }

    public PedidoItem(Long productoId, String sku, String nombreProducto,
                      Integer cantidad, BigDecimal precioUnitario) {
        this.productoId = productoId;
        this.sku = sku;
        this.nombreProducto = nombreProducto;
        this.cantidad = cantidad;
        this.precioUnitario = precioUnitario;
        this.subtotal = precioUnitario.multiply(BigDecimal.valueOf(cantidad));
    }

    void asociarA(Pedido pedido) {
        this.pedido = pedido;
    }

    public Long getId() {
        return id;
    }

    public Pedido getPedido() {
        return pedido;
    }

    public Long getProductoId() {
        return productoId;
    }

    public String getSku() {
        return sku;
    }

    public String getNombreProducto() {
        return nombreProducto;
    }

    public Integer getCantidad() {
        return cantidad;
    }

    public BigDecimal getPrecioUnitario() {
        return precioUnitario;
    }

    public BigDecimal getSubtotal() {
        return subtotal;
    }
}
